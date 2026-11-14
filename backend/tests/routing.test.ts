import { mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AnthropicProvider } from "@/lib/ai/anthropic-provider";
import { resetSpendTracking } from "@/lib/ai/budget";
import { resetAiHealth } from "@/lib/ai/health";
import { describeCall, isSimpleReply, resolveRoutes, ROUTES, thinkingParam, type RouteKey } from "@/lib/ai/router";
import type { AiUsageRecord } from "@/lib/ai/usage-log";
import { coachRequestSchema, refineRequestSchema, repliesRequestSchema, analyzeRequestSchema } from "@/lib/domain/contracts";
import type { TransientImage } from "@/lib/ai/types";
import { fakeAnthropic, message, type Step } from "./helpers/anthropic-http";

/**
 * The ModelRouter: which route each request takes, which model, effort and
 * thinking setting each route uses, how configuration overrides it, and what
 * the provider sends for it. Every API call here goes to a fake HTTP API.
 */
const ROUTE_VARS = [
  "AI_ROUTING",
  "AI_MODEL",
  "ANTHROPIC_MODEL",
  "AI_EFFORT",
  ...["ANALYZE", "REPLIES", "REFINE", "COACH"].flatMap((t) => [`AI_MODEL_${t}`, `AI_EFFORT_${t}`]),
  ...ROUTES.map((r) => `AI_ROUTE_${r.toUpperCase()}`),
  "AI_SIMPLE_REPLIES",
  "AI_SIMPLE_REPLY_INTENTS",
  "AI_SIMPLE_REPLY_MAX_CHARS",
  "RR_USAGE_LOG_DIR",
  "RR_DEV_SPEND_LIMIT_USD",
];
const saved: Record<string, string | undefined> = {};
let dir = "";
const IMAGE: TransientImage = { mediaType: "image/jpeg", base64: "AAAA", width: 780, height: 1688 };

beforeEach(() => {
  for (const name of ROUTE_VARS) saved[name] = process.env[name];
  for (const name of ROUTE_VARS) delete process.env[name];
  dir = mkdtempSync(join(tmpdir(), "rr-routing-"));
  process.env.RR_USAGE_LOG_DIR = dir;
  resetSpendTracking();
  resetAiHealth();
  vi.spyOn(console, "error").mockImplementation(() => {});
  vi.spyOn(console, "warn").mockImplementation(() => {});
});
afterEach(() => {
  for (const name of ROUTE_VARS) {
    if (saved[name] === undefined) delete process.env[name];
    else process.env[name] = saved[name];
  }
  vi.restoreAllMocks();
});

const replies = (body: Record<string, unknown>) => repliesRequestSchema.parse(body);

describe("default route table", () => {
  it("matches the agreed starting allocation", () => {
    const { routes, problems } = resolveRoutes();
    expect(problems).toEqual([]);
    const models = Object.fromEntries(ROUTES.map((key) => [key, routes[key].model]));
    expect(models).toEqual({
      read_text: "claude-sonnet-5-5",
      read_screenshot: "claude-sonnet-5-5",
      reply_simple: "claude-haiku-5-5",
      reply_standard: "claude-sonnet-5-5",
      reply_screenshot: "claude-sonnet-5-5",
      starter: "claude-haiku-5-5",
      refine: "claude-haiku-5-5",
      tone: "claude-haiku-5-5",
      coach_ask: "claude-sonnet-5-5",
      coach_review: "claude-sonnet-5-5",
      coach_practice: "claude-sonnet-5-5",
      coach_advanced: "claude-opus-5-5",
    });
  });

  it("keeps adaptive thinking and each task's effort, so only the model changes by default", () => {
    const { routes } = resolveRoutes();
    for (const key of ROUTES) expect(routes[key].thinking).toBe("auto");
    expect(routes.read_screenshot.effort).toBe("low");
    expect(routes.reply_simple.effort).toBe("medium");
    expect(routes.refine.effort).toBe("low");
    expect(routes.coach_advanced.effort).toBe("medium");
  });

  it("gives only the Haiku routes a fallback model, and never Opus", () => {
    const { routes } = resolveRoutes();
    for (const key of ROUTES) {
      const expected = routes[key].model === "claude-haiku-5-5" ? "claude-sonnet-5-5" : null;
      expect(routes[key].fallback).toBe(expected);
    }
  });
});

