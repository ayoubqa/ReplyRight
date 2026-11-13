import "server-only";
import type { AiHealth, FailureReason } from "@/lib/domain/contracts";

/**
 * A small in-memory record of whether AI calls are working, so `/status` can
 * tell the app "connected and answering" apart from "configured but failing".
 *
 * It is per server process. On serverless hosting each instance keeps its own
 * record, so treat it as a hint rather than monitoring.
 */
const store = globalThis as unknown as { __replyrightAiHealth?: AiHealth };

function current(): AiHealth {
  store.__replyrightAiHealth ??= { state: "untested", lastSuccessAt: null, lastFailureAt: null, lastFailureReason: null };
  return store.__replyrightAiHealth;
}

/** Failures that say something about the service, as opposed to one request. */
const SERVICE_FAILURES = new Set<FailureReason>(["credentials", "billing", "model", "overloaded", "timeout", "network"]);

export function recordAiSuccess(): void {
  const health = current();
  health.state = "ok";
  health.lastSuccessAt = new Date().toISOString();
}

export function recordAiFailure(reason: FailureReason): void {
  if (!SERVICE_FAILURES.has(reason)) return;
  const health = current();
  health.state = "failing";
  health.lastFailureAt = new Date().toISOString();
  health.lastFailureReason = reason;
}

export function aiHealth(): AiHealth {
  return { ...current() };
}

/** For tests. */
export function resetAiHealth(): void {
  store.__replyrightAiHealth = undefined;
}
