import "server-only";
import type { Tier, UsageSnapshot } from "@/lib/domain/contracts";
import { getPlans, usageLimitsEnabled } from "./plans";

export type Meter = "generation" | "coach";

interface Counters {
  generation: number;
  coach: number;
}

/**
 * Daily usage counters.
 *
 * The MVP keeps them in memory, which is correct for a single instance and
 * resets on deploy. `UsageStore` is the seam for a shared store (Redis,
 * Postgres) when the backend scales out or accounts are added.
 */
export interface UsageStore {
  read(key: string): Counters;
  add(key: string, meter: Meter, amount: number): Counters;
}

class MemoryUsageStore implements UsageStore {
  private readonly counters = new Map<string, Counters>();

  read(key: string): Counters {
    return this.counters.get(key) ?? { generation: 0, coach: 0 };
  }

  add(key: string, meter: Meter, amount: number): Counters {
    const next = { ...this.read(key) };
    next[meter] = Math.max(0, next[meter] + amount);
    this.counters.set(key, next);
    if (this.counters.size > 50_000) this.prune();
    return next;
  }

  private prune() {
    const today = dayKey(Date.now());
    for (const key of this.counters.keys()) {
      if (!key.startsWith(today)) this.counters.delete(key);
    }
  }

  clear() {
    this.counters.clear();
  }
}

const store = new MemoryUsageStore();

function dayKey(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

function nextReset(now: number): string {
  const d = new Date(now);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)).toISOString();
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Who usage is counted against: the app's anonymous install id when present,
 * otherwise the caller's IP. The install id is a random UUID created on the
 * device; it is not tied to a person or to Apple identifiers.
 */
export function usageSubject(request: Request): string {
  const install = request.headers.get("x-rr-install")?.trim();
  if (install && UUID.test(install)) return `install:${install.toLowerCase()}`;
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return `ip:${forwarded || request.headers.get("x-real-ip") || "local"}`;
}

function toSnapshot(tier: Tier, counters: Counters, now: number): UsageSnapshot {
  const plan = getPlans()[tier];
  const part = (used: number, limit: number) => ({ used, limit, remaining: Math.max(0, limit - used) });
  return {
    tier,
    generations: part(counters.generation, plan.dailyGenerations),
    coach: part(counters.coach, plan.dailyCoachMessages),
    resetsAt: nextReset(now),
  };
}

export function usageSnapshot(subject: string, tier: Tier, now = Date.now()): UsageSnapshot {
  return toSnapshot(tier, store.read(`${dayKey(now)}:${subject}`), now);
}

/** Reserves one unit. Returns ok=false (and consumes nothing) when the daily limit is reached. */
export function consumeUsage(
  subject: string,
  tier: Tier,
  meter: Meter,
  now = Date.now(),
): { ok: boolean; usage: UsageSnapshot } {
  const key = `${dayKey(now)}:${subject}`;
  const plan = getPlans()[tier];
  const limit = meter === "generation" ? plan.dailyGenerations : plan.dailyCoachMessages;
  const current = store.read(key);
  if (usageLimitsEnabled() && current[meter] >= limit) {
    return { ok: false, usage: toSnapshot(tier, current, now) };
  }
  return { ok: true, usage: toSnapshot(tier, store.add(key, meter, 1), now) };
}

/** Gives a unit back when the request failed on our side. */
export function refundUsage(subject: string, tier: Tier, meter: Meter, now = Date.now()): UsageSnapshot {
  return toSnapshot(tier, store.add(`${dayKey(now)}:${subject}`, meter, -1), now);
}

/** For tests. */
export function resetUsage() {
  store.clear();
}
