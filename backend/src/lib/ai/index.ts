import "server-only";
import { AnthropicProvider, type Effort } from "./anthropic-provider";
import { anyAnthropicKeyConfigured, resolveAnthropicKey } from "./credentials";
import { DemoProvider } from "./demo-provider";
import { describeRoutes, resolveRoutes } from "./router";
import { AI_TASKS, type AiProvider, type AiTask } from "./types";

export type { AiProvider, AiTask } from "./types";
export { ProviderError } from "./types";

/**
 * Model strategy
 * --------------
 * Models are chosen per route by the ModelRouter (`./router.ts`): Haiku,
 * Sonnet or Opus depending on what was asked for. Every assignment can be
 * changed from the environment without touching an endpoint:
 *
 *   AI_ROUTE_<ROUTE>          one route, e.g. AI_ROUTE_REFINE="claude-sonnet-5-5"
 *   AI_MODEL                  one model for every route (overrides the router's defaults)
 *   AI_MODEL_ANALYZE / _REPLIES / _REFINE / _COACH   one model for every route of a task
 *   AI_EFFORT, AI_EFFORT_<TASK>                      reasoning effort, as before
 *   AI_ROUTING=off            the pre-routing setup: claude-opus-5-5 everywhere
 *
 * Check candidates with the eval harness in `backend/evals` (`npm run eval`).
 * `resolveModels` and `resolveEfforts` below are the per-task view used by
 * the eval harness and by AI_ROUTING=off.
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
 *   ANTHROPIC_API_KEY                   production key, used only in production
 *   ANTHROPIC_API_KEY_DEV               development key, used everywhere else
 *
 * See `./credentials.ts`. Without a key this environment may use, the server
 * runs in the labelled demo mode.
 */
export function getProvider(): AiProvider {
  if (cached) return cached;

  const requested = env("AI_PROVIDER")?.toLowerCase();
  if (requested === "demo") {
    cached = new DemoProvider();
    return cached;
  }
  if (requested && requested !== "anthropic") {
    console.warn(`[replyright] Unknown AI_PROVIDER "${requested}". Falling back to demo mode.`);
    cached = new DemoProvider();
    return cached;
  }

  const key = resolveAnthropicKey();
  if (!key.ok) {
    // Quiet when nothing is configured at all, as before. Loud when a key is
    // present but this environment may not use it, or live AI was asked for.
    if (requested === "anthropic" || anyAnthropicKeyConfigured()) {
      console.warn(`[replyright] ${key.message} Running in demo mode.`);
    }
    cached = new DemoProvider();
    return cached;
  }
  console.info(`[replyright] Live AI in ${key.environment} using ${key.source}.`);
  const { routes, problems } = resolveRoutes();
  for (const problem of problems) console.warn(`[replyright] ${problem.variable}: ${problem.message}`);
  console.info(`[replyright] AI routes: ${describeRoutes(routes)}`);
  cached = new AnthropicProvider({ apiKey: key.apiKey, routes, environment: key.environment });
  return cached;
}

/** For tests. */
export function resetProviderCache() {
  cached = null;
}

/** For tests: use this provider until the cache is reset. */
export function setProviderForTests(provider: AiProvider) {
  cached = provider;
}
