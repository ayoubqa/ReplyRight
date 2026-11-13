import { repliesRequestSchema, type RepliesResult } from "@/lib/domain/contracts";
import { INTENT_DEFINITIONS } from "@/lib/domain/intents";
import { handleTask, UpgradeRequired } from "@/lib/server/pipeline";

export const maxDuration = 120;

/**
 * POST /api/v1/replies
 * Three distinct options for the user's next message (kind: "reply"), or
 * three ways to open a conversation (kind: "starter").
 * Accepts JSON, or multipart with screenshots for the one-step path.
 */
export async function POST(request: Request) {
  return handleTask<typeof repliesRequestSchema, RepliesResult>(request, {
    task: "replies",
    schema: repliesRequestSchema,
    allowImages: true,
    meter: "generation",
    validate: (input, images) => {
      if (input.kind === "reply" && !input.conversation && input.transcript.length === 0 && images.length === 0) {
        return "Share the conversation first so there's something to reply to.";
      }
      return null;
    },
    gate: ({ input, plan }) => {
      if (!plan.intents.includes(input.intent)) {
        throw new UpgradeRequired(`"${INTENT_DEFINITIONS[input.intent].label}" is part of ReplyRight Pro.`);
      }
    },
    run: ({ input, images, plan, provider }) =>
      provider.replies({ request: input, images, options: { includeSamples: plan.voiceSamples } }),
  });
}
