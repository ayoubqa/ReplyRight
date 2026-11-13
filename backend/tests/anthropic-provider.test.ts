import Anthropic from "@anthropic-ai/sdk";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AnthropicProvider, normalizeAnalysis } from "@/lib/ai/anthropic-provider";
import { aiHealth, resetAiHealth } from "@/lib/ai/health";
import { ProviderError } from "@/lib/ai/types";
import { analyzeRequestSchema, coachRequestSchema, refineRequestSchema, type Analysis } from "@/lib/domain/contracts";

/**
 * The live provider with the network call replaced, so its own logic can be
 * checked without an API key: what it sends, how it recovers when the optional
 * fallback parameter is refused, and how failures are classified.
 *
 * This does not prove the Anthropic API accepts the request. Only a run with a
 * real key does (`npm run verify:live`).
 */
type Params = { model: string; messages: { role: string; content: unknown }[]; betas?: string[]; fallbacks?: unknown; output_config: { effort: string } };

const models = { analyze: "claude-opus-5-5", replies: "claude-opus-5-5", refine: "claude-opus-5-5", coach: "claude-opus-5-5" };
const efforts = { analyze: "low", replies: "medium", refine: "low", coach: "medium" } as const;

function setup(parse: (params: Params) => Promise<unknown>) {
  const provider = new AnthropicProvider({ apiKey: "test-key-not-real", models, efforts });
  const spy = vi.fn(parse);
  (provider as unknown as { client: { beta: { messages: { parse: typeof spy } } } }).client = { beta: { messages: { parse: spy } } };
  return { provider, spy };
}

function answer(parsed: unknown, stop_reason = "end_turn") {
  return { model: "claude-opus-5-5", stop_reason, usage: { input_tokens: 10, output_tokens: 5 }, parsed_output: parsed };
}

function apiError(status: number, message: string) {
  return Anthropic.APIError.generate(status, { type: "error", error: { type: "api_error", message } }, message, new Headers());
}

const refineRequest = refineRequestSchema.parse({ text: "hey there, how are you doing today?", action: "shorter" });
const refined = { options: [{ style: "Shorter", text: "hey, how's today?", why: "Same question, half the words." }], note: null };
const coachAnswer = { message: "ok", suggestions: [], followUps: [], lesson: null, review: null, practice: null, headsUp: null };

beforeEach(() => {
  resetAiHealth();
  vi.spyOn(console, "error").mockImplementation(() => {});
  vi.spyOn(console, "warn").mockImplementation(() => {});
});

describe("AnthropicProvider request", () => {
  it("asks for the refusal fallback on models that support it and records success", async () => {
    const { provider, spy } = setup(async () => answer(refined));
    const result = await provider.refine({ request: refineRequest, options: { includeSamples: false } });
    expect(result.options).toHaveLength(1);
    const sent = spy.mock.calls[0][0];
    expect(sent.model).toBe("claude-opus-5-5");
    expect(sent.betas).toEqual(["server-side-fallback-2026-07-01"]);
    expect(sent.fallbacks).toBe("default");
    expect(sent.output_config.effort).toBe("low");
    expect(aiHealth().state).toBe("ok");
  });

  it("carries on without the fallback parameter when the API refuses it, and remembers", async () => {
    const { provider, spy } = setup(async (params) => {
      if (params.fallbacks) throw apiError(400, "fallbacks: Extra inputs are not permitted");
      return answer(refined);
    });
    await provider.refine({ request: refineRequest, options: { includeSamples: false } });
    expect(spy).toHaveBeenCalledTimes(2);
    expect(spy.mock.calls[1][0].fallbacks).toBeUndefined();

    await provider.refine({ request: refineRequest, options: { includeSamples: false } });
    expect(spy).toHaveBeenCalledTimes(3);
    expect(spy.mock.calls[2][0].fallbacks).toBeUndefined();
    expect(aiHealth().state).toBe("ok");
  });

  it("does not retry other bad requests, and does not blame the model's output for them", async () => {
    const { provider, spy } = setup(async () => {
      throw apiError(400, "output_config.effort: Input should be 'low', 'medium', 'high', 'xhigh' or 'max'");
    });
    await expect(provider.refine({ request: refineRequest, options: { includeSamples: false } })).rejects.toMatchObject({
      kind: "misconfigured",
      reason: "request",
    });
    expect(spy).toHaveBeenCalledTimes(1);
  });
});

