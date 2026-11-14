import { appendFileSync, mkdirSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { checkSpend, DEFAULT_DEV_LIMIT_USD, resetSpendTracking, spendConfig, spendStatus } from "@/lib/ai/budget";
import { estimateCostUsd } from "@/lib/ai/pricing";
import { ledgerFile, recordAiUsage, toRecordLine, type AiUsageRecord } from "@/lib/ai/usage-log";

const VARS = ["RR_DEV_SPEND_LIMIT_USD", "RR_DEV_SPEND_PERIOD", "RR_DEV_SPEND_WARN_AT", "RR_ENVIRONMENT", "RR_USAGE_LOG_DIR"];
const saved: Record<string, string | undefined> = {};
let warnings: string[] = [];
let dir = "";

function record(costUsd: number, overrides: Partial<AiUsageRecord> = {}): AiUsageRecord {
  return {
    at: new Date().toISOString(),
    environment: "development",
    feature: "replies",
    task: "replies",
    route: "reply_standard",
    client: "app",
    requestId: null,
    model: "claude-opus-5-5",
    servedModel: "claude-opus-5-5",
    status: "ok",
    reason: null,
    httpStatus: 200,
    durationMs: 1200,
    attempts: 1,
    retries: 0,
    usageKnown: true,
    inputTokens: 2963,
    outputTokens: 1500,
    thinkingTokens: 1200,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
    estimatedCostUsd: costUsd,
    priced: true,
    ...overrides,
  };
}

beforeEach(() => {
  for (const name of VARS) saved[name] = process.env[name];
  for (const name of VARS) delete process.env[name];
  dir = mkdtempSync(join(tmpdir(), "rr-spend-"));
  process.env.RR_USAGE_LOG_DIR = dir;
  resetSpendTracking();
  warnings = [];
  vi.spyOn(console, "warn").mockImplementation((...args) => void warnings.push(args.join(" ")));
});

afterEach(() => {
  for (const name of VARS) {
    if (saved[name] === undefined) delete process.env[name];
    else process.env[name] = saved[name];
  }
  vi.restoreAllMocks();
});

describe("estimateCostUsd", () => {
  const tokens = (input: number, output: number, cacheRead = 0) => ({
    inputTokens: input,
    outputTokens: output,
    cacheReadInputTokens: cacheRead,
    cacheWrite5mInputTokens: 0,
    cacheWrite1hInputTokens: 0,
  });

  it("prices Opus 5.5 at $4 in and $20 out per million tokens", () => {
    expect(estimateCostUsd("claude-opus-5-5", tokens(2963, 1500))).toEqual({ costUsd: 0.041852, priced: true });
  });

  it("matches dated model names to the right family, longest name first", () => {
    expect(estimateCostUsd("claude-opus-5-5-20261101", tokens(1_000_000, 0)).costUsd).toBe(4);
    expect(estimateCostUsd("claude-opus-5-20260101", tokens(1_000_000, 0)).costUsd).toBe(5);
  });

  it("prices cache reads, cache writes and Haiku's long-prompt tier", () => {
    expect(estimateCostUsd("claude-sonnet-5-5", tokens(0, 0, 2_000_000)).costUsd).toBe(0.2);
    expect(
      estimateCostUsd("claude-sonnet-5-5", { ...tokens(0, 0), cacheWrite5mInputTokens: 1_000_000, cacheWrite1hInputTokens: 1_000_000 }).costUsd,
    ).toBe(6.5);
    expect(estimateCostUsd("claude-haiku-5-5", tokens(100_000, 1000)).costUsd).toBeCloseTo(0.0105, 6);
    expect(estimateCostUsd("claude-haiku-5-5", tokens(120_000, 100)).costUsd).toBeCloseTo(0.06025, 6);
  });

  it("never lets an unknown model look free", () => {
    const result = estimateCostUsd("claude-mystery-9", tokens(1_000_000, 1_000_000));
    expect(result.priced).toBe(false);
    expect(result.costUsd).toBe(60);
  });
});

describe("usage ledger", () => {
  it("writes only the listed fields, and replaces anything that is not a short label", () => {
    const leaky = { ...record(0.01, { feature: "Them: are you free tonight?" }), transcript: "Them: secret", prompt: "secret" };
    const line = toRecordLine(leaky as AiUsageRecord);
    const parsed = JSON.parse(line);
    expect(parsed.feature).toBe("invalid");
    expect(line).not.toContain("secret");
    expect(line).not.toContain("free tonight");
    expect(Object.keys(parsed)).toEqual([
      "at", "environment", "feature", "task", "route", "client", "requestId", "model", "servedModel", "status", "reason", "httpStatus",
      "durationMs", "attempts", "retries", "usageKnown", "inputTokens", "outputTokens", "thinkingTokens",
      "cacheReadInputTokens", "cacheCreationInputTokens", "estimatedCostUsd", "priced",
    ]);
  });

  it("logs one JSON line per call to the server log, and can be silenced", () => {
    const lines: string[] = [];
    const info = vi.spyOn(console, "info").mockImplementation((...args) => void lines.push(args.join(" ")));
    process.env.AI_USAGE_LOG = "on";
    recordAiUsage(record(0.001));
    process.env.AI_USAGE_LOG = "off";
    recordAiUsage(record(0.001));
    info.mockRestore();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatch(/^\[replyright\] ai_usage \{"at":/);
  });

  it("keeps no file in production unless a directory is configured", async () => {
    const { ledgerDirectory } = await import("@/lib/ai/usage-log");
    delete process.env.RR_USAGE_LOG_DIR;
    expect(ledgerDirectory("production")).toBeNull();
    expect(ledgerDirectory("development")).toMatch(/\.usage$/);
    process.env.RR_USAGE_LOG_DIR = "off";
    expect(ledgerDirectory("development")).toBeNull();
  });
});

describe("development spend limit", () => {
  it("defaults to $5 a day with warnings at 50, 75 and 90 percent, and does not apply in production", () => {
    expect(spendConfig("development")).toEqual({ limitUsd: DEFAULT_DEV_LIMIT_USD, period: "day", warnAt: [50, 75, 90] });
    expect(spendConfig("staging").limitUsd).toBe(5);
    process.env.RR_DEV_SPEND_LIMIT_USD = "0";
    expect(spendConfig("production").limitUsd).toBeNull();
  });

  it("reads its settings, and falls back to the default for a value that is not a number", () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "12.5";
    process.env.RR_DEV_SPEND_PERIOD = "month";
    process.env.RR_DEV_SPEND_WARN_AT = "25, 80";
    expect(spendConfig("development")).toEqual({ limitUsd: 12.5, period: "month", warnAt: [25, 80] });
    process.env.RR_DEV_SPEND_LIMIT_USD = "off";
    expect(spendConfig("development").limitUsd).toBeNull();
    process.env.RR_DEV_SPEND_LIMIT_USD = "lots";
    expect(spendConfig("development").limitUsd).toBe(5);
    expect(warnings.join("\n")).toMatch(/not a number/);
  });

  it("warns once at each threshold and stops at the limit", () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "1";
    recordAiUsage(record(0.5));
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toMatch(/at 50% of the limit/);
    recordAiUsage(record(0.01));
    expect(warnings).toHaveLength(1);
    recordAiUsage(record(0.29));
    expect(warnings[1]).toMatch(/at 80% of the limit \(past 75%\)/);
    recordAiUsage(record(0.15));
    expect(warnings[2]).toMatch(/at 95% of the limit \(past 90%\)/);
    expect(checkSpend().allowed).toBe(true);
    expect(spendStatus().state).toBe("warning");

    recordAiUsage(record(0.05));
    const check = checkSpend();
    expect(check.allowed).toBe(false);
    if (!check.allowed) {
      expect(check.message).toMatch(/reached its limit.*\$1\.00.*RR_DEV_SPEND_LIMIT_USD/);
      expect(check.status.state).toBe("stopped");
    }
    expect(warnings.filter((w) => /limit reached/.test(w))).toHaveLength(1);
    checkSpend();
    expect(warnings.filter((w) => /limit reached/.test(w))).toHaveLength(1);
  });

  it("survives a restart, because the total is read back from the ledger file", () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "1";
    recordAiUsage(record(0.6));
    resetSpendTracking(); // what a new process sees
    expect(spendStatus().spentUsd).toBe(0.6);
    recordAiUsage(record(0.4));
    resetSpendTracking();
    expect(checkSpend().allowed).toBe(false);
  });

  it("counts spend that another process (an eval run) appends to the same ledger", () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "1";
    expect(spendStatus().spentUsd).toBe(0);
    mkdirSync(dir, { recursive: true });
    appendFileSync(ledgerFile(dir, new Date()), `${toRecordLine(record(0.7, { feature: "eval_judge", task: "judge" }))}\n`);
    expect(spendStatus().spentUsd).toBe(0.7);
  });

  it("counts a day period from midnight UTC, and a month period from the first", () => {
    process.env.RR_DEV_SPEND_LIMIT_USD = "10";
    const now = new Date("2026-11-13T12:00:00Z");
    recordAiUsage(record(1, { at: "2026-11-12T23:30:00.000Z" }));
    recordAiUsage(record(2, { at: "2026-11-13T00:10:00.000Z" }));
    expect(spendStatus(now)).toMatchObject({ spentUsd: 2, period: "day", resetsAt: "2026-11-14T00:00:00.000Z" });
    process.env.RR_DEV_SPEND_PERIOD = "month";
    expect(spendStatus(now)).toMatchObject({ spentUsd: 3, period: "month", resetsAt: "2026-12-01T00:00:00.000Z" });
  });

  it("still counts in memory when there is no ledger file", () => {
    process.env.RR_USAGE_LOG_DIR = "off";
    process.env.RR_DEV_SPEND_LIMIT_USD = "0.02";
    recordAiUsage(record(0.03));
    expect(checkSpend().allowed).toBe(false);
  });

  it("never blocks production", () => {
    process.env.RR_ENVIRONMENT = "production";
    process.env.RR_DEV_SPEND_LIMIT_USD = "0";
    recordAiUsage(record(50, { environment: "production" }));
    expect(spendStatus().active).toBe(false);
    expect(checkSpend().allowed).toBe(true);
  });
});
