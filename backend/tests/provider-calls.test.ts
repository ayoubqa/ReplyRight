import Anthropic from "@anthropic-ai/sdk";
import { mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AnthropicProvider, configuredRetries, retryDelayMs } from "@/lib/ai/anthropic-provider";
import { resetSpendTracking } from "@/lib/ai/budget";
import { resetAiHealth } from "@/lib/ai/health";
import type { AiUsageRecord } from "@/lib/ai/usage-log";
import { refineRequestSchema, repliesRequestSchema } from "@/lib/domain/contracts";
import { fakeAnthropic, message, type Step } from "./helpers/anthropic-http";

/**
 * Retries, cancellation, the spend limit and usage records, with the real SDK
 * talking to a fake HTTP API. Nothing here reaches Anthropic or spends money.
 */
const models = { analyze: "claude-opus-5-5", replies: "claude-opus-5-5", refine: "claude-opus-5-5", coach: "claude-opus-5-5" };
const efforts = { analyze: "low", replies: "medium", refine: "low", coach: "medium" } as const;
const MARKER = "MARKER-private-message-4417";
const refineRequest = refineRequestSchema.parse({ text: `hey ${MARKER}, how was the gig?`, action: "shorter" });
const refined = { options: [{ style: "Shorter", text: "how was the gig?", why: "Same question." }], note: null };
const replies = { note: "Here you go.", replies: [{ style: "Natural", text: "haha fair", why: "Easy." }], headsUp: null };
const VARS = ["RR_USAGE_LOG_DIR", "RR_DEV_SPEND_LIMIT_USD", "AI_MAX_RETRIES", "RR_ENVIRONMENT", "ANTHROPIC_LOG"];
const saved: Record<string, string | undefined> = {};
let dir = "";

function setup(steps: Step[], options: Partial<ConstructorParameters<typeof AnthropicProvider>[0]> = {}) {
  const http = fakeAnthropic(steps);
  const provider = new AnthropicProvider({
    apiKey: "test-key-not-real",
    models,
    efforts,
    environment: "development",
    retryBaseDelayMs: 1,
    fetch: http.fetch,
    ...options,
  });
  return { provider, http };
}

function ledger(): AiUsageRecord[] {
  return readdirSync(dir)
    .flatMap((file) => readFileSync(join(dir, file), "utf8").split("\n"))
    .filter(Boolean)
    .map((line) => JSON.parse(line) as AiUsageRecord);
}

const refine = (provider: AnthropicProvider, signal?: AbortSignal) =>
  provider.refine({ request: refineRequest, options: { includeSamples: false }, call: { feature: "refine", client: "app", requestId: "req-1", signal } });

beforeEach(() => {
  for (const name of VARS) saved[name] = process.env[name];
  for (const name of VARS) delete process.env[name];
  dir = mkdtempSync(join(tmpdir(), "rr-calls-"));
  process.env.RR_USAGE_LOG_DIR = dir;
  resetSpendTracking();
  resetAiHealth();
  vi.spyOn(console, "error").mockImplementation(() => {});
  vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  for (const name of VARS) {
    if (saved[name] === undefined) delete process.env[name];
    else process.env[name] = saved[name];
  }
  vi.restoreAllMocks();
});

describe("usage records", () => {
  it("records one call with its tokens, thinking, cache use and estimated cost, and nothing it was about", async () => {
    const { provider, http } = setup([
      message(refined, {
        input_tokens: 2513,
        output_tokens: 500,
        cache_read_input_tokens: 100,
        cache_creation_input_tokens: 0,
        output_tokens_details: { thinking_tokens: 400 },
      }),
    ]);
    const result = await refine(provider);
    expect(result.options[0].text).toBe("how was the gig?");
    expect(http.bodies[0]).toContain(MARKER); // the model does get the message...

    const [entry] = ledger();
    expect(entry).toMatchObject({
      environment: "development",
      feature: "refine",
      task: "refine",
      client: "app",
      requestId: "req-1",
      model: "claude-opus-5-5",
      servedModel: "claude-opus-5-5",
      status: "ok",
      httpStatus: 200,
      attempts: 1,
      retries: 0,
      usageKnown: true,
      inputTokens: 2513,
      outputTokens: 500,
      thinkingTokens: 400,
      cacheReadInputTokens: 100,
      cacheCreationInputTokens: 0,
      priced: true,
    });
    // 2513 x $4 + 500 x $20 + 100 x $0.20, per million tokens.
    expect(entry.estimatedCostUsd).toBeCloseTo(0.020072, 6);
    expect(entry.durationMs).toBeGreaterThanOrEqual(0);
    // ...and the ledger never does.
    expect(readdirSync(dir).map((f) => readFileSync(join(dir, f), "utf8")).join("")).not.toContain(MARKER);
  });

  it("still counts the tokens of a billed answer that cannot be parsed", async () => {
    const { provider, http } = setup([{ kind: "message", text: "this is not JSON", usage: { input_tokens: 2000, output_tokens: 300 } }]);
    await expect(refine(provider)).rejects.toMatchObject({ kind: "bad_output", reason: "output" });
    expect(http.remaining()).toBe(0);
    expect(ledger()).toEqual([expect.objectContaining({ status: "bad_output", attempts: 1, retries: 0, inputTokens: 2000, outputTokens: 300 })]);
    expect(ledger()[0].estimatedCostUsd).toBeCloseTo(0.014, 6);
  });

  it("prices the model that answered when a refusal fallback served the request", async () => {
    const { provider } = setup([{ kind: "message", text: JSON.stringify(refined), model: "claude-opus-5", usage: { input_tokens: 1_000_000, output_tokens: 0 } }]);
    await refine(provider);
    expect(ledger()[0]).toMatchObject({ model: "claude-opus-5-5", servedModel: "claude-opus-5", estimatedCostUsd: 5 });
  });

  it("records a cut-off answer and a refusal as such", async () => {
    const { provider } = setup([
      { kind: "message", text: JSON.stringify(refined), stop: "max_tokens" },
      { kind: "message", text: JSON.stringify(refined), stop: "refusal" },
    ]);
    await expect(refine(provider)).rejects.toMatchObject({ kind: "bad_output" });
    await expect(refine(provider)).rejects.toMatchObject({ kind: "declined" });
    expect(ledger().map((e) => e.status)).toEqual(["cut_off", "refused"]);
  });
});