describe("choosing a route", () => {
  const short = "Them: haha that's fair\nMe: right?\nThem: so what are you up to this weekend";

  it("sends a short, light, text-only reply to the simple route", () => {
    expect(describeCall("replies", replies({ conversation: short, intent: "natural" }), [])).toEqual({ feature: "replies", route: "reply_simple" });
    expect(describeCall("replies", replies({ conversation: short, intent: "keep_going" }), []).route).toBe("reply_simple");
  });

  it("keeps flirting, asking out, feelings, boundaries and humour on the standard route", () => {
    for (const intent of ["flirt", "ask_out", "feelings", "boundary", "laugh", "dry_reply", "mysterious", "charming", "confident", "interest"]) {
      expect(describeCall("replies", replies({ conversation: short, intent }), []).route).toBe("reply_standard");
    }
  });

  it("treats a long conversation, a special instruction or a screenshot as more than simple", () => {
    const long = Array.from({ length: 12 }, (_, i) => `Them: message number ${i}`).join("\n");
    expect(describeCall("replies", replies({ conversation: long, intent: "natural" }), []).route).toBe("reply_standard");
    expect(describeCall("replies", replies({ conversation: "Them: " + "x".repeat(700), intent: "natural" }), []).route).toBe("reply_standard");
    expect(describeCall("replies", replies({ conversation: short, intent: "natural", instruction: "mention the dog" }), []).route).toBe(
      "reply_standard",
    );
    expect(describeCall("replies", replies({ conversation: "", intent: "natural" }), [IMAGE])).toEqual({
      feature: "replies_from_screenshot",
      route: "reply_screenshot",
    });
  });

  it("routes three more like the first set, and labels it as a regeneration", () => {
    expect(describeCall("replies", replies({ conversation: short, intent: "natural", avoid: ["hey"] }), [])).toEqual({
      feature: "regenerate",
      route: "reply_simple",
    });
    expect(describeCall("replies", replies({ conversation: short, intent: "flirt", avoid: ["hey"] }), [])).toEqual({
      feature: "regenerate",
      route: "reply_standard",
    });
  });

  it("follows the simple-reply settings", () => {
    const request = replies({ conversation: short, intent: "flirt" });
    process.env.AI_SIMPLE_REPLY_INTENTS = "flirt,natural";
    expect(isSimpleReply(request, [])).toBe(true);
    process.env.AI_SIMPLE_REPLIES = "off";
    expect(isSimpleReply(request, [])).toBe(false);
    delete process.env.AI_SIMPLE_REPLIES;
    process.env.AI_SIMPLE_REPLY_MAX_CHARS = "20";
    expect(isSimpleReply(request, [])).toBe(false);
  });

  it("uses the structured transcript from a read when there is one", () => {
    const transcript = [
      { speaker: "them" as const, text: "so what are you up to" },
      { speaker: "me" as const, text: "not much" },
    ];
    expect(describeCall("replies", replies({ transcript, intent: "natural" }), []).route).toBe("reply_simple");
  });

  it("names every other kind of request", () => {
    const analysis = analyzeRequestSchema.parse({ conversation: short });
    expect(describeCall("analyze", analysis, [])).toEqual({ feature: "read_text", route: "read_text" });
    expect(describeCall("analyze", analysis, [IMAGE])).toEqual({ feature: "read_screenshot", route: "read_screenshot" });
    expect(describeCall("replies", replies({ kind: "starter", intent: "natural" }), [])).toEqual({ feature: "starter", route: "starter" });
    expect(describeCall("refine", refineRequestSchema.parse({ text: "hey you", action: "shorter" }), [])).toEqual({ feature: "refine", route: "refine" });
    for (const action of ["flirty", "playful", "charming", "subtle", "warm"]) {
      expect(describeCall("refine", refineRequestSchema.parse({ text: "hey you", action }), [])).toEqual({ feature: "tone", route: "tone" });
    }
    const coach = (body: Record<string, unknown>) => coachRequestSchema.parse(body);
    expect(describeCall("coach", coach({ messages: [{ role: "user", text: "help" }] }), []).route).toBe("coach_ask");
    expect(describeCall("coach", coach({ mode: "review", draft: "hey" }), []).route).toBe("coach_review");
    expect(describeCall("coach", coach({ mode: "practice", scenario: { id: "first_message" } }), []).route).toBe("coach_practice");
    expect(describeCall("coach", coach({ depth: "deep", messages: [{ role: "user", text: "help" }] }), [])).toEqual({
      feature: "coach_ask_deep",
      route: "coach_advanced",
    });
  });
});