describe("AnthropicProvider failures", () => {
  const cases: [string, () => unknown, string, string, boolean][] = [
    ["a rejected key", () => apiError(401, "invalid x-api-key"), "unavailable", "credentials", true],
    ["a model the key cannot use", () => apiError(403, "forbidden"), "unavailable", "credentials", true],
    ["an unknown model", () => apiError(404, "model: claude-nope"), "unavailable", "model", true],
    ["an empty credit balance", () => apiError(400, "Your credit balance is too low"), "unavailable", "billing", true],
    ["a rate limit", () => apiError(429, "rate limited"), "rate_limited", "rate_limit", false],
    ["an overloaded provider", () => apiError(529, "overloaded"), "unavailable", "overloaded", true],
    ["a timeout", () => new Anthropic.APIConnectionTimeoutError(), "unavailable", "timeout", true],
    ["no connection", () => new Anthropic.APIConnectionError({ message: "connect ECONNREFUSED" }), "unavailable", "network", true],
  ];

  it.each(cases)("classifies %s", async (_name, make, kind, reason, marksFailing) => {
    const { provider } = setup(async () => {
      throw make();
    });
    const error = await provider.refine({ request: refineRequest, options: { includeSamples: false } }).catch((e) => e);
    expect(error).toBeInstanceOf(ProviderError);
    expect(error).toMatchObject({ kind, reason });
    // What the user reads never contains the provider's own wording.
    expect(error.message).not.toMatch(/x-api-key|credit balance|claude-nope|ECONNREFUSED/);
    expect(aiHealth().state).toBe(marksFailing ? "failing" : "untested");
  });

  it("treats a refusal and a cut-off answer as failures of that one request", async () => {
    const refusal = setup(async () => answer(null, "refusal"));
    await expect(refusal.provider.refine({ request: refineRequest, options: { includeSamples: false } })).rejects.toMatchObject({
      kind: "declined",
      reason: "refusal",
    });
    const cut = setup(async () => answer(null, "max_tokens"));
    await expect(cut.provider.refine({ request: refineRequest, options: { includeSamples: false } })).rejects.toMatchObject({
      kind: "bad_output",
    });
    expect(aiHealth().state).toBe("ok");
  });
});

describe("AnthropicProvider coach turns", () => {
  const roles = (params: Params) => params.messages.map((m) => m.role);
  const run = async (input: unknown) => {
    const { provider, spy } = setup(async () => answer(coachAnswer));
    await provider.coach({ request: coachRequestSchema.parse(input), options: { includeSamples: false } });
    return spy.mock.calls[0][0];
  };

  it("opens a question with the context and the question in one user turn", async () => {
    const sent = await run({ messages: [{ role: "user", text: "Is this too eager?" }], draft: "miss you!!" });
    expect(roles(sent)).toEqual(["user"]);
    expect(sent.messages[0].content).toContain("<mode>ask</mode>");
    expect(sent.messages[0].content).toContain("Is this too eager?");
  });

  it("sends a review as one user turn that asks for the review", async () => {
    const sent = await run({ mode: "review", draft: "hey you" });
    expect(roles(sent)).toEqual(["user"]);
    expect(sent.messages[0].content).toContain("<my_draft>\nhey you\n</my_draft>");
    expect(sent.messages[0].content).toMatch(/Fill in review\.$/);
  });

  it("always starts and ends a practice exchange on a user turn", async () => {
    const scenario = { id: "flirting" };
    const opening = await run({ mode: "practice", scenario });
    expect(roles(opening)).toEqual(["user"]);
    expect(opening.messages[0].content).toMatch(/Set up the practice/);

    const later = await run({
      mode: "practice",
      scenario,
      messages: [
        { role: "coach", text: "hey! how was the gig?" },
        { role: "user", text: "loud. in a good way" },
      ],
    });
    expect(roles(later)).toEqual(["user", "assistant", "user"]);
    expect(later.messages[2].content).toMatch(/^loud\. in a good way\n\nStay in the practice/);
  });

  it("drops practice output outside practice mode", async () => {
    const { provider } = setup(async () =>
      answer({ ...coachAnswer, practice: { partnerReply: "hi", feedback: null, tryThis: null, finished: false } }),
    );
    const result = await provider.coach({
      request: coachRequestSchema.parse({ messages: [{ role: "user", text: "hello" }] }),
      options: { includeSamples: false },
    });
    expect(result.practice).toBeNull();
  });
});

// ------------------------------------------------------------------ screenshots

const analysis: Analysis = {
  canReply: true,
  transcript: [
    { speaker: "them", text: "are we still on for friday?" },
    { speaker: "me", text: "unless you found someone better" },
  ],
  latestMessage: "are we still on for friday?",
  latestFromMe: false,
  read: "They're checking the plan is still on, with a bit of teasing.",
  toneLabel: "Playful planning",
  observations: ["They asked a direct question about Friday."],
  assumptions: ["They might be a little nervous about it."],
  opportunity: "Confirm, and tease back.",
  suggestedIntents: ["natural", "laugh"],
  headsUp: null,
  problem: "none",
};

const shot = (mediaType: "image/png" | "image/jpeg", marker: string) => ({
  mediaType,
  base64: Buffer.from(marker).toString("base64"),
  width: 800,
  height: 1200,
});

