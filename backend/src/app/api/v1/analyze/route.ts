import { analyzeRequestSchema, type Analysis } from "@/lib/domain/contracts";
import { handleTask } from "@/lib/server/pipeline";

export const maxDuration = 120;

/**
 * POST /api/v1/analyze
 * Reads a conversation (pasted text and/or screenshots) and returns a
 * transcript plus a short, hedged read. Does not count against the daily
 * generation limit: it is the first half of writing a reply.
 */
export async function POST(request: Request) {
  return handleTask<typeof analyzeRequestSchema, Analysis>(request, {
    task: "analyze",
    schema: analyzeRequestSchema,
    allowImages: true,
    meter: null,
    validate: (input, images) => {
      if (!input.conversation && images.length === 0) {
        return "Add a screenshot or paste a few messages so there's something to read.";
      }
      if (input.conversation && input.conversation.length < 2) return "Paste a little more of the conversation.";
      return null;
    },
    run: ({ input, images, provider, call }) => provider.analyze({ request: input, images, call }),
  });
}
