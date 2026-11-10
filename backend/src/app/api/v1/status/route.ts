import { getProvider } from "@/lib/ai";
import { LIMITS, REFINE_ACTIONS } from "@/lib/domain/contracts";
import { INTENT_DEFINITIONS, INTENTS } from "@/lib/domain/intents";
import { LANGUAGES, TONES } from "@/lib/domain/voice";
import { resolveTier } from "@/lib/server/entitlements";
import { getPlans } from "@/lib/server/plans";
import { usageSnapshot, usageSubject } from "@/lib/server/usage";

/**
 * GET /api/v1/status
 * Tells the app whether AI is live or in demo mode, what the plans allow, and
 * the caller's usage today. Contains no secrets.
 */
export async function GET(request: Request) {
  const provider = getProvider();
  const tier = resolveTier(request);
  return Response.json(
    {
      apiVersion: 1,
      mode: provider.mode,
      provider: provider.id,
      supportsImages: provider.supportsImages,
      plans: getPlans(),
      usage: usageSnapshot(usageSubject(request), tier),
      intents: INTENTS.map((id) => ({ id, label: INTENT_DEFINITIONS[id].label })),
      tones: TONES,
      refineActions: REFINE_ACTIONS,
      languages: LANGUAGES,
      limits: LIMITS,
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