describe("retries", () => {
  it("retries an overloaded API once, with backoff, and records the retry", async () => {
    const { provider, http } = setup([{ kind: "error", status: 529, type: "overloaded_error" }, message(refined)]);
    await refine(provider);
    expect(http.bodies).toHaveLength(2);
    expect(ledger()[0]).toMatchObject({ status: "ok", attempts: 2, retries: 1 });
  });

  it("gives up after one retry, so one tap costs at most two attempts", async () => {
    const { provider, http } = setup([
      { kind: "error", status: 529, type: "overloaded_error" },
      { kind: "error", status: 529, type: "overloaded_error" },
      message(refined),
    ]);
    await expect(refine(provider)).rejects.toMatchObject({ kind: "unavailable", reason: "overloaded" });
    expect(http.bodies).toHaveLength(2);
    expect(ledger()[0]).toMatchObject({ status: "error", reason: "overloaded", attempts: 2, retries: 1, httpStatus: 529 });
  });

  it("reads AI_MAX_RETRIES, treating an empty value as the default", () => {
    expect(configuredRetries()).toBe(1);
    process.env.AI_MAX_RETRIES = "";
    expect(configuredRetries()).toBe(1);
    process.env.AI_MAX_RETRIES = "2";
    expect(configuredRetries()).toBe(2);
    process.env.AI_MAX_RETRIES = "9";
    expect(configuredRetries()).toBe(3);
    process.env.AI_MAX_RETRIES = "lots";
    expect(configuredRetries()).toBe(1);
  });

  it("respects AI_MAX_RETRIES=0", async () => {
    process.env.AI_MAX_RETRIES = "0";
    const { provider, http } = setup([{ kind: "error", status: 529, type: "overloaded_error" }, message(refined)]);
    await expect(refine(provider)).rejects.toMatchObject({ reason: "overloaded" });
    expect(http.bodies).toHaveLength(1);
  });

  it.each([
    [400, "invalid_request_error", "misconfigured"],
    [401, "authentication_error", "unavailable"],
    [403, "permission_error", "unavailable"],
    [404, "not_found_error", "unavailable"],
    [413, "request_too_large", "unavailable"],
  ])("never retries a %i, which would fail the same way again", async (status, type, kind) => {
    const { provider, http } = setup([{ kind: "error", status, type }, message(refined)]);
    await expect(refine(provider)).rejects.toMatchObject({ kind });
    expect(http.bodies).toHaveLength(1);
    expect(ledger()[0]).toMatchObject({ attempts: 1, retries: 0, status: "error" });
  });

  it("never retries a timeout, because the first answer may already have been billed", async () => {
    const { provider, http } = setup([{ kind: "hang" }, message(refined)], { timeoutMs: 40 });
    await expect(refine(provider)).rejects.toMatchObject({ kind: "unavailable", reason: "timeout" });
    expect(http.bodies).toHaveLength(1);
    expect(ledger()[0]).toMatchObject({ status: "error", reason: "timeout", attempts: 1, retries: 0, usageKnown: false });
  });

  it("follows the API's own hints: Retry-After within reason, x-should-retry, and a long wait means fail now", async () => {
    let calls = setup([{ kind: "error", status: 429, type: "rate_limit_error", headers: { "retry-after": "0" } }, message(refined)]);
    await refine(calls.provider);
    expect(calls.http.bodies).toHaveLength(2);

    calls = setup([{ kind: "error", status: 429, type: "rate_limit_error", headers: { "retry-after": "30" } }, message(refined)]);
    await expect(refine(calls.provider)).rejects.toMatchObject({ kind: "rate_limited" });
    expect(calls.http.bodies).toHaveLength(1);

    calls = setup([{ kind: "error", status: 500, type: "api_error", headers: { "x-should-retry": "false" } }, message(refined)]);
    await expect(refine(calls.provider)).rejects.toMatchObject({ kind: "unavailable" });
    expect(calls.http.bodies).toHaveLength(1);
  });

  it("backs off exponentially, capped at four seconds, with jitter", () => {
    const error = Anthropic.APIError.generate(503, { type: "error", error: { type: "api_error", message: "busy" } }, "busy", new Headers());
    const random = vi.spyOn(Math, "random").mockReturnValue(1);
    expect(retryDelayMs(error, 0, 500)).toBe(500);
    expect(retryDelayMs(error, 1, 500)).toBe(1000);
    expect(retryDelayMs(error, 5, 500)).toBe(4000);
    random.mockReturnValue(0);
    expect(retryDelayMs(error, 0, 500)).toBe(400);
  });
});

