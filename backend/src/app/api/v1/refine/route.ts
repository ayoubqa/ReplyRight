import { refineRequestSchema, type RefineResult } from "@/lib/domain/contracts";
import { handleTask } from "@/lib/server/pipeline";

export const maxDuration = 120;

/**
 * POST /api/v1/refine
 * Rewrites one message: shorter, funnier, more confident, more like me, or in
 * a given tone. Used by reply cards, draft polish and the keyboard.
 */
export async function POST(request: Request) {
  return handleTask<typeof refineRequestSchema, RefineResult>(request, {
    task: "refine",
    schema: refineRequestSchema,
    meter: "generation",
    run: ({ input, plan, provider, call }) =>
      provider.refine({ request: input, options: { includeSamples: plan.voiceSamples }, call }),
  });
}