describe("configuration", () => {
  it("lets one route be changed without touching the others", () => {
    process.env.AI_ROUTE_REFINE = "claude-sonnet-5-5,effort=medium,thinking=off,fallback=none";
    const { routes, problems } = resolveRoutes();
    expect(problems).toEqual([]);
    expect(routes.refine).toMatchObject({ model: "claude-sonnet-5-5", effort: "medium", thinking: "off", fallback: null, source: "AI_ROUTE_REFINE" });
    expect(routes.tone.model).toBe("claude-haiku-5-5");
  });

  it("lets AI_MODEL put every route on one model, dropping the Haiku fallbacks", () => {
    process.env.AI_MODEL = "claude-opus-5-5";
    const { routes } = resolveRoutes();
    for (const key of ROUTES) {
      expect(routes[key]).toMatchObject({ model: "claude-opus-5-5", fallback: null, source: "AI_MODEL" });
    }
  });

  it("keeps the per-task model and effort variables working", () => {
    process.env.AI_MODEL_COACH = "claude-opus-5-5";
    process.env.AI_EFFORT_REPLIES = "high";
    const { routes } = resolveRoutes();
    expect(routes.coach_ask.model).toBe("claude-opus-5-5");
    expect(routes.coach_practice.model).toBe("claude-opus-5-5");
    expect(routes.read_text.model).toBe("claude-sonnet-5-5");
    expect(routes.reply_simple.effort).toBe("high");
    expect(routes.starter.effort).toBe("high");
  });

  it("an explicit route beats AI_MODEL", () => {
    process.env.AI_MODEL = "claude-opus-5-5";
    process.env.AI_ROUTE_STARTER = "claude-haiku-5-5";
    const { routes } = resolveRoutes();
    expect(routes.starter.model).toBe("claude-haiku-5-5");
    expect(routes.reply_simple.model).toBe("claude-opus-5-5");
  });

  it("rolls everything back to Opus 5.5 with AI_ROUTING=off", () => {
    process.env.AI_ROUTING = "off";
    process.env.AI_ROUTE_REFINE = "claude-haiku-5-5";
    const { routes } = resolveRoutes();
    for (const key of ROUTES) {
      expect(routes[key]).toMatchObject({ model: "claude-opus-5-5", thinking: "auto", fallback: null });
    }
  });

  it("reports bad values and keeps the default for that route instead of failing", () => {
    process.env.AI_ROUTE_REPLY_SIMPLE = "gpt-4o,effort=max,thinking=none,colour=blue";
    process.env.AI_ROUTE_TONE = "claude-mystery-9";
    const { routes, problems } = resolveRoutes();
    expect(routes.reply_simple).toMatchObject({ model: "claude-haiku-5-5", effort: "medium", thinking: "auto" });
    expect(problems.map((p) => p.message).join("\n")).toMatch(/not a Claude model id/);
    expect(problems.map((p) => p.message).join("\n")).toMatch(/effort must be/);
    expect(problems.map((p) => p.message).join("\n")).toMatch(/thinking must be/);
    expect(problems.map((p) => p.message).join("\n")).toMatch(/unknown option/);
    expect(routes.tone.model).toBe("claude-mystery-9");
    expect(problems.find((p) => p.variable === "AI_ROUTE_TONE")?.message).toMatch(/not in the price table/);
  });

  it("warns when a route asks to switch thinking off on a model that cannot", () => {
    process.env.AI_ROUTE_COACH_ADVANCED = "claude-opus-5-5,thinking=off";
    const { problems } = resolveRoutes();
    expect(problems.find((p) => p.variable === "AI_ROUTE_COACH_ADVANCED")?.message).toMatch(/cannot turn thinking off/);
  });
});

describe("thinking settings per model", () => {
  it("uses the lowest setting each model accepts, from the thinking documentation", () => {
    expect(thinkingParam("claude-sonnet-5-5", "off")).toEqual({ type: "between_tools" });
    expect(thinkingParam("claude-haiku-5-5", "off")).toEqual({ type: "disabled" });
    expect(thinkingParam("claude-opus-5", "off")).toEqual({ type: "disabled" });
    expect(thinkingParam("claude-opus-5-20260101", "off")).toEqual({ type: "disabled" });
    expect(thinkingParam("claude-opus-5-5", "off")).toBeUndefined();
    expect(thinkingParam("claude-fable-5-2", "off")).toBeUndefined();
    for (const model of ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]) expect(thinkingParam(model, "auto")).toBeUndefined();
  });
});