describe("AnthropicProvider screenshots", () => {
  type Block = { type: string; source?: { type: string; media_type: string; data: string }; text?: string };

  it("sends each screenshot as an image block, in order, before the text that refers to them", async () => {
    const { provider, spy } = setup(async () => answer(analysis));
    const images = [shot("image/jpeg", "first"), shot("image/png", "second")];
    const result = await provider.analyze({ request: analyzeRequestSchema.parse({ conversation: "" }), images });
    expect(result.transcript).toHaveLength(2);

    const [message] = spy.mock.calls[0][0].messages;
    expect(message.role).toBe("user");
    const blocks = message.content as Block[];
    expect(blocks.map((block) => block.type)).toEqual(["image", "image", "text"]);
    expect(blocks[0].source).toEqual({ type: "base64", media_type: "image/jpeg", data: images[0].base64 });
    expect(blocks[1].source).toEqual({ type: "base64", media_type: "image/png", data: images[1].base64 });
    expect(blocks[2].text).toContain("I attached 2 screenshots of the conversation, in order.");
  });

  it("sends screenshots with a one-step reply request too", async () => {
    const replies = { note: "ok", replies: [{ style: "Natural", text: "yes!", why: "Easy." }], headsUp: null };
    const { provider, spy } = setup(async () => answer(replies));
    await provider.replies({
      request: (await import("@/lib/domain/contracts")).repliesRequestSchema.parse({}),
      images: [shot("image/jpeg", "only")],
      options: { includeSamples: false },
    });
    const blocks = spy.mock.calls[0][0].messages[0].content as Block[];
    expect(blocks.map((block) => block.type)).toEqual(["image", "text"]);
  });

  it("tells the user when the API cannot use an image, without marking the service as down", async () => {
    const { provider } = setup(async () => {
      throw apiError(400, "messages.0.content.0.image.source.base64.data: Could not process image");
    });
    const error = await provider
      .analyze({ request: analyzeRequestSchema.parse({}), images: [shot("image/jpeg", "x")] })
      .catch((e: unknown) => e);
    expect(error).toMatchObject({ kind: "rejected_input", reason: "image" });
    expect((error as Error).message).toMatch(/couldn't read one of those screenshots/i);
    expect(aiHealth().state).toBe("untested");
  });

  it("treats an answer that does not match the schema as unusable output", async () => {
    const { provider } = setup(async () => {
      // What the SDK throws when the model's JSON fails the Zod schema.
      throw new Anthropic.AnthropicError("Failed to parse structured output: canReply: Required");
    });
    await expect(
      provider.analyze({ request: analyzeRequestSchema.parse({}), images: [shot("image/jpeg", "x")] }),
    ).rejects.toMatchObject({ kind: "bad_output", reason: "output" });
  });

  it("treats a missing parsed answer and a cut-off answer as unusable output", async () => {
    for (const reply of [answer(null), answer(analysis, "max_tokens")]) {
      const { provider } = setup(async () => reply);
      await expect(
        provider.analyze({ request: analyzeRequestSchema.parse({}), images: [shot("image/png", "x")] }),
      ).rejects.toMatchObject({ kind: "bad_output" });
    }
  });
});

describe("normalizeAnalysis", () => {
  it("drops empty lines and tidies whitespace without adding anything", () => {
    const result = normalizeAnalysis({
      ...analysis,
      transcript: [
        { speaker: "them", text: "  are we still on?  " },
        { speaker: "unknown", text: "   " },
        { speaker: "me", text: "" },
      ],
      latestMessage: "   ",
      toneLabel: "  Playful \n planning ",
      observations: ["  one  ", "", "two"],
      assumptions: [" "],
      headsUp: "  ",
      suggestedIntents: ["laugh", "laugh", "natural", "flirt", "interest"],
    });
    expect(result.transcript).toEqual([{ speaker: "them", text: "are we still on?" }]);
    expect(result.latestMessage).toBeNull();
    expect(result.toneLabel).toBe("Playful planning");
    expect(result.observations).toEqual(["one", "two"]);
    expect(result.assumptions).toEqual([]);
    expect(result.headsUp).toBeNull();
    expect(result.suggestedIntents).toEqual(["laugh", "natural", "flirt"]);
  });

  it("never offers replies to a screenshot that could not be read", () => {
    for (const problem of ["unreadable", "not_a_conversation"] as const) {
      const result = normalizeAnalysis({ ...analysis, canReply: true, problem });
      expect(result.canReply).toBe(false);
      expect(result.problem).toBe(problem);
    }
    expect(normalizeAnalysis({ ...analysis, problem: "partly_readable" }).canReply).toBe(true);
  });

  it("refuses an analysis with nothing to tell the user", () => {
    expect(() => normalizeAnalysis({ ...analysis, read: "   " })).toThrow(ProviderError);
  });

  it("caps the transcript at the most recent lines the contract allows", () => {
    const long = Array.from({ length: 120 }, (_, i) => ({ speaker: "them" as const, text: `line ${i}` }));
    const result = normalizeAnalysis({ ...analysis, transcript: long });
    expect(result.transcript).toHaveLength(80);
    expect(result.transcript.at(-1)?.text).toBe("line 119");
  });
});
