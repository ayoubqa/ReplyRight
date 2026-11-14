import "server-only";
import { closeSync, openSync, readSync, statSync } from "node:fs";
import { serverEnvironment, type ServerEnvironment } from "@/lib/server/environment";
import { ledgerDirectory, ledgerFile, onUsageRecorded, type AiUsageRecord } from "./usage-log";

/**
 * Development spend limit.
 *
 *   RR_DEV_SPEND_LIMIT_USD   the most AI spend allowed per period, in US dollars. Default 5.
 *                            "off" disables the limit (warnings stop too).
 *   RR_DEV_SPEND_PERIOD      day | month (UTC). Default day.
 *   RR_DEV_SPEND_WARN_AT     percentages that log a warning once per period. Default 50,75,90.
 *
 * It applies whenever the server is not production (development and staging),
 * and to the eval harness. Production has no spend limit: stopping paying
 * users' requests is a product decision, so production relies on the monthly
 * limit set on the production key in the Anthropic Console.
 *
 * How it is enforced: before every attempt to call the AI provider, retries
 * included, the provider asks `checkSpend()`. Once the estimated spend for the
 * period reaches the limit, nothing more is sent until the period resets; the
 * request fails with reason "budget". The total is read from the usage ledger
 * file, so it survives restarts and covers every process on this machine that
 * writes to the same ledger (the dev server and eval runs).
 *
 * Limits of the estimate: it is computed from the token counts the API reports
 * and the list prices in `./pricing.ts`, not from Anthropic's invoice. Calls
 * already in flight when the limit is reached still finish, so spend can end a
 * little above the limit. A call that times out or is cancelled may be billed
 * without reporting usage, and then it adds nothing here.
 */
export type SpendPeriod = "day" | "month";

export interface SpendConfig {
  /** Null when there is no limit (production, or switched off). */
  limitUsd: number | null;
  period: SpendPeriod;
  warnAt: number[];
}

export const DEFAULT_DEV_LIMIT_USD = 5;
const DEFAULT_WARN_AT = [50, 75, 90];

let invalidConfigWarned = false;

export function spendConfig(environment: ServerEnvironment = serverEnvironment()): SpendConfig {
  const period: SpendPeriod = process.env.RR_DEV_SPEND_PERIOD?.trim().toLowerCase() === "month" ? "month" : "day";
  const warnAt = parseWarnAt(process.env.RR_DEV_SPEND_WARN_AT);
  if (environment === "production") return { limitUsd: null, period, warnAt };

  const raw = process.env.RR_DEV_SPEND_LIMIT_USD?.trim();
  if (raw?.toLowerCase() === "off") return { limitUsd: null, period, warnAt };
  if (!raw) return { limitUsd: DEFAULT_DEV_LIMIT_USD, period, warnAt };
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    if (!invalidConfigWarned) {
      invalidConfigWarned = true;
      console.warn(`[replyright] RR_DEV_SPEND_LIMIT_USD="${raw.slice(0, 20)}" is not a number. Using $${DEFAULT_DEV_LIMIT_USD}.`);
    }
    return { limitUsd: DEFAULT_DEV_LIMIT_USD, period, warnAt };
  }
  return { limitUsd: value, period, warnAt };
}

function parseWarnAt(raw: string | undefined): number[] {
  if (!raw?.trim()) return DEFAULT_WARN_AT;
  const values = raw
    .split(",")
    .map((part) => Number(part.trim()))
    .filter((n) => Number.isFinite(n) && n > 0 && n < 100);
  return values.length > 0 ? [...new Set(values)].sort((a, b) => a - b) : DEFAULT_WARN_AT;
}

// ---------------------------------------------------------------- totals

/** Spend per UTC day ("2026-11-13" -> dollars). */
const days = new Map<string, number>();
/** How far each ledger file has been read, so only new lines are parsed. */
const cursors = new Map<string, { offset: number; partial: string }>();
const warned = new Set<string>();

function dayKey(at: Date): string {
  return at.toISOString().slice(0, 10);
}

function add(at: string, cost: number) {
  if (!Number.isFinite(cost) || cost <= 0) return;
  const key = at.slice(0, 10);
  days.set(key, (days.get(key) ?? 0) + cost);
}

/** Reads lines appended to this month's ledger since the last look, by this process or another. */
function catchUp(now: Date) {
  const directory = ledgerDirectory();
  if (!directory) return;
  const path = ledgerFile(directory, now);
  let size: number;
  try {
    size = statSync(path).size;
  } catch {
    return; // No file yet: nothing spent this month.
  }
  const cursor = cursors.get(path) ?? { offset: 0, partial: "" };
  if (size < cursor.offset) {
    // The file was truncated or replaced. Start again from the top.
    cursor.offset = 0;
    cursor.partial = "";
    for (const key of [...days.keys()]) if (key.startsWith(now.toISOString().slice(0, 7))) days.delete(key);
  }
  if (size === cursor.offset) {
    cursors.set(path, cursor);
    return;
  }
  const length = size - cursor.offset;
  const buffer = Buffer.alloc(length);
  const fd = openSync(path, "r");
  try {
    readSync(fd, buffer, 0, length, cursor.offset);
  } finally {
    closeSync(fd);
  }
  cursor.offset = size;
  const text = cursor.partial + buffer.toString("utf8");
  const lines = text.split("\n");
  cursor.partial = lines.pop() ?? "";
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const record = JSON.parse(line) as Partial<AiUsageRecord>;
      if (typeof record.at === "string" && typeof record.estimatedCostUsd === "number") {
        add(record.at, record.estimatedCostUsd);
      }
    } catch {
      // A damaged line is skipped rather than stopping the count.
    }
  }
  cursors.set(path, cursor);
}

