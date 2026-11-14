import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DEFAULT_MODEL, getProvider, resetProviderCache, resolveEfforts, resolveModels } from "@/lib/ai";
import { resolveAnthropicKey } from "@/lib/ai/credentials";
import { GET as status } from "@/app/api/v1/status/route";

/**
 * Development traffic must never use the production key, and production must
 * keep working exactly as before. Fake keys only; nothing here calls the API.
 */
const PROD = "sk-ant-api03-PRODUCTION-not-a-real-key";
const DEV = "sk-ant-api03-DEVELOPMENT-not-a-real-key";
const VARS = ["ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY_DEV", "RR_ENVIRONMENT", "AI_PROVIDER", "AI_MODEL", "AI_EFFORT", "AI_ROUTING"];
const saved: Record<string, string | undefined> = {};

let warnings: string[] = [];
let infos: string[] = [];

beforeEach(() => {
  for (const name of VARS) {
    saved[name] = process.env[name];
    delete process.env[name];
  }
  resetProviderCache();
  warnings = [];
  infos = [];
  vi.spyOn(console, "warn").mockImplementation((...args) => void warnings.push(args.join(" ")));
  vi.spyOn(console, "info").mockImplementation((...args) => void infos.push(args.join(" ")));
});

afterEach(() => {
  for (const name of VARS) {
    if (saved[name] === undefined) delete process.env[name];
    else process.env[name] = saved[name];
  }
  resetProviderCache();
  vi.restoreAllMocks();
});

describe("resolveAnthropicKey", () => {
  it("uses only the production key in production, and ignores a development key there", () => {
    process.env.ANTHROPIC_API_KEY = PROD;
    process.env.ANTHROPIC_API_KEY_DEV = DEV;
    expect(resolveAnthropicKey("production")).toEqual({ ok: true, apiKey: PROD, source: "ANTHROPIC_API_KEY", environment: "production" });
  });

  it("does not let production fall back to the development key", () => {
    process.env.ANTHROPIC_API_KEY_DEV = DEV;
    expect(resolveAnthropicKey("production")).toMatchObject({ ok: false, problem: "missing" });
  });

  it("uses only the development key in development and staging", () => {
    process.env.ANTHROPIC_API_KEY = PROD;
    process.env.ANTHROPIC_API_KEY_DEV = DEV;
    for (const environment of ["development", "staging"] as const) {
      expect(resolveAnthropicKey(environment)).toEqual({ ok: true, apiKey: DEV, source: "ANTHROPIC_API_KEY_DEV", environment });
    }
  });

  it("refuses the production key outside production instead of falling back to it", () => {
    process.env.ANTHROPIC_API_KEY = PROD;
    const result = resolveAnthropicKey("development");
    expect(result).toMatchObject({ ok: false, problem: "production_key_outside_production" });
    expect(JSON.stringify(result)).not.toContain(PROD);
  });

  it("refuses a development key that is a copy of the production key", () => {
    process.env.ANTHROPIC_API_KEY = PROD;
    process.env.ANTHROPIC_API_KEY_DEV = PROD;
    const result = resolveAnthropicKey("development");
    expect(result).toMatchObject({ ok: false, problem: "same_key" });
    expect(JSON.stringify(result)).not.toContain(PROD);
  });
});

describe("getProvider", () => {
  it("runs a development server in labelled demo mode when only the production key is present, and says why", () => {
    process.env.ANTHROPIC_API_KEY = PROD;
    const provider = getProvider();
    expect(provider.mode).toBe("demo");
    expect(warnings.join("\n")).toMatch(/ANTHROPIC_API_KEY is the production key.*ANTHROPIC_API_KEY_DEV/);
    expect([...warnings, ...infos].join("\n")).not.toContain(PROD);
  });

  it("goes live in development with the development key, naming the variable but never the key", () => {
    process.env.ANTHROPIC_API_KEY_DEV = DEV;
    expect(getProvider().mode).toBe("live");
    expect(infos.join("\n")).toContain("Live AI in development using ANTHROPIC_API_KEY_DEV");
    expect([...warnings, ...infos].join("\n")).not.toContain(DEV);
  });

  it("uses the production key in production, with the routed models", () => {
    process.env.RR_ENVIRONMENT = "production";
    process.env.ANTHROPIC_API_KEY = PROD;
    const provider = getProvider();
    expect(provider.mode).toBe("live");
    expect(infos.join("\n")).toContain("using ANTHROPIC_API_KEY.");
    expect(infos.join("\n")).toContain("AI routes: read_text=claude-sonnet-5-5");
    expect(provider.modelFor("analyze")).toBe("claude-sonnet-5-5");
    expect(provider.modelFor("replies")).toBe("claude-sonnet-5-5");
    expect(provider.modelFor("refine")).toBe("claude-haiku-5-5");
    expect(provider.modelFor("coach")).toBe("claude-sonnet-5-5");
  });

  it("goes back to the pre-routing setup with AI_ROUTING=off: Opus 5.5 and the same efforts for every task", () => {
    process.env.RR_ENVIRONMENT = "production";
    process.env.ANTHROPIC_API_KEY = PROD;
    process.env.AI_ROUTING = "off";
    const provider = getProvider();
    expect(DEFAULT_MODEL).toBe("claude-opus-5-5");
    for (const task of ["analyze", "replies", "refine", "coach"] as const) {
      expect(provider.modelFor(task)).toBe("claude-opus-5-5");
    }
    expect(resolveModels()).toEqual({ analyze: "claude-opus-5-5", replies: "claude-opus-5-5", refine: "claude-opus-5-5", coach: "claude-opus-5-5" });
    expect(resolveEfforts()).toEqual({ analyze: "low", replies: "medium", refine: "low", coach: "medium" });
  });

  it("stays quietly in demo mode when no key is configured at all, as before", () => {
    expect(getProvider().mode).toBe("demo");
    expect(warnings).toEqual([]);
  });

  it("never puts either key in the status payload", async () => {
    process.env.ANTHROPIC_API_KEY = PROD;
    process.env.ANTHROPIC_API_KEY_DEV = DEV;
    const body = await (await status(new Request("http://test/api/v1/status"))).text();
    expect(body).not.toContain(PROD);
    expect(body).not.toContain(DEV);
  });
});
