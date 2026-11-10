import { describe, expect, it } from "vitest";
import { analysisSchema, coachRequestSchema, LIMITS, refineRequestSchema, repliesRequestSchema } from "@/lib/domain/contracts";
import { crushSchema, voiceSchema } from "@/lib/domain/voice";

describe("request schemas", () => {
  it("fill sensible defaults so older clients keep working", () => {
    expect(repliesRequestSchema.parse({ conversation: "hi" })).toMatchObject({
      kind: "reply",
      intent: "natural",
      instruction: "",
      draft: "",
      avoid: [],
      transcript: [],
      locale: "en",
    });
    expect(voiceSchema.parse({})).toMatchObject({ defaultTone: "playful", emoji: "rare", length: "short", samples: [] });
    expect(crushSchema.parse({ alias: " Sam " })).toEqual({ alias: "Sam", stage: "talking", notes: "" });
  });

  it("enforce limits", () => {
    expect(repliesRequestSchema.safeParse({ instruction: "x".repeat(LIMITS.instructionChars + 1) }).success).toBe(false);
    expect(repliesRequestSchema.safeParse({ avoid: Array(LIMITS.avoidReplies + 1).fill("a") }).success).toBe(false);
    expect(voiceSchema.safeParse({ samples: Array(9).fill("hey") }).success).toBe(false);
    expect(voiceSchema.safeParse({ replyLanguage: "klingon" }).success).toBe(false);
    expect(refineRequestSchema.safeParse({ text: "hi", action: "shorter", count: 2 }).success).toBe(false);
    expect(coachRequestSchema.safeParse({ messages: [] }).success).toBe(false);
    expect(crushSchema.safeParse({ alias: "" }).success).toBe(false);
  });
});

describe("analysisSchema", () => {
  it("keeps observations and assumptions as separate fields", () => {
    const shape = analysisSchema.shape;
    expect(shape.observations).toBeDefined();
    expect(shape.assumptions).toBeDefined();
    expect(shape.read).toBeDefined();
  });
});
