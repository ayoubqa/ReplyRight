import "server-only";
import { AnthropicProvider, type Effort } from "./anthropic-provider";
import { DemoProvider } from "./demo-provider";
import { AI_TASKS, type AiProvider, type AiTask } from "./types";

export type { AiProvider, AiTask } from "./types";
export { ProviderError } from "./types";

/**
 * Model strategy
 * --------------
 * The model is chosen per task from environment variables so production can
 * trade naturalness, latency and cost without a code change:
 *
 *   AI_MODEL                  default for every task
 *   AI_MODEL_ANALYZE / _REPLIES / _REFINE / _COACH   per-task override
 *   AI_EFFORT                 low | medium | high for every task
 *   AI_EFFORT_ANALYZE / ...   per-task override
 *
 * Pick production values with the eval harness in `backend/evals`
 * (`npm run eval`), which compares candidate models on the same cases.
 */
export const DEFAULT_MODEL = "claude-opus-5-5";

const DEFAULT_EFFORT: Record<AiTask, Effort> = {
  analyze: "low",
  replies: "medium",
  refine: "low",
  coach: "medium",
};

let cached: AiProvider | null = null;

function env(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

function parseEffort(value: string | undefined): Effort | undefined {
  const v = value?.toLowerCase();
  return v === "low" || v === "medium" || v === "high" ? v : undefined;
}

export function resolveModels(): Record<AiTask, string> {
  // ANTHROPIC_MODEL is honoured for backwards compatibility with the first release.
  const base = env("AI_MODEL") ?? env("ANTHROPIC_MODEL") ?? DEFAULT_MODEL;
  return Object.fromEntries(
    AI_TASKS.map((task) => [task, env(`AI_MODEL_${task.toUpperCase()}`) ?? base]),
  ) as Record<AiTask, string>;
}

export function resolveEfforts(): Record<AiTask, Effort> {
  const base = parseEffort(env("AI_EFFORT"));
  return Object.fromEntries(
    AI_TASKS.map((task) => [task, parseEffort(env(`AI_EFFORT_${task.toUpperCase()}`)) ?? base ?? DEFAULT_EFFORT[task]]),
  ) as Record<AiTask, Effort>;
}

/**
 * Resolves the configured provider (server only).
 *
 *   AI_PROVIDER = "anthropic" | "demo"  (optional; inferred from credentials)
 *   ANTHROPIC_API_KEY                   (required for "anthropic")
 */
export function getProvider(): AiProvider {
  if (cached) return cached;

  const requested = env("AI_PROVIDER")?.toLowerCase();
  const apiKey = env("ANTHROPIC_API_KEY");

  if (requested === "demo" || (!requested && !apiKey)) {
    cached = new DemoProvider();
  } else if (requested === "anthropic" || !requested) {
    if (!apiKey) {
      console.warn("[replyright] AI_PROVIDER=anthropic but ANTHROPIC_API_KEY is missing. Falling back to demo mode.");
      cached = new DemoProvider();
    } else {
      cached = new AnthropicProvider({ apiKey, models: resolveModels(), efforts: resolveEfforts() });
    }
  } else {
    console.warn(`[replyright] Unknown AI_PROVIDER "${requested}". Falling back to demo mode.`);
    cached = new DemoProvider();
  }
  return cached;
}

/** For tests. */
export function resetProviderCache() {
  cached = null;
}
