import { coachRequestSchema, type CoachResult } from "@/lib/domain/contracts";
import { handleTask } from "@/lib/server/pipeline";

export const maxDuration = 60;

/**
 * POST /api/v1/coach
 * One turn of the conversation coach. The client sends the running
 * conversation each time; the server keeps no chat history.
 */
export async function POST(request: Request) {
  return handleTask<typeof coachRequestSchema, CoachResult>(request, {
    task: "coach",
    schema: coachRequestSchema,
    meter: "coach",
    validate: (input) =>
      input.messages[input.messages.length - 1].role === "user" ? null : "The last message should be your question.",
    run: ({ input, plan, provider }) =>
      provider.coach({ request: input, options: { includeSamples: plan.voiceSamples } }),
  });
}
