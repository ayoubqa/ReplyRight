import { describe, expect, it } from "vitest";
import { CASES } from "../evals/cases";
import { runChecks, similarity } from "../evals/checks";

/**
 * The eval's graders are tested on known-good and known-bad outputs before
 * they are trusted to compare models.
 */
const good = {
  texts: ["wow. and here I was about to say you had great taste", "fine, but you're explaining yourself over a slice this weekend", "bold of you to admit that this early"],
  headsUp: null,
  requested: 3,
  avoid: [],
};

describe("eval checks", () => {
  it("pass a known-good output", () => {
    const results = runChecks(good, { language: "en" });
    expect(Object.values(results).every(Boolean)).toBe(true);
  });

  it("fail an empty output (no answer is not a pass)", () => {
    const results = runChecks({ ...good, texts: [] }, { language: "en" });
    expect(results.count).toBe(false);
    expect(results.non_empty).toBe(false);
  });

  it("catch rewordings, quotes, em dashes, stacked questions, emoji, length and repeats", () => {
    const bad = {
      texts: ['"that sounds really fun — want to go?"', "that sounds really fun, want to go with me?", "how are you? what's up? 😀 " + "x".repeat(200)],
      headsUp: null,
      requested: 3,
      avoid: ["that sounds really fun, want to go with me?"],
    };
    const results = runChecks(bad, { language: "en", noEmoji: true, maxChars: 140, forbidden: ["want to go"] });
    expect(results).toMatchObject({
      distinct: false,
      no_wrapping_quotes: false,
      no_em_dash: false,
      one_question_max: false,
      no_emoji: false,
      length: false,
      not_repeated: false,
      no_forbidden: false,
    });
  });

  it("grade declines in both directions", () => {
    expect(runChecks({ texts: [], headsUp: "I can't help write flirtatious messages here because...", requested: 3, avoid: [] }, { decline: true })).toEqual({
      declined: true,
      explained: true,
    });
    expect(runChecks(good, { decline: true })).toMatchObject({ declined: false, explained: false });
  });

  it("detect language", () => {
    expect(runChecks({ ...good, texts: ["jajaja no puede ser, cuéntame más"], requested: 1 }, { language: "es" }).language).toBe(true);
    expect(runChecks({ ...good, texts: ["haha no way, tell me more"], requested: 1 }, { language: "es" }).language).toBe(false);
  });

  it("measure similarity sensibly", () => {
    expect(similarity("want to grab coffee this week", "want to grab coffee this week?")).toBeGreaterThan(0.9);
    expect(similarity("bold of you to admit that", "fine, pizza is on you this weekend")).toBeLessThan(0.2);
  });
});

describe("eval cases", () => {
  it("have unique ids and cover safety, both languages, starters and refine", () => {
    const ids = CASES.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
    const tags = new Set(CASES.flatMap((c) => c.tags));
    for (const tag of ["safety", "es", "starter", "refine", "voice", "boundaries"]) expect(tags.has(tag)).toBe(true);
    expect(CASES.some((c) => c.expect.decline)).toBe(true);
  });
});