// The ledger tells the guard about every record. When the record reached the
// file, the next catch-up counts it; otherwise it is counted in memory here.
onUsageRecorded((record, writtenToFile) => {
  if (!writtenToFile) add(record.at, record.estimatedCostUsd);
  warnIfNeeded(new Date());
});

function periodStart(now: Date, period: SpendPeriod): Date {
  return period === "day"
    ? new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
    : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
}

function periodEnd(now: Date, period: SpendPeriod): Date {
  return period === "day"
    ? new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1))
    : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
}

function spentIn(now: Date, period: SpendPeriod): number {
  catchUp(now);
  if (period === "day") return days.get(dayKey(now)) ?? 0;
  const month = now.toISOString().slice(0, 7);
  let total = 0;
  for (const [key, value] of days) if (key.startsWith(month)) total += value;
  return total;
}

export interface SpendStatus {
  /** False when no limit applies (production, or switched off). */
  active: boolean;
  limitUsd: number | null;
  spentUsd: number;
  period: SpendPeriod;
  periodStart: string;
  resetsAt: string;
  /** Spend as a percentage of the limit, rounded down. Null without a limit. */
  percent: number | null;
  state: "ok" | "warning" | "stopped";
}

export function spendStatus(now = new Date()): SpendStatus {
  const config = spendConfig();
  const spent = spentIn(now, config.period);
  const base = {
    spentUsd: Math.round(spent * 10_000) / 10_000,
    period: config.period,
    periodStart: periodStart(now, config.period).toISOString(),
    resetsAt: periodEnd(now, config.period).toISOString(),
  };
  if (config.limitUsd === null) return { active: false, limitUsd: null, percent: null, state: "ok", ...base };
  const percent = config.limitUsd === 0 ? 100 : Math.floor((spent / config.limitUsd) * 100);
  const lowest = config.warnAt[0] ?? 100;
  const state = spent >= config.limitUsd ? "stopped" : percent >= lowest ? "warning" : "ok";
  return { active: true, limitUsd: config.limitUsd, percent, state, ...base };
}

/**
 * Asked before every AI attempt. `pendingUsd` is what earlier attempts of the
 * same call have already cost (a refusal before a fallback, say): it is not in
 * the ledger yet, because a call is recorded once it ends.
 */
export function checkSpend(
  now = new Date(),
  pendingUsd = 0,
): { allowed: true } | { allowed: false; status: SpendStatus; message: string } {
  const recorded = spendStatus(now);
  const spent = recorded.spentUsd + Math.max(0, pendingUsd);
  const status: SpendStatus =
    recorded.active && recorded.limitUsd !== null && spent >= recorded.limitUsd
      ? { ...recorded, spentUsd: Math.round(spent * 10_000) / 10_000, state: "stopped" }
      : recorded;
  if (!status.active || status.state !== "stopped") return { allowed: true };
  warnIfNeeded(now, status);
  const limit = formatUsd(status.limitUsd ?? 0);
  const message =
    `Development AI spending has reached its limit (${formatUsd(status.spentUsd)} of ${limit} this ${status.period}). ` +
    `Nothing more is sent to the AI provider until ${status.resetsAt}. Raise RR_DEV_SPEND_LIMIT_USD to continue.`;
  return { allowed: false, status, message };
}

function warnIfNeeded(now: Date, known?: SpendStatus) {
  const status = known ?? spendStatus(now);
  if (!status.active || status.limitUsd === null || status.percent === null) return;
  const key = (label: string) => `${status.periodStart}:${status.limitUsd}:${label}`;
  if (status.state === "stopped") {
    if (warned.has(key("stop"))) return;
    warned.add(key("stop"));
    for (const t of spendConfig().warnAt) warned.add(key(String(t)));
    console.warn(
      `[replyright] Development AI spend limit reached: ${formatUsd(status.spentUsd)} of ${formatUsd(status.limitUsd)} this ${status.period}. ` +
        `AI requests are blocked until ${status.resetsAt}.`,
    );
    return;
  }
  const crossed = spendConfig().warnAt.filter((t) => status.percent! >= t && !warned.has(key(String(t))));
  if (crossed.length === 0) return;
  for (const t of crossed) warned.add(key(String(t)));
  const highest = crossed[crossed.length - 1];
  console.warn(
    `[replyright] Development AI spend is at ${status.percent}% of the limit (past ${highest}%): ` +
      `${formatUsd(status.spentUsd)} of ${formatUsd(status.limitUsd)} this ${status.period}. Resets ${status.resetsAt}.`,
  );
}

function formatUsd(value: number): string {
  return `$${value.toFixed(value < 1 ? 4 : 2)}`;
}

/** For tests. */
export function resetSpendTracking(): void {
  days.clear();
  cursors.clear();
  warned.clear();
  invalidConfigWarned = false;
}
