import { coachRequestSchema, type CoachResult } from "@/lib/domain/contracts";
import { handleTask, UpgradeRequired } from "@/lib/server/pipeline";

export const maxDuration = 120;

/**
 * POST /api/v1/coach
 * One turn with the communication mentor: a question (ask), feedback on a
 * message the user wrote (review), or a rehearsal where the coach plays the
 * other person (practice). The client sends the running exchange each time;
 * the server keeps no chat history.
 */
export async function POST(request: Request) {
  return handleTask<typeof coachRequestSchema, CoachResult>(request, {
    task: "coach",
    schema: coachRequestSchema,
    meter: "coach",
    validate: (input) => {
      const last = input.messages[input.messages.length - 1];
      switch (input.mode) {
        case "ask":
          return last?.role === "user" ? null : "The last message should be your question.";
        case "review":
          return input.draft ? null : "Add the message you want feedback on.";
        case "practice":
          if (!input.scenario) return "Choose what you want to practise.";
          if (input.scenario.id === "custom" && !input.scenario.detail) return "Describe the situation you want to practise.";
          return !last || last.role === "user" ? null : "Send your next message to keep practising.";
      }
    },
    // Deep coaching runs on the most capable model, so it is part of Pro.
    gate: ({ input, tier }) => {
      if (input.depth === "deep" && tier !== "pro") {
        throw new UpgradeRequired("Deeper coaching is part of ReplyRight Pro.");
      }
    },
    run: ({ input, plan, provider, call }) =>
      provider.coach({ request: input, options: { includeSamples: plan.voiceSamples }, call }),
  });
}
