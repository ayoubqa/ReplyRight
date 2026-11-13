import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { BetaContentBlockParam, BetaMessageParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { z } from "zod";
import {
  analysisSchema,
  coachResultSchema,
  LIMITS,
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
import { recordAiFailure, recordAiSuccess } from "./health";
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
  /** Set when the API refuses the optional refusal-fallback parameter, so later calls skip it. */
  private fallbacksRejected = false;

  constructor(options: AnthropicProviderOptions) {
    this.models = options.models;
    this.efforts = options.efforts;
    // The SDK retries 408/409/429/5xx and connection errors with backoff. One
    // retry at 45 seconds keeps the worst case close to the app's own timeout,
    // so the server is not still working on an answer nobody is waiting for.
    this.client = new Anthropic({ apiKey: options.apiKey, timeout: options.timeoutMs ?? 45_000, maxRetries: 1 });
  }

  modelFor(task: AiTask): string {
    return this.models[task];
  }

  async analyze({ request, images }: { request: AnalyzeRequest; images: TransientImage[] }): Promise<Analysis> {
    const parsed = await this.run("analyze", ANALYZE_SYSTEM, analysisSchema, [
      { role: "user", content: [...imageBlocks(images), { type: "text", text: buildAnalyzePrompt(request, images.length) }] },
    ]);
    return normalizeAnalysis(parsed);
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
    const turns: BetaMessageParam[] = request.messages.map((m) => ({
      role: m.role === "user" ? "user" : "assistant",
      content: m.text,
    }));
    // The API needs the exchange to open and close on a user turn. Context opens
    // it; in practice and review mode a closing instruction ends it.
    const messages: BetaMessageParam[] = [];
    if (turns.length > 0 && turns[0].role === "user") {
      messages.push({ role: "user", content: `${context}\n\n${turns[0].content as string}` }, ...turns.slice(1));
    } else {
      messages.push({ role: "user", content: context }, ...turns);
    }
    const closing = coachClosingTurn(request);
    if (messages[messages.length - 1].role === "assistant") {
      messages.push({ role: "user", content: closing ?? "Go on." });
    } else if (closing) {
      const last = messages[messages.length - 1];
      messages[messages.length - 1] = { role: "user", content: `${last.content as string}\n\n${closing}` };
    }

    const parsed = await this.run("coach", COACH_SYSTEM, coachResultSchema, messages);
    return {
      ...parsed,
      suggestions: parsed.suggestions.slice(0, 3),
      followUps: parsed.followUps.slice(0, 3),
      review: parsed.review ? { ...parsed.review, improvements: parsed.review.improvements.slice(0, 3) } : null,
      practice: request.mode === "practice" ? parsed.practice : null,
    };
  }

  private async run<Schema extends z.ZodType>(
    task: AiTask,
    system: string,
    schema: Schema,
    messages: BetaMessageParam[],
  ): Promise<z.infer<Schema>> {
    const model = this.models[task];
    const started = Date.now();
    const send = (withFallbacks: boolean) =>
      this.client.beta.messages.parse({
        model,
        max_tokens: 16000,
        system,
        messages,
        output_config: { effort: this.efforts[task], format: betaZodOutputFormat(schema) },
        ...(withFallbacks ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
      });

    let response: Awaited<ReturnType<typeof send>>;
    const useFallbacks = FALLBACK_MODELS.has(model) && !this.fallbacksRejected;
    try {
      try {
        response = await send(useFallbacks);
      } catch (error) {
        // The refusal fallback is an optional extra. If this account, model or
        // platform does not accept the parameter, carry on without it instead
        // of failing every request.
        if (useFallbacks && error instanceof Anthropic.BadRequestError && /fallback|beta/i.test(error.message)) {
          this.fallbacksRejected = true;
          console.warn("[replyright] The API did not accept the refusal fallback parameter. Continuing without it.");
          response = await send(false);
        } else {
          throw error;
        }
      }
    } catch (error) {
      const mapped = mapAnthropicError(error);
      recordAiFailure(mapped.reason);
      throw mapped;
    }
    recordAiSuccess();

    this.onMetrics?.({
      task,
      model: response.model,
      latencyMs: Date.now() - started,
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
    });

    if (response.stop_reason === "refusal") {
      throw new ProviderError("declined", "I can't help with this one. Try sharing a different part of the conversation.", {
        reason: "refusal",
      });
    }
    if (response.stop_reason === "max_tokens") {
      throw new ProviderError("bad_output", "That answer got cut short. Please try again.", { reason: "output" });
    }
    const parsed = response.parsed_output;
    if (!parsed) {
      throw new ProviderError("bad_output", "Something came back garbled. Please try again.", { reason: "output" });
    }
    return parsed as z.infer<Schema>;
  }
}

/** The instruction that closes a coaching exchange, depending on the mode. */
function coachClosingTurn(request: CoachRequest): string | null {
  if (request.mode === "review") {
    return "Look at my message and coach me on it. Fill in review.";
  }
  if (request.mode === "practice") {
    return request.messages.length === 0
      ? "Set up the practice. Tell me briefly who you are playing and what the situation is, then either send their first message or ask me to send mine."
      : "Stay in the practice: give me feedback on what I just sent, then answer as them.";
  }
  return null;
}

/**
 * Screenshots as image content blocks, in the order the user attached them.
 * They come before the text that refers to them, as the API recommends.
 */
export function imageBlocks(images: TransientImage[]): BetaContentBlockParam[] {
  return images.map(
    (image): BetaContentBlockParam => ({
      type: "image",
      source: { type: "base64", media_type: image.mediaType, data: image.base64 },
    }),
  );
}

const clean = (text: string) => text.replace(/\s+/g, " ").trim();

/**
 * Makes the analysis consistent before it reaches the app. Structured output
 * guarantees the shape; this enforces what the schema cannot express.
 *
 * It removes and trims, and it refuses an answer with nothing to show. It never
 * adds content the model did not write.
 */
export function normalizeAnalysis(parsed: Analysis): Analysis {
  const read = parsed.read.trim();
  if (!read) {
    throw new ProviderError("bad_output", "Something came back garbled. Please try again.", { reason: "output" });
  }
  const transcript = parsed.transcript
    .map((line) => ({ speaker: line.speaker, text: line.text.trim().slice(0, LIMITS.transcriptLineChars) }))
    .filter((line) => line.text.length > 0)
    .slice(-LIMITS.transcriptLines);
  const latestMessage = parsed.latestMessage?.trim() || null;
  // Nothing can be answered from a screenshot that could not be read, or from something that is not a conversation.
  const unusable = parsed.problem === "unreadable" || parsed.problem === "not_a_conversation";
  return {
    ...parsed,
    canReply: parsed.canReply && !unusable,
    read,
    transcript,
    latestMessage,
    toneLabel: clean(parsed.toneLabel),
    observations: parsed.observations.map(clean).filter(Boolean).slice(0, 4),
    assumptions: parsed.assumptions.map(clean).filter(Boolean).slice(0, 3),
    opportunity: parsed.opportunity.trim(),
    suggestedIntents: [...new Set(parsed.suggestedIntents)].slice(0, 3),
    headsUp: parsed.headsUp?.trim() || null,
  };
}

/** True when the API refused the request because of an image in it. */
function isImageRejection(error: InstanceType<typeof Anthropic.BadRequestError>): boolean {
  return /\bimage\b|media_type|base64/i.test(error.message);
}

/**
 * Whether the provider's own error text may be written to the server log.
 * It describes parameters, not conversations, but it stays out of production
 * logs unless someone asks for it with RR_DEBUG_ERRORS=true.
 */
function logsProviderMessages(): boolean {
  const flag = process.env.RR_DEBUG_ERRORS?.trim().toLowerCase();
  if (flag === "true" || flag === "1") return true;
  if (flag === "false" || flag === "0") return false;
  return process.env.NODE_ENV !== "production";
}

function describe(error: InstanceType<typeof Anthropic.APIError>): string {
  const parts = [`status ${error.status ?? "none"}`];
  if (error.requestID) parts.push(`request ${error.requestID}`);
  if (logsProviderMessages()) parts.push(error.message.slice(0, 300));
  return parts.join(", ");
}

/**
 * Maps SDK errors to typed provider errors with a coarse reason for
 * diagnostics. Logs status and request id, never request content.
 */
function mapAnthropicError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  const notSetUp = "ReplyRight isn't set up correctly on our side. Please try again later.";

  if (error instanceof Anthropic.RateLimitError) {
    console.error(`[replyright] Anthropic rate limit (${describe(error)}).`);
    return new ProviderError("rate_limited", "Things are busy right now. Give it a moment and try again.", {
      cause: error,
      reason: "rate_limit",
    });
  }
  if (error instanceof Anthropic.AuthenticationError) {
    console.error(`[replyright] Anthropic rejected the API key (${describe(error)}). Check ANTHROPIC_API_KEY.`);
    return new ProviderError("unavailable", notSetUp, { cause: error, reason: "credentials" });
  }
  if (error instanceof Anthropic.PermissionDeniedError) {
    console.error(`[replyright] The API key may not use this model or feature (${describe(error)}).`);
    return new ProviderError("unavailable", notSetUp, { cause: error, reason: "credentials" });
  }
  if (error instanceof Anthropic.NotFoundError) {
    console.error(`[replyright] Anthropic does not know the configured model (${describe(error)}). Check AI_MODEL.`);
    return new ProviderError("unavailable", notSetUp, { cause: error, reason: "model" });
  }
  if (error instanceof Anthropic.BadRequestError) {
    if (/credit balance|billing/i.test(error.message)) {
      console.error(`[replyright] The Anthropic account has no credit (${describe(error)}).`);
      return new ProviderError("unavailable", notSetUp, { cause: error, reason: "billing" });
    }
    if (isImageRejection(error)) {
      // Images are fully decoded and normalised before they are sent, so this
      // should be rare. The message names the field, never the image content.
      console.error(`[replyright] Anthropic could not use an image (${describe(error)}).`);
      return new ProviderError(
        "rejected_input",
        "I couldn't read one of those screenshots. Try taking it again, or paste the text instead.",
        { cause: error, reason: "image" },
      );
    }
    console.error(`[replyright] Anthropic rejected the request (${describe(error)}).`);
    return new ProviderError("misconfigured", "Something went wrong on our side. Please try again.", {
      cause: error,
      reason: "request",
    });
  }
  // The timeout error is a kind of connection error, so it is checked first.
  if (error instanceof Anthropic.APIConnectionTimeoutError) {
    console.error("[replyright] The AI provider took too long to answer.");
    return new ProviderError("unavailable", "That took longer than it should. Please try again.", {
      cause: error,
      reason: "timeout",
    });
  }
  if (error instanceof Anthropic.APIConnectionError) {
    console.error("[replyright] The server could not connect to the AI provider.");
    return new ProviderError("unavailable", "I couldn't reach the writing service. Please try again.", {
      cause: error,
      reason: "network",
    });
  }
  if (error instanceof Anthropic.InternalServerError) {
    console.error(`[replyright] The AI provider is having trouble (${describe(error)}).`);
    return new ProviderError("unavailable", "The writing service is busy right now. Please try again.", {
      cause: error,
      reason: "overloaded",
    });
  }
  if (error instanceof Anthropic.APIError) {
    console.error(`[replyright] Anthropic API error (${describe(error)}).`);
    return new ProviderError("unavailable", "Something went wrong on our side. Please try again.", { cause: error });
  }
  // Output that failed schema validation surfaces as a parse error from the SDK helper.
  console.error("[replyright] Unexpected AI error:", error instanceof Error ? error.name : "unknown");
  return new ProviderError("bad_output", "Something came back garbled. Please try again.", {
    cause: error,
    reason: "output",
  });
}
