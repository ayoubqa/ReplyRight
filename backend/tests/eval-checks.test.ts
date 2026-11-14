import { describe, expect, it } from "vitest";
import { CASES } from "../evals/cases";
import { runChecks, runCoachChecks, runReadChecks, similarity } from "../evals/checks";
import { describeCall, ROUTES } from "@/lib/ai/router";
import { analyzeRequestSchema, coachRequestSchema, refineRequestSchema, repliesRequestSchema } from "@/lib/domain/contracts";

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
    expect(CASES.some((c) => "expect" in c && c.expect.decline)).toBe(true);
  });

  it("include every route the app uses, and only invented content", () => {
    const tags = new Set(CASES.flatMap((c) => c.tags));
    for (const tag of ["simple", "flirt", "tone", "read", "screenshot", "coach", "review", "practice", "deep"]) expect(tags.has(tag)).toBe(true);
    for (const task of ["replies", "refine", "analyze", "coach"]) expect(CASES.some((c) => c.task === task)).toBe(true);
  });
});

describe("read and coach graders", () => {
  const analysis = (over: Record<string, unknown> = {}) =>
    ({
      canReply: true,
      problem: "none",
      read: "They're making a playful test of it.",
      transcript: [
        { speaker: "them", text: "ok be honest, pineapple on pizza?" },
        { speaker: "me", text: "depends who’s asking" },
      ],
      latestMessage: "depends who's asking",
      latestFromMe: true,
      toneLabel: "Playful",
      observations: [],
      assumptions: [],
      opportunity: "",
      suggestedIntents: [],
      headsUp: null,
      ...over,
    }) as never;
  const lines = [
    { text: "pineapple on pizza", speaker: "them" as const },
    { text: "depends who's asking", speaker: "me" as const },
  ];

  it("pass a correct read, curly apostrophes included", () => {
    const results = runReadChecks(analysis(), { canReply: true, lines, latestIncludes: "asking", problemIn: ["none"] });
    expect(Object.values(results).every(Boolean)).toBe(true);
  });

  it("catch swapped speakers, missing lines, wrong order and a read that should have refused", () => {
    const swapped = runReadChecks(
      analysis({ transcript: [{ speaker: "me", text: "pineapple on pizza?" }, { speaker: "them", text: "depends who's asking" }] }),
      { canReply: true, lines },
    );
    expect(swapped.speakers).toBe(false);
    expect(runReadChecks(analysis({ transcript: [{ speaker: "them", text: "pineapple on pizza" }] }), { canReply: true, lines }).transcribed).toBe(false);
    expect(runReadChecks(analysis(), { canReply: true, lines: [...lines].reverse() }).order).toBe(false);
    expect(runReadChecks(analysis(), { canReply: false, problemIn: ["unreadable"] })).toMatchObject({ can_reply: false, problem: false });
  });

  const coachResult = (over: Record<string, unknown> = {}) =>
    ({ message: "Try once more, with a specific day and time, then let them come to you.", suggestions: [], followUps: [], lesson: null, review: null, practice: null, headsUp: null, ...over }) as never;
  const request = (body: Record<string, unknown>) => coachRequestSchema.parse(body);

  it("check coaching answers for the parts each mode needs, and for mind-reading", () => {
    const ask = request({ messages: [{ role: "user", text: "should I try again?" }] });
    expect(Object.values(runCoachChecks(coachResult(), ask, { forbidden: ["they definitely"] })).every(Boolean)).toBe(true);
    expect(runCoachChecks(coachResult({ message: "They definitely like you, just wait for them to text." }), ask, { forbidden: ["they definitely"] }).no_mind_reading).toBe(false);
    const review = request({ mode: "review", draft: "hey" });
    expect(runCoachChecks(coachResult(), review, { review: true }).review).toBe(false);
    const practice = request({ mode: "practice", scenario: { id: "flirting" }, messages: [{ role: "user", text: "hi" }] });
    const turn = runCoachChecks(coachResult({ practice: { partnerReply: "", feedback: null, tryThis: null, finished: false } }), practice, { practice: true, partnerReply: true });
    expect(turn).toMatchObject({ practice: true, partner_reply: false, feedback: false });
  });
});

describe("eval routing coverage", () => {
  it("routes the cases through the app's router to every route, as intended", () => {
    const image = { mediaType: "image/jpeg" as const, base64: "AAAA", width: 780, height: 1688 };
    const schema = { replies: repliesRequestSchema, refine: refineRequestSchema, analyze: analyzeRequestSchema, coach: coachRequestSchema };
    const routeOf = (c: (typeof CASES)[number]) =>
      describeCall(c.task, schema[c.task].parse(c.request), ("images" in c && c.images ? c.images : []).map(() => image)).route;
    expect(new Set(CASES.map(routeOf))).toEqual(new Set(ROUTES));
    for (const c of CASES) {
      if (c.tags.includes("simple")) expect(routeOf(c)).toBe("reply_simple");
      if (c.tags.includes("deep")) expect(routeOf(c)).toBe("coach_advanced");
      if (c.tags.includes("tone")) expect(routeOf(c)).toBe("tone");
    }
  });
});
