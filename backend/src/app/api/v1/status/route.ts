import { getProvider } from "@/lib/ai";
import { spendStatus } from "@/lib/ai/budget";
import { aiHealth } from "@/lib/ai/health";
import { resolveRoutes, ROUTES } from "@/lib/ai/router";
import { AI_TASKS } from "@/lib/ai/types";
import { COACH_MODES, COACH_TOPICS, LIMITS, PRACTICE_SCENARIOS, REFINE_ACTIONS } from "@/lib/domain/contracts";
import { INTENT_DEFINITIONS, INTENTS } from "@/lib/domain/intents";
import { LANGUAGES, TONES } from "@/lib/domain/voice";
import { resolveTier } from "@/lib/server/entitlements";
import { serverEnvironment } from "@/lib/server/environment";
import { getPlans } from "@/lib/server/plans";
import { usageSnapshot, usageSubject } from "@/lib/server/usage";

/**
 * GET /api/v1/status
 * Tells the app whether AI is live or in demo mode, whether live calls have
 * been working, what the plans allow, and the caller's usage today.
 * Contains no secrets: model names and coarse health only, never a key.
 */
function routeModels(): Record<string, string> {
  const { routes } = resolveRoutes();
  return Object.fromEntries(ROUTES.map((key) => [key, routes[key].model]));
}

export async function GET(request: Request) {
  const provider = getProvider();
  const tier = resolveTier(request);
  // Development and staging only: how much of the AI spend limit is used. Production has no limit, so no field.
  const spend = spendStatus();
  return Response.json(
    {
      apiVersion: 2,
      mode: provider.mode,
      provider: provider.id,
      supportsImages: provider.supportsImages,
      environment: serverEnvironment(),
      ai: {
        ...aiHealth(),
        models: provider.mode === "live" ? Object.fromEntries(AI_TASKS.map((task) => [task, provider.modelFor(task)])) : null,
        // Which model each route uses. Added with the ModelRouter; `models` above is unchanged in shape.
        routes: provider.mode === "live" ? routeModels() : null,
        ...(spend.active ? { spend } : {}),
      },
      plans: getPlans(),
      usage: usageSnapshot(usageSubject(request), tier),
      intents: INTENTS.map((id) => ({ id, label: INTENT_DEFINITIONS[id].label })),
      tones: TONES,
      refineActions: REFINE_ACTIONS,
      coach: { modes: COACH_MODES, topics: COACH_TOPICS, scenarios: PRACTICE_SCENARIOS },
      languages: LANGUAGES,
      limits: LIMITS,
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