// ---------------------------------------------------------------- the provider, end to end over a fake API

const refined = { options: [{ style: "Shorter", text: "how was it?", why: "Same question." }], note: null };
const refusal = (model: string, usage = { input_tokens: 2000, output_tokens: 20 }): Step => ({
  kind: "message",
  text: "",
  stop: "refusal",
  model,
  usage,
});

function provider(steps: Step[], env: Record<string, string> = {}) {
  for (const [k, v] of Object.entries(env)) process.env[k] = v;
  const http = fakeAnthropic(steps);
  const p = new AnthropicProvider({
    apiKey: "test-key-not-real",
    routes: resolveRoutes().routes,
    environment: "development",
    retryBaseDelayMs: 1,
    fetch: http.fetch,
  });
  return { p, http, sent: () => http.bodies.map((b) => JSON.parse(b)) };
}

const ledger = (): AiUsageRecord[] =>
  readdirSync(dir)
    .flatMap((f) => readFileSync(join(dir, f), "utf8").split("\n"))
    .filter(Boolean)
    .map((l) => JSON.parse(l));

const refine = (p: AnthropicProvider, route: RouteKey = "refine", call: { servedModel?: string } = {}) =>
  p.refine({
    request: refineRequestSchema.parse({ text: "hey, how was the gig?", action: "shorter" }),
    options: { includeSamples: false },
    call: Object.assign(call, { route, feature: route }),
  });

describe("what the provider sends for each route", () => {
  it("sends Haiku routes to Haiku without the refusal-fallback parameter, which Haiku does not support", async () => {
    const { p, sent } = provider([{ kind: "message", text: JSON.stringify(refined), model: "claude-haiku-5-5" }]);
    await refine(p);
    expect(sent()[0]).toMatchObject({ model: "claude-haiku-5-5", max_tokens: 16000, output_config: { effort: "low" } });
    expect(sent()[0].fallbacks).toBeUndefined();
    expect(sent()[0].thinking).toBeUndefined();
  });

  it("asks Sonnet and Opus routes for the server-side refusal fallback, as before", async () => {
    const { p, sent } = provider([message(refined), message(refined)]);
    await refine(p, "coach_ask");
    await refine(p, "coach_advanced");
    expect(sent().map((b) => [b.model, b.fallbacks])).toEqual([
      ["claude-sonnet-5-5", "default"],
      ["claude-opus-5-5", "default"],
    ]);
  });

  it("sends each model its own way of switching thinking off", async () => {
    const { p, sent } = provider([message(refined), message(refined), message(refined)], {
      AI_ROUTE_REFINE: "claude-haiku-5-5,thinking=off",
      AI_ROUTE_TONE: "claude-sonnet-5-5,thinking=off",
      AI_ROUTE_COACH_ADVANCED: "claude-opus-5-5,thinking=off",
    });
    await refine(p, "refine");
    await refine(p, "tone");
    await refine(p, "coach_advanced");
    expect(sent().map((b) => b.thinking)).toEqual([{ type: "disabled" }, { type: "between_tools" }, undefined]);
  });

  it("records the route, the requested and the answering model, and reports the answering model back", async () => {
    const { p } = provider([{ kind: "message", text: JSON.stringify(refined), model: "claude-haiku-5-5", usage: { input_tokens: 1000, output_tokens: 100 } }]);
    const call: { servedModel?: string } = {};
    await refine(p, "refine", call);
    expect(call.servedModel).toBe("claude-haiku-5-5");
    expect(ledger()[0]).toMatchObject({ route: "refine", model: "claude-haiku-5-5", servedModel: "claude-haiku-5-5", estimatedCostUsd: 0.00015 });
  });
});

describe("stop reasons the SDK cannot parse", () => {
  it("reports a refusal that comes with plain text as a refusal, not as garbled output", async () => {
    const { p, http } = provider([{ kind: "message", text: "I can't help with that.", stop: "refusal", model: "claude-sonnet-5-5" }]);
    await expect(refine(p, "coach_ask")).rejects.toMatchObject({ kind: "declined", reason: "refusal" });
    expect(http.bodies).toHaveLength(1);
    expect(ledger()[0]).toMatchObject({ status: "refused", reason: "refusal" });
  });

  it("still gives Haiku its one Sonnet try when the refusal text is not JSON", async () => {
    const { p, sent } = provider([
      { kind: "message", text: "Sorry, I can't.", stop: "refusal", model: "claude-haiku-5-5" },
      { kind: "message", text: JSON.stringify(refined), model: "claude-sonnet-5-5" },
    ]);
    await refine(p);
    expect(sent().map((b) => b.model)).toEqual(["claude-haiku-5-5", "claude-sonnet-5-5"]);
  });

  it("reports an answer cut off mid-JSON as cut short", async () => {
    const { p } = provider([{ kind: "message", text: '{"options":[{"style":"Sh', stop: "max_tokens", model: "claude-haiku-5-5" }]);
    await expect(refine(p)).rejects.toMatchObject({ kind: "bad_output", reason: "output", message: "That answer got cut short. Please try again." });
    expect(ledger()[0]).toMatchObject({ status: "cut_off" });
  });
});

