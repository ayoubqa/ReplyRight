import "server-only";
import { appendFileSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import type { FailureReason } from "@/lib/domain/contracts";
import { serverEnvironment, type ServerEnvironment } from "@/lib/server/environment";

/**
 * One record per AI call: what it was for, which model, how many tokens, what
 * it cost (estimated) and how it ended. It is the only place token use and
 * spend are recorded, and the spend guard (`./budget.ts`) adds it up.
 *
 * A record holds numbers and short labels only. It never holds a prompt, a
 * conversation, a draft, a reply, a screenshot, a name, an install id, an IP
 * address or a key. `toRecordLine` builds the line from an explicit list of
 * fields, so nothing else can slip in.
 *
 * Where records go:
 *   - the server log, as one JSON line per call (`[replyright] ai_usage {...}`),
 *     unless AI_USAGE_LOG=off;
 *   - outside production, also a local file per month in `backend/.usage/`
 *     (ignored by git), so totals survive restarts and are shared by the dev
 *     server and the eval harness. RR_USAGE_LOG_DIR moves it ("off" disables it).
 */
export type AiCallStatus =
  /** An answer came back and was usable. */
  | "ok"
  /** The model declined. */
  | "refused"
  /** The answer hit max_tokens. */
  | "cut_off"
  /** An answer came back but could not be used. */
  | "bad_output"
  /** The provider returned an error, or could not be reached. */
  | "error"
  /** The caller went away and the call was stopped. */
  | "cancelled"
  /** Not sent: the development spend limit is reached. */
  | "blocked";

export interface AiUsageRecord {
  /** When the call started (ISO 8601, UTC). */
  at: string;
  environment: ServerEnvironment;
  /** What the call was for, such as "read_screenshot", "replies" or "keyboard_rewrite". */
  feature: string;
  /** The provider task behind the feature: analyze, replies, refine, coach, or judge for evals. */
  task: string;
  /** Which route (model policy) served it, such as "reply_simple" (see `./router.ts`). */
  route: string;
  /** Which client asked: app, keyboard, share, diagnostics, eval or other. */
  client: string;
  /** The server's request id (the X-RR-Request header), for matching a call to its request log line. */
  requestId: string | null;
  /** The model that was asked for. */
  model: string;
  /** The model that answered, when the API says (it can differ after a refusal fallback). */
  servedModel: string | null;
  status: AiCallStatus;
  reason: FailureReason | null;
  /** The provider's HTTP status on the last attempt, when there was a response. */
  httpStatus: number | null;
  durationMs: number;
  /** HTTP attempts made, including retries and the one-time fallback recovery. */
  attempts: number;
  /** Attempts repeated after a recoverable failure. */
  retries: number;
  /**
   * False when an attempt may have been billed without the API reporting usage
   * (a timeout or a cancelled call). The cost below then covers only what was reported.
   */
  usageKnown: boolean;
  inputTokens: number;
  /** All output tokens, thinking included. This is what output is billed on. */
  outputTokens: number;
  /** The part of outputTokens spent on thinking, when the API reports it. */
  thinkingTokens: number | null;
  cacheReadInputTokens: number;
  cacheCreationInputTokens: number;
  /** Estimated from the token counts and `./pricing.ts`. */
  estimatedCostUsd: number;
  /** False when the model is not in the price table and the highest known prices were used. */
  priced: boolean;
}

const FIELDS: (keyof AiUsageRecord)[] = [
  "at",
  "environment",
  "feature",
  "task",
  "route",
  "client",
  "requestId",
  "model",
  "servedModel",
  "status",
  "reason",
  "httpStatus",
  "durationMs",
  "attempts",
  "retries",
  "usageKnown",
  "inputTokens",
  "outputTokens",
  "thinkingTokens",
  "cacheReadInputTokens",
  "cacheCreationInputTokens",
  "estimatedCostUsd",
  "priced",
];

/** Labels are short machine words. Anything else is replaced, so free text can never be logged by mistake. */
const LABEL = /^[A-Za-z0-9._:-]{1,64}$/;

export function toRecordLine(record: AiUsageRecord): string {
  const out: Record<string, unknown> = {};
  for (const field of FIELDS) {
    const value = record[field];
    if (typeof value === "string" && field !== "at" && !LABEL.test(value)) {
      out[field] = "invalid";
    } else {
      out[field] = value ?? null;
    }
  }
  return JSON.stringify(out);
}

/** Where the ledger files live, or null when there is no file. */
export function ledgerDirectory(environment: ServerEnvironment = serverEnvironment()): string | null {
  const configured = process.env.RR_USAGE_LOG_DIR?.trim();
  if (configured?.toLowerCase() === "off") return null;
  if (configured) return resolve(configured);
  return environment === "production" ? null : resolve(process.cwd(), ".usage");
}

export function ledgerFile(directory: string, at: Date): string {
  return join(directory, `ai-usage-${at.toISOString().slice(0, 7)}.jsonl`);
}

type Listener = (record: AiUsageRecord, writtenToFile: boolean) => void;
const listeners: Listener[] = [];
let fileWarningShown = false;

/** The spend guard subscribes here. */
export function onUsageRecorded(listener: Listener): void {
  listeners.push(listener);
}

/** Writes one record to the log and, where configured, the ledger file. Never throws. */
export function recordAiUsage(record: AiUsageRecord): void {
  const line = toRecordLine(record);
  if (process.env.AI_USAGE_LOG?.trim().toLowerCase() !== "off") {
    console.info(`[replyright] ai_usage ${line}`);
  }

  let written = false;
  const directory = ledgerDirectory(record.environment);
  if (directory) {
    try {
      mkdirSync(directory, { recursive: true });
      appendFileSync(ledgerFile(directory, new Date(record.at)), `${line}\n`, { encoding: "utf8" });
      written = true;
    } catch (error) {
      if (!fileWarningShown) {
        fileWarningShown = true;
        console.warn(
          `[replyright] Could not write the AI usage ledger in ${directory} (${error instanceof Error ? error.name : "error"}). ` +
            "Spend is still counted in memory, but the development limit will not survive a restart.",
        );
      }
    }
  }
  for (const listener of listeners) {
    try {
      listener(record, written);
    } catch {
      // A listener must never break an AI call.
    }
  }
}
