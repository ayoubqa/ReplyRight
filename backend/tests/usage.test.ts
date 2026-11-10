import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { consumeUsage, refundUsage, resetUsage, usageSnapshot, usageSubject } from "@/lib/server/usage";

const DAY = Date.UTC(2026, 10, 10, 12);

beforeEach(() => {
  resetUsage();
  process.env.FREE_DAILY_GENERATIONS = "3";
  process.env.FREE_DAILY_COACH_MESSAGES = "1";
});
afterEach(() => {
  delete process.env.FREE_DAILY_GENERATIONS;
  delete process.env.FREE_DAILY_COACH_MESSAGES;
  delete process.env.USAGE_LIMITS;
});

describe("daily usage", () => {
  it("counts down and stops at the free limit", () => {
    for (let i = 1; i <= 3; i++) {
      const step = consumeUsage("install:a", "free", "generation", DAY);
      expect(step.ok).toBe(true);
      expect(step.usage.generations).toEqual({ used: i, limit: 3, remaining: 3 - i });
    }
    const blocked = consumeUsage("install:a", "free", "generation", DAY);
    expect(blocked.ok).toBe(false);
    expect(blocked.usage.generations.used).toBe(3);
  });

  it("keeps coach and generation counters separate", () => {
    expect(consumeUsage("install:a", "free", "coach", DAY).ok).toBe(true);
    expect(consumeUsage("install:a", "free", "coach", DAY).ok).toBe(false);
    expect(consumeUsage("install:a", "free", "generation", DAY).ok).toBe(true);
  });

  it("refunds a unit after a failed request", () => {
    consumeUsage("install:a", "free", "generation", DAY);
    expect(refundUsage("install:a", "free", "generation", DAY).generations.used).toBe(0);
    expect(refundUsage("install:a", "free", "generation", DAY).generations.used).toBe(0);
  });

  it("resets on the next UTC day and reports when", () => {
    for (let i = 0; i < 3; i++) consumeUsage("install:a", "free", "generation", DAY);
    const tomorrow = DAY + 24 * 60 * 60 * 1000;
    expect(usageSnapshot("install:a", "free", tomorrow).generations.used).toBe(0);
    expect(usageSnapshot("install:a", "free", DAY).resetsAt).toBe("2026-11-11T00:00:00.000Z");
  });

  it("separates subjects and gives Pro a higher ceiling", () => {
    for (let i = 0; i < 3; i++) consumeUsage("install:a", "free", "generation", DAY);
    expect(consumeUsage("install:b", "free", "generation", DAY).ok).toBe(true);
    expect(consumeUsage("install:a", "pro", "generation", DAY).ok).toBe(true);
  });

  it("can be switched off for local development", () => {
    process.env.USAGE_LIMITS = "off";
    for (let i = 0; i < 10; i++) expect(consumeUsage("install:a", "free", "generation", DAY).ok).toBe(true);
  });

  it("identifies callers by install id, falling back to IP", () => {
    const id = "3F2504E0-4F89-41D3-9A0C-0305E82C3301";
    const withInstall = new Request("http://x", { headers: { "x-rr-install": id, "x-forwarded-for": "1.2.3.4" } });
    expect(usageSubject(withInstall)).toBe(`install:${id.toLowerCase()}`);
    const spoofed = new Request("http://x", { headers: { "x-rr-install": "not-a-uuid", "x-forwarded-for": "1.2.3.4" } });
    expect(usageSubject(spoofed)).toBe("ip:1.2.3.4");
  });
});