describe("fallback between models", () => {
  it("tries Sonnet once when Haiku refuses, and prices each answer by its own model", async () => {
    const { p, sent } = provider([
      refusal("claude-haiku-5-5", { input_tokens: 2000, output_tokens: 20 }),
      { kind: "message", text: JSON.stringify(refined), model: "claude-sonnet-5-5", usage: { input_tokens: 2000, output_tokens: 100 } },
    ]);
    const call: { servedModel?: string } = {};
    const result = await refine(p, "refine", call);
    expect(result.options).toHaveLength(1);
    expect(sent().map((b) => b.model)).toEqual(["claude-haiku-5-5", "claude-sonnet-5-5"]);
    expect(call.servedModel).toBe("claude-sonnet-5-5");
    const [entry] = ledger();
    expect(entry).toMatchObject({ status: "ok", attempts: 2, retries: 0, model: "claude-haiku-5-5", servedModel: "claude-sonnet-5-5" });
    // Haiku: 2000 x $0.10 + 20 x $0.50; Sonnet: 2000 x $2 + 100 x $10 (per million).
    expect(entry.estimatedCostUsd).toBeCloseTo(0.00021 + 0.005, 6);
    expect(entry.inputTokens).toBe(4000);
  });

  it("does not go further than Sonnet: a second refusal is the answer", async () => {
    const { p, http } = provider([refusal("claude-haiku-5-5"), refusal("claude-sonnet-5-5"), message(refined)]);
    await expect(refine(p)).rejects.toMatchObject({ kind: "declined", reason: "refusal" });
    expect(http.bodies).toHaveLength(2);
    expect(ledger()[0]).toMatchObject({ status: "refused", attempts: 2 });
  });

  it("never re-sends an unusable answer or an error to a bigger model", async () => {
    let calls = provider([{ kind: "message", text: "not json", model: "claude-haiku-5-5" }, message(refined)]);
    await expect(refine(calls.p)).rejects.toMatchObject({ kind: "bad_output" });
    expect(calls.sent().map((b) => b.model)).toEqual(["claude-haiku-5-5"]);

    calls = provider([{ kind: "error", status: 529, type: "overloaded_error" }, { kind: "message", text: JSON.stringify(refined), model: "claude-haiku-5-5" }]);
    await refine(calls.p);
    // An overload is retried on the same model, not escalated.
    expect(calls.sent().map((b) => b.model)).toEqual(["claude-haiku-5-5", "claude-haiku-5-5"]);
  });

  it("leaves Sonnet refusals to the API's own fallback instead of switching models itself", async () => {
    const { p, http } = provider([refusal("claude-sonnet-5-5"), message(refined)]);
    await expect(refine(p, "coach_ask")).rejects.toMatchObject({ kind: "declined" });
    expect(http.bodies).toHaveLength(1);
  });

  it("respects fallback=none", async () => {
    const { p, http } = provider([refusal("claude-haiku-5-5"), message(refined)], { AI_ROUTE_REFINE: "claude-haiku-5-5,fallback=none" });
    await expect(refine(p)).rejects.toMatchObject({ kind: "declined" });
    expect(http.bodies).toHaveLength(1);
  });

  it("checks the development spend limit before the fallback model is tried", async () => {
    const { p, http } = provider([refusal("claude-haiku-5-5", { input_tokens: 20_000, output_tokens: 0 }), message(refined)], {
      RR_DEV_SPEND_LIMIT_USD: "0.001",
    });
    await expect(refine(p)).rejects.toMatchObject({ reason: "budget" });
    expect(http.bodies).toHaveLength(1);
    expect(ledger()[0]).toMatchObject({ status: "blocked", attempts: 1, estimatedCostUsd: 0.002 });
  });
});
