import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { BetaContentBlockParam, BetaMessageParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { z } from "zod";
import {
  analysisSchema,
  coachResultSchema,
  refineResultSchema,
  repliesResultSchema,
  type Analysis,
  type AnalyzeRequest,
  type CoachRequest,
  type CoachResult,
  type RefineRequest,
  type RefineResult,
  type RepliesRequest,
  type RepliesResult,
} from "@/lib/domain/contracts";
import {
  ANALYZE_SYSTEM,
  buildAnalyzePrompt,
  buildCoachContext,
  buildRefinePrompt,
  buildRepliesPrompt,
  COACH_SYSTEM,
  REFINE_SYSTEM,
  REPLIES_SYSTEM,
} from "./prompts/tasks";
import { ProviderError, type AiProvider, type AiTask, type TaskOptions, type TransientImage } from "./types";

export type Effort = "low" | "medium" | "high";

/** Models that accept the server-side refusal fallback parameter. */
const FALLBACK_MODELS = new Set([
  "claude-opus-5-5",
  "claude-opus-5",
  "claude-sonnet-5-5",
  "claude-fable-5-2",
  "claude-fable-5-1",
]);

export interface AnthropicProviderOptions {
  apiKey: string;
  models: Record<AiTask, string>;
  efforts: Record<AiTask, Effort>;
  timeoutMs?: number;
}

export interface CallMetrics {
  task: AiTask;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
}

export class AnthropicProvider implements AiProvider {
  readonly id = "anthropic";
  readonly mode = "live" as const;
  readonly supportsImages = true;
  private readonly client: Anthropic;
  private readonly models: Record<AiTask, string>;
  private readonly efforts: Record<AiTask, Effort>;
  /** Optional hook for evals: receives token and latency metrics per call. Never receives content. */
  onMetrics: ((metrics: CallMetrics) => void) | null = null;

  constructor(options: AnthropicProviderOptions) {
    this.models = options.models;
    this.efforts = options.efforts;
    // The SDK retries 408/409/429/5xx and connection errors with backoff.
    this.client = new Anthropic({ apiKey: options.apiKey, timeout: options.timeoutMs ?? 60_000, maxRetries: 2 });
  }

  modelFor(task: AiTask): string {
    return this.models[task];
  }

  async analyze({ request, images }: { request: AnalyzeRequest; images: TransientImage[] }): Promise<Analysis> {
    const parsed = await this.run("analyze", ANALYZE_SYSTEM, analysisSchema, [
      { role: "user", content: [...imageBlocks(images), { type: "text", text: buildAnalyzePrompt(request, images.length) }] },
    ]);
    return {
      ...parsed,
      observations: parsed.observations.slice(0, 4),
      assumptions: parsed.assumptions.slice(0, 3),
      suggestedIntents: [...new Set(parsed.suggestedIntents)].slice(0, 3),
    };
  }

  async replies({
    request,
    images,
    options,
  }: {
    request: RepliesRequest;
    images: TransientImage[];
    options: TaskOptions;
  }): Promise<RepliesResult> {
    const parsed = await this.run("replies", REPLIES_SYSTEM, repliesResultSchema, [
      {
        role: "user",
        content: [...imageBlocks(images), { type: "text", text: buildRepliesPrompt(request, images.length, options) }],
      },
    ]);
    return { ...parsed, replies: parsed.replies.slice(0, 3) };
  }

  async refine({ request, options }: { request: RefineRequest; options: TaskOptions }): Promise<RefineResult> {
    const parsed = await this.run("refine", REFINE_SYSTEM, refineResultSchema, [
      { role: "user", content: buildRefinePrompt(request, options) },
    ]);
    return { ...parsed, options: parsed.options.slice(0, request.count) };
  }

  async coach({ request, options }: { request: CoachRequest; options: TaskOptions }): Promise<CoachResult> {
    const context = buildCoachContext(request, options);
    const messages: BetaMessageParam[] = request.messages.map((m) => ({
      role: m.role === "user" ? "user" : "assistant",
      content: m.text,
    }));
    // Context travels with the first user turn so the conversation always opens with "user".
    if (messages[0].role === "user") {
      messages[0] = { role: "user", content: `${context}\n\n${messages[0].content as string}` };
    } else {
      messages.unshift({ role: "user", content: context });
    }
    const parsed = await this.run("coach", COACH_SYSTEM, coachResultSchema, messages);
    return { ...parsed, suggestions: parsed.suggestions.slice(0, 3), followUps: parsed.followUps.slice(0, 3) };
  }

  private async run<Schema extends z.ZodType>(
    task: AiTask,
    system: string,
    schema: Schema,
    messages: BetaMessageParam[],
  ): Promise<z.infer<Schema>> {
    const model = this.models[task];
    const useFallbacks = FALLBACK_MODELS.has(model);
    const started = Date.now();

    let response;
    try {
      response = await this.client.beta.messages.parse({
        model,
        max_tokens: 16000,
        system,
        messages,
        output_config: { effort: this.efforts[task], format: betaZodOutputFormat(schema) },
        ...(useFallbacks ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
      });
    } catch (error) {
      throw mapAnthropicError(error);
    }

    this.onMetrics?.({
      task,
      model: response.model,
      latencyMs: Date.now() - started,
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
    });

    if (response.stop_reason === "refusal") {
      throw new ProviderError(
        "declined",
        "I can't help with this one. Try sharing a different part of the conversation.",
      );
    }
    if (response.stop_reason === "max_tokens") {
      throw new ProviderError("bad_output", "That answer got cut short. Please try again.");
    }
    const parsed = response.parsed_output;
    if (!parsed) {
      throw new ProviderError("bad_output", "Something came back garbled. Please try again.");
    }
    return parsed as z.infer<Schema>;
  }
}

function imageBlocks(images: TransientImage[]): BetaContentBlockParam[] {
  return images.map(
    (image): BetaContentBlockParam => ({
      type: "image",
      source: { type: "base64", media_type: image.mediaType, data: image.base64 },
    }),
  );
}

/** Maps SDK errors to typed provider errors. Logs status only, never request content. */
function mapAnthropicError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  if (error instanceof Anthropic.RateLimitError) {
    return new ProviderError("rate_limited", "Things are busy right now. Give it a moment and try again.", { cause: error });
  }
  if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    console.error("[replyright] Anthropic credentials rejected. Check ANTHROPIC_API_KEY.");
    return new ProviderError("unavailable", "ReplyRight isn't set up correctly on our side. Please try again later.", { cause: error });
  }
  if (error instanceof Anthropic.BadRequestError) {
    console.error(`[replyright] Anthropic rejected the request (400): ${error.message}`);
    return new ProviderError("bad_output", "I couldn't work with that. Try a clearer screenshot or fewer images.", { cause: error });
  }
  if (error instanceof Anthropic.APIConnectionError || error instanceof Anthropic.InternalServerError) {
    return new ProviderError("unavailable", "I couldn't reach the writing service. Please try again.", { cause: error });
  }
  if (error instanceof Anthropic.APIError) {
    console.error(`[replyright] Anthropic API error ${error.status}`);
    return new ProviderError("unavailable", "Something went wrong on our side. Please try again.", { cause: error });
  }
  // Output that failed schema validation surfaces as a parse error from the SDK helper.
  console.error("[replyright] Unexpected AI error:", error instanceof Error ? error.name : "unknown");
  return new ProviderError("bad_output", "Something came back garbled. Please try again.", { cause: error });
}