describe("cancellation", () => {
  it("stops the call when the caller goes away, without retrying", async () => {
    const { provider, http } = setup([{ kind: "hang" }, message(refined)]);
    const controller = new AbortController();
    const pending = refine(provider, controller.signal);
    setTimeout(() => controller.abort(), 10);
    await expect(pending).rejects.toMatchObject({ kind: "unavailable", reason: "cancelled" });
    expect(http.bodies).toHaveLength(1);
    expect(ledger()[0]).toMatchObject({ status: "cancelled", reason: "cancelled", usageKnown: false });
  });

  it("does not start a retry for a caller that left during the backoff", async () => {
    const { provider, http } = setup([{ kind: "error", status: 529, type: "overloaded_error" }, message(refined)], { retryBaseDelayMs: 300 });
    const controller = new AbortController();
    const pending = refine(provider, controller.signal);
    setTimeout(() => controller.abort(), 30);
    await expect(pending).rejects.toMatchObject({ reason: "cancelled" });
    expect(http.bodies).toHaveLength(1);
  });

  it("sends nothing for a caller that has already gone", async () => {
    const { provider, http } = setup([message(refined)]);
    await expect(refine(provider, AbortSignal.abort())).rejects.toMatchObject({ reason: "cancelled" });
    expect(http.remaining()).toBe(1);
  });
});

describe("spend limit", () => {
  it("sends nothing once the development limit is reached, and records the blocked call", async () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "0";
    const { provider, http } = setup([message(refined)]);
    await expect(refine(provider)).rejects.toMatchObject({ kind: "unavailable", reason: "budget" });
    expect(http.remaining()).toBe(1);
    expect(ledger()[0]).toMatchObject({ status: "blocked", reason: "budget", attempts: 0, estimatedCostUsd: 0 });
  });

  it("checks the limit again before a retry", async () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "0.001";
    const { provider, http } = setup([
      { kind: "message", text: JSON.stringify(replies), usage: { input_tokens: 1000, output_tokens: 100 } },
      { kind: "error", status: 529, type: "overloaded_error" },
      message(replies),
    ]);
    const request = repliesRequestSchema.parse({ conversation: "Them: hi" });
    await provider.replies({ request, images: [], options: { includeSamples: false } }); // spends $0.006
    await expect(provider.replies({ request, images: [], options: { includeSamples: false } })).rejects.toMatchObject({ reason: "budget" });
    expect(http.bodies).toHaveLength(1);
  });

  it("does not apply in production", async () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "0";
    const { provider, http } = setup([message(refined)], { environment: "production" });
    process.env.RR_ENVIRONMENT = "production";
    await refine(provider);
    expect(http.remaining()).toBe(0);
  });
});

describe("request shape", () => {
  it("still sends the same model, output limit, effort and refusal fallback as before", async () => {
    const { provider, http } = setup([message(refined)]);
    await refine(provider);
    const sent = JSON.parse(http.bodies[0]);
    expect(sent).toMatchObject({ model: "claude-opus-5-5", max_tokens: 16000, fallbacks: "default", output_config: { effort: "low" } });
    expect(sent.thinking).toBeUndefined();
  });

  it("keeps the SDK quiet even when ANTHROPIC_LOG=debug, so request bodies are never printed", () => {
    process.env.ANTHROPIC_LOG = "debug";
    const { provider } = setup([]);
    expect((provider as unknown as { client: { logLevel: string } }).client.logLevel).toBe("warn");
  });
});
