import "server-only";
import type { Tier } from "@/lib/domain/contracts";
import { DEFAULT_FREE_INTENTS, INTENTS, isIntent, type Intent } from "@/lib/domain/intents";

/**
 * Plan definitions. These are product hypotheses, so every number is
 * configurable from the environment and delivered to clients through
 * GET /api/v1/status. The app never hardcodes limits or which intents are Pro.
 */
export interface Plan {
  dailyGenerations: number;
  dailyCoachMessages: number;
  intents: Intent[];
  /** Personalisation from the user's own sample messages. */
  voiceSamples: boolean;
}

function intEnv(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function freeIntents(): Intent[] {
  const raw = process.env.FREE_INTENTS?.trim();
  if (!raw) return DEFAULT_FREE_INTENTS;
  const parsed = raw
    .split(",")
    .map((item) => item.trim())
    .filter(isIntent);
  return parsed.length ? parsed : DEFAULT_FREE_INTENTS;
}

export function getPlans(): Record<Tier, Plan> {
  return {
    free: {
      dailyGenerations: intEnv("FREE_DAILY_GENERATIONS", 10),
      dailyCoachMessages: intEnv("FREE_DAILY_COACH_MESSAGES", 3),
      intents: freeIntents(),
      voiceSamples: false,
    },
    pro: {
      // "Unlimited" in the product sense; a high fair-use ceiling protects against abuse.
      dailyGenerations: intEnv("PRO_DAILY_GENERATIONS", 400),
      dailyCoachMessages: intEnv("PRO_DAILY_COACH_MESSAGES", 200),
      intents: [...INTENTS],
      voiceSamples: true,
    },
  };
}

export function usageLimitsEnabled(): boolean {
  return process.env.USAGE_LIMITS?.trim().toLowerCase() !== "off";
}
