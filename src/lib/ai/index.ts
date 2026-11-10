import "server-only";
import { AnthropicReplyProvider } from "./anthropic-provider";
import { DemoReplyProvider } from "./demo-provider";
import type { ReplyProvider } from "./types";

export type { ReplyProvider } from "./types";
export { ProviderError } from "./types";

const DEFAULT_ANTHROPIC_MODEL = "claude-opus-5-5";

let cached: ReplyProvider | null = null;

/**
 * Resolves the configured provider from environment variables (server only).
 *
 * AI_PROVIDER = "anthropic" | "demo"   (optional; inferred from credentials)
 * ANTHROPIC_API_KEY                    (required for "anthropic")
 * ANTHROPIC_MODEL                      (optional, default claude-opus-5-5)
 * AI_EFFORT = "low" | "medium" | "high" (optional, default medium)
 */
export function getReplyProvider(): ReplyProvider {
  if (cached) return cached;

  const requested = process.env.AI_PROVIDER?.trim().toLowerCase();
  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();

  if (requested === "demo" || (!requested && !apiKey)) {
    cached = new DemoReplyProvider();
  } else if (requested === "anthropic" || (!requested && apiKey)) {
    if (!apiKey) {
      console.warn("[replyright] AI_PROVIDER=anthropic but ANTHROPIC_API_KEY is missing. Falling back to demo mode.");
      cached = new DemoReplyProvider();
    } else {
      cached = new AnthropicReplyProvider({
        apiKey,
        model: process.env.ANTHROPIC_MODEL?.trim() || DEFAULT_ANTHROPIC_MODEL,
        effort: parseEffort(process.env.AI_EFFORT),
      });
    }
  } else {
    console.warn(`[replyright] Unknown AI_PROVIDER "${requested}". Falling back to demo mode.`);
    cached = new DemoReplyProvider();
  }

  return cached;
}

function parseEffort(value: string | undefined): "low" | "medium" | "high" {
  const v = value?.trim().toLowerCase();
  return v === "low" || v === "high" ? v : "medium";
}

/** Safe, non-secret summary for rendering in the UI. */
export function getAiStatus() {
  const provider = getReplyProvider();
  return { mode: provider.mode, provider: provider.id, supportsImages: provider.supportsImages };
}
export type AiStatus = ReturnType<typeof getAiStatus>;
