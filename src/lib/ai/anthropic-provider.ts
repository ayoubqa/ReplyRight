import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { BetaContentBlockParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { replyResultSchema, type ReplyResult } from "@/lib/domain/replies";
import { buildUserPrompt, SYSTEM_PROMPT } from "./prompt";
import { ProviderError, type GenerateRepliesInput, type ReplyProvider } from "./types";

type Effort = "low" | "medium" | "high";

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
  model: string;
  effort: Effort;
}

export class AnthropicReplyProvider implements ReplyProvider {
  readonly id = "anthropic";
  readonly mode = "live" as const;
  readonly supportsImages = true;
  readonly model: string;
  private readonly client: Anthropic;
  private readonly effort: Effort;

  constructor(options: AnthropicProviderOptions) {
    this.model = options.model;
    this.effort = options.effort;
    this.client = new Anthropic({ apiKey: options.apiKey, timeout: 90_000, maxRetries: 1 });
  }

  async generateReplies({ request, images }: GenerateRepliesInput): Promise<ReplyResult> {
    const content: BetaContentBlockParam[] = [
      ...images.map(
        (image): BetaContentBlockParam => ({
          type: "image",
          source: { type: "base64", media_type: image.mediaType, data: image.base64 },
        }),
      ),
      { type: "text", text: buildUserPrompt(request, images.length) },
    ];

    const useFallbacks = FALLBACK_MODELS.has(this.model);

    let response;
    try {
      response = await this.client.beta.messages.parse({
        model: this.model,
        max_tokens: 16000,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content }],
        output_config: {
          effort: this.effort,
          format: betaZodOutputFormat(replyResultSchema),
        },
        ...(useFallbacks
          ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const }
          : {}),
      });
    } catch (error) {
      throw mapAnthropicError(error);
    }

    if (response.stop_reason === "refusal") {
      throw new ProviderError(
        "declined",
        "The AI declined to help with this conversation. Try rephrasing or sharing a different part of it.",
      );
    }
    if (response.stop_reason === "max_tokens") {
      throw new ProviderError("bad_output", "The AI response was cut short. Please try again.");
    }

    const parsed = response.parsed_output;
    if (!parsed) {
      throw new ProviderError("bad_output", "The AI returned an unexpected response. Please try again.");
    }

    return {
      ...parsed,
      read: { ...parsed.read, cues: parsed.read.cues.slice(0, 3) },
      replies: parsed.replies.slice(0, 3),
    };
  }
}

function mapAnthropicError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  if (error instanceof Anthropic.RateLimitError) {
    return new ProviderError("rate_limited", "The AI is busy right now. Try again in a moment.", { cause: error });
  }
  if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    console.error("[replyright] Anthropic credentials rejected. Check ANTHROPIC_API_KEY.");
    return new ProviderError("unavailable", "The AI service isn't configured correctly.", { cause: error });
  }
  if (error instanceof Anthropic.BadRequestError) {
    console.error("[replyright] Anthropic rejected the request:", error.message);
    return new ProviderError("bad_output", "The AI couldn't process this input. Try a clearer screenshot or fewer images.", { cause: error });
  }
  if (error instanceof Anthropic.APIConnectionError || error instanceof Anthropic.InternalServerError) {
    return new ProviderError("unavailable", "Couldn't reach the AI service. Please try again.", { cause: error });
  }
  if (error instanceof Anthropic.APIError) {
    console.error(`[replyright] Anthropic API error ${error.status}:`, error.message);
    return new ProviderError("unavailable", "The AI service had a problem. Please try again.", { cause: error });
  }
  // Output that failed schema validation surfaces as a parse error from the SDK helper.
  console.error("[replyright] Unexpected AI error:", error);
  return new ProviderError("bad_output", "The AI returned an unexpected response. Please try again.", { cause: error });
}
