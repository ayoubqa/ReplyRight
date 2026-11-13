import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { POST as analyze } from "@/app/api/v1/analyze/route";
import { POST as coach } from "@/app/api/v1/coach/route";
import { POST as refine } from "@/app/api/v1/refine/route";
import { POST as replies } from "@/app/api/v1/replies/route";
import { POST as probe } from "@/app/api/v1/diagnostics/probe/route";
import { GET as status } from "@/app/api/v1/status/route";
import { resetProviderCache, setProviderForTests } from "@/lib/ai";
import { ProviderError, type AiProvider, type TransientImage } from "@/lib/ai/types";
import { aiHealth, recordAiFailure, recordAiSuccess, resetAiHealth } from "@/lib/ai/health";
import { resetEntitlementCache } from "@/lib/server/entitlements";
import { resetUsage } from "@/lib/server/usage";
import { asUint8, garbledJpeg, OLD_VERIFY_FIXTURE, screenshot } from "./helpers/images";
import { xcodeTransaction } from "./helpers/storekit";

/** Route handlers exercised directly, with the demo provider (no network, no key). */
let ip = 0;
const INSTALL = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";

function headers(extra: Record<string, string> = {}) {
  // A fresh IP per request keeps the per-minute limiter out of the way.
  return { "x-forwarded-for": `10.0.${Math.floor(++ip / 250)}.${ip % 250}`, "x-rr-install": INSTALL, ...extra };
}
function json(path: string, body: unknown, extra: Record<string, string> = {}) {
  return new Request(`http://test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers(extra) },
    body: JSON.stringify(body),
  });
}
function multipart(path: string, payload: unknown, files: { name: string; bytes: Uint8Array<ArrayBuffer>; type: string }[]) {
  const form = new FormData();
  form.set("payload", JSON.stringify(payload));
  for (const file of files) form.append("images", new File([file.bytes], file.name, { type: file.type }));
  return new Request(`http://test${path}`, { method: "POST", headers: headers(), body: form });
}
// Smallest valid PNG (1x1). Fine where a request is refused before images are read.
const PNG = Uint8Array.from(
  Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64"),
);

beforeEach(() => {
  process.env.AI_PROVIDER = "demo";
  process.env.DEMO_DELAY_MS = "0";
  resetProviderCache();
  resetEntitlementCache();
  resetUsage();
  resetAiHealth();
  process.env.REQUEST_LOG = "off";
});
afterEach(() => {
  for (const key of [
    "FREE_DAILY_GENERATIONS",
    "FREE_DAILY_COACH_MESSAGES",
    "ENTITLEMENT_TRUST_XCODE",
    "APPLE_BUNDLE_ID",
    "RR_ENVIRONMENT",
    "DIAGNOSTICS_TOKEN",
  ]) {
    delete process.env[key];
  }
});

describe("POST /api/v1/replies", () => {
  it("returns three clearly labelled demo replies with usage", async () => {
    const res = await replies(json("/api/v1/replies", { conversation: "Them: free this weekend?", intent: "flirt" }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mode).toBe("demo");
    expect(body.model).toBeNull();
    expect(body.result.replies).toHaveLength(3);
    expect(body.result.note).toMatch(/demo mode/i);
    expect(body.result.replies.every((r: { why: string }) => r.why.startsWith("Sample:"))).toBe(true);
    expect(body.usage).toMatchObject({ tier: "free", generations: { used: 1 } });
    expect(res.headers.get("cache-control")).toBe("no-store");
  });

  it("avoids options the user has already seen", async () => {
    const first = await (await replies(json("/api/v1/replies", { conversation: "Them: hey", intent: "laugh" }))).json();
    const seen = first.result.replies.map((r: { text: string }) => r.text);
    const second = await (
      await replies(json("/api/v1/replies", { conversation: "Them: hey", intent: "laugh", avoid: seen }))
    ).json();
    for (const reply of second.result.replies) expect(seen).not.toContain(reply.text);
  });

  it("needs a conversation for replies but not for starters", async () => {
    const empty = await replies(json("/api/v1/replies", { intent: "natural" }));
    expect(empty.status).toBe(400);
    expect((await empty.json()).error.code).toBe("invalid_request");
    const starter = await replies(json("/api/v1/replies", { kind: "starter", situation: "We matched yesterday" }));
    expect(starter.status).toBe(200);
  });

  it("accepts a structured transcript from /analyze", async () => {
    const res = await replies(
      json("/api/v1/replies", { transcript: [{ speaker: "them", text: "so what do you do for fun" }], intent: "interest" }),
    );
    expect(res.status).toBe(200);
  });

  it("rejects unknown intents, oversized input and non-JSON bodies", async () => {
    expect((await replies(json("/api/v1/replies", { conversation: "hi there", intent: "negging" }))).status).toBe(400);
    expect((await replies(json("/api/v1/replies", { conversation: "x".repeat(6001) }))).status).toBe(400);
    const text = new Request("http://test/api/v1/replies", { method: "POST", headers: headers(), body: "hello" });
    expect((await replies(text)).status).toBe(415);
    const broken = new Request("http://test/api/v1/replies", {
      method: "POST",
      headers: { "content-type": "application/json", ...headers() },
      body: "{oops",
    });
    expect((await replies(broken)).status).toBe(400);
  });

  it("asks free users to upgrade for Pro intents, without spending a generation", async () => {
    const res = await replies(json("/api/v1/replies", { conversation: "Them: hey", intent: "ask_out" }));
    expect(res.status).toBe(402);
    const body = await res.json();
    expect(body.error.code).toBe("upgrade_required");
    expect(body.error.usage.generations.used).toBe(0);
  });

  it("unlocks Pro intents only for a verified entitlement", async () => {
    const token = xcodeTransaction({
      bundleId: "com.replyright.app",
      productId: "com.replyright.pro.annual",
      expiresDate: Date.now() + 3_600_000,
    });
    const request = () => json("/api/v1/replies", { conversation: "Them: hey", intent: "ask_out" }, { "x-rr-entitlement": token });

    // Local Xcode test tokens are refused unless the server opts in.
    expect((await replies(request())).status).toBe(402);

    process.env.ENTITLEMENT_TRUST_XCODE = "true";
    resetEntitlementCache();
    const res = await replies(request());
    expect(res.status).toBe(200);
    expect((await res.json()).usage.tier).toBe("pro");

    // A made-up token never grants Pro.
    const fake = json("/api/v1/replies", { conversation: "Them: hey", intent: "ask_out" }, { "x-rr-entitlement": "a.b.c" });
    expect((await replies(fake)).status).toBe(402);
  });

  it("stops at the daily free limit and says when it resets", async () => {
    process.env.FREE_DAILY_GENERATIONS = "2";
    const call = () => replies(json("/api/v1/replies", { conversation: "Them: hey", intent: "natural" }));
    expect((await call()).status).toBe(200);
    expect((await call()).status).toBe(200);
    const blocked = await call();
    expect(blocked.status).toBe(402);
    const body = await blocked.json();
    expect(body.error.code).toBe("limit_reached");
    expect(body.error.usage.generations).toEqual({ used: 2, limit: 2, remaining: 0 });
    expect(typeof body.error.usage.resetsAt).toBe("string");
  });
});

describe("POST /api/v1/analyze", () => {
  it("parses labelled text without claiming to have analysed it", async () => {
    const res = await analyze(json("/api/v1/analyze", { conversation: "Them: beach or mountains?\nMe: mountains\nThem: ok bold" }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.result.transcript).toHaveLength(3);
    expect(body.result.transcript[1]).toEqual({ speaker: "me", text: "mountains" });
    expect(body.result.latestMessage).toBe("ok bold");
    expect(body.result.read).toMatch(/demo mode/i);
    expect(body.usage.generations.used).toBe(0);
  });

  it("accepts screenshots as multipart and validates them by content", async () => {
    const shot = asUint8(await screenshot("png"));
    const ok = await analyze(multipart("/api/v1/analyze", {}, [{ name: "chat.png", bytes: shot, type: "image/png" }]));
    expect(ok.status).toBe(200);

    const fake = await analyze(
      multipart("/api/v1/analyze", {}, [{ name: "chat.png", bytes: new TextEncoder().encode("not an image at all"), type: "image/png" }]),
    );
    expect(fake.status).toBe(400);
    expect((await fake.json()).error.code).toBe("unsupported_media");

    const many = Array.from({ length: 5 }, (_, i) => ({ name: `${i}.png`, bytes: shot, type: "image/png" }));
    expect((await analyze(multipart("/api/v1/analyze", {}, many))).status).toBe(400);
  });

  it("needs something to read", async () => {
    expect((await analyze(json("/api/v1/analyze", {}))).status).toBe(400);
  });
});

describe("POST /api/v1/refine", () => {
  it("returns exactly the number of options requested", async () => {
    const one = await (await refine(json("/api/v1/refine", { text: "hey how are you", action: "shorter" }))).json();
    expect(one.result.options).toHaveLength(1);
    const three = await (await refine(json("/api/v1/refine", { text: "hey how are you", action: "flirty", count: 3 }))).json();
    expect(three.result.options).toHaveLength(3);
    expect(three.result.note).toMatch(/demo mode/i);
  });

  it("rejects empty text, unknown actions and screenshots", async () => {
    expect((await refine(json("/api/v1/refine", { text: "  ", action: "shorter" }))).status).toBe(400);
    expect((await refine(json("/api/v1/refine", { text: "hi", action: "meaner" }))).status).toBe(400);
    const withImage = multipart("/api/v1/refine", { text: "hi", action: "shorter" }, [{ name: "a.png", bytes: PNG, type: "image/png" }]);
    expect((await refine(withImage)).status).toBe(400);
  });
});

describe("POST /api/v1/coach", () => {
  it("answers a question and meters coaching separately", async () => {
    process.env.FREE_DAILY_COACH_MESSAGES = "1";
    const ask = () => coach(json("/api/v1/coach", { messages: [{ role: "user", text: "Does this sound too eager?" }] }));
    const res = await ask();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.result.message).toMatch(/demo mode/i);
    expect(body.usage.coach.used).toBe(1);
    expect(body.usage.generations.used).toBe(0);
    expect((await (await ask()).json()).error.code).toBe("limit_reached");
  });

  it("requires the last message to be the user's", async () => {
    const res = await coach(
      json("/api/v1/coach", { messages: [{ role: "user", text: "hi" }, { role: "coach", text: "hello" }] }),
    );
    expect(res.status).toBe(400);
    expect((await coach(json("/api/v1/coach", { messages: [] }))).status).toBe(400);
  });

  it("reviews a message the user wrote, with every part of the feedback", async () => {
    const res = await coach(json("/api/v1/coach", { mode: "review", draft: "hey!! miss you already", goal: "warm, not clingy" }));
    expect(res.status).toBe(200);
    const { result } = await res.json();
    expect(result.message).toMatch(/demo mode/i);
    expect(Object.keys(result.review).sort()).toEqual(
      ["alternative", "checks", "comesAcross", "improvements", "intent", "lesson", "whyItWorks"].sort(),
    );
    expect(result.review.checks.map((c: { aspect: string }) => c.aspect)).toEqual([
      "natural",
      "intensity",
      "formality",
      "feeling",
      "clarity",
    ]);
    expect(result.practice).toBeNull();

    const empty = await coach(json("/api/v1/coach", { mode: "review" }));
    expect(empty.status).toBe(400);
    expect((await empty.json()).error.message).toMatch(/message you want feedback on/i);
  });

  it("runs a practice conversation turn by turn", async () => {
    const scenario = { id: "keep_it_going" };
    const opening = await coach(json("/api/v1/coach", { mode: "practice", scenario }));
    expect(opening.status).toBe(200);
    const first = (await opening.json()).result;
    expect(first.message).toMatch(/demo mode/i);
    expect(first.practice.feedback).toBeNull();
    expect(typeof first.practice.partnerReply).toBe("string");

    const next = await coach(
      json("/api/v1/coach", {
        mode: "practice",
        scenario,
        messages: [
          { role: "coach", text: first.practice.partnerReply },
          { role: "user", text: "pretty good! finally tried that ramen place" },
        ],
      }),
    );
    expect(next.status).toBe(200);
    expect((await next.json()).result.practice.feedback).toMatch(/^Sample:/);

    expect((await coach(json("/api/v1/coach", { mode: "practice" }))).status).toBe(400);
    expect((await coach(json("/api/v1/coach", { mode: "practice", scenario: { id: "custom" } }))).status).toBe(400);
    const waiting = await coach(
      json("/api/v1/coach", { mode: "practice", scenario, messages: [{ role: "coach", text: "hey" }] }),
    );
    expect(waiting.status).toBe(400);
  });
});

describe("GET /api/v1/status", () => {
  it("reports mode, plans and usage without secrets", async () => {
    const res = await status(new Request("http://test/api/v1/status", { headers: headers() }));
    const body = await res.json();
    expect(body).toMatchObject({ apiVersion: 2, mode: "demo", provider: "demo", environment: "development" });
    expect(body.ai).toEqual({ state: "untested", lastSuccessAt: null, lastFailureAt: null, lastFailureReason: null, models: null });
    expect(body.plans.free.intents).toContain("boundary");
    expect(body.plans.free.intents).not.toContain("ask_out");
    expect(body.plans.pro.intents).toHaveLength(12);
    expect(body.usage.tier).toBe("free");
    expect(body.refineActions).toEqual(expect.arrayContaining(["more_direct", "ask_question", "keep_going"]));
    expect(body.coach.modes).toEqual(["ask", "review", "practice"]);
    expect(JSON.stringify(body)).not.toMatch(/sk-ant|api[_-]?key/i);
  });

  it("names the deployment and reflects recent AI health", async () => {
    process.env.RR_ENVIRONMENT = "staging";
    recordAiSuccess();
    recordAiFailure("credentials");
    // A refusal or a garbled answer says nothing about whether the service is up.
    recordAiFailure("refusal");
    const body = await (await status(new Request("http://test/api/v1/status", { headers: headers() }))).json();
    expect(body.environment).toBe("staging");
    expect(body.ai.state).toBe("failing");
    expect(body.ai.lastFailureReason).toBe("credentials");
    expect(aiHealth().lastSuccessAt).not.toBeNull();
  });
});

describe("request pipeline", () => {
  it("tags every answer with a request id and never caches it", async () => {
    const ok = await refine(json("/api/v1/refine", { text: "hello there", action: "shorter" }));
    const bad = await refine(json("/api/v1/refine", { text: "", action: "shorter" }));
    for (const res of [ok, bad]) {
      expect(res.headers.get("x-rr-request")).toMatch(/^[0-9a-f-]{36}$/);
      expect(res.headers.get("cache-control")).toBe("no-store");
    }
    expect(ok.headers.get("x-rr-request")).not.toBe(bad.headers.get("x-rr-request"));
  });

  it("accepts the three newer rewrite actions", async () => {
    for (const action of ["more_direct", "ask_question", "keep_going"]) {
      const res = await refine(json("/api/v1/refine", { text: "want to get coffee sometime maybe", action }));
      expect(res.status).toBe(200);
    }
  });
});

describe("POST /api/v1/diagnostics/probe", () => {
  const call = (extra: Record<string, string> = {}) =>
    probe(new Request("http://test/api/v1/diagnostics/probe", { method: "POST", headers: headers(extra) }));

  it("says plainly when there is no AI to probe", async () => {
    const res = await call();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: false, mode: "demo", reason: "not_configured" });
  });

  it("is closed outside development unless the caller has the token", async () => {
    process.env.RR_ENVIRONMENT = "production";
    expect((await call()).status).toBe(403);
    process.env.DIAGNOSTICS_TOKEN = "let-me-in";
    expect((await call({ "x-rr-diagnostics": "wrong" })).status).toBe(403);
    expect((await call({ "x-rr-diagnostics": "let-me-in" })).status).toBe(200);
  });
});

describe("rate limiting", () => {
  it("returns 429 with Retry-After when one client hammers the API", async () => {
    // Invalid bodies are rejected after the limiter runs, so this stays fast.
    const hit = () =>
      analyze(
        new Request("http://test/api/v1/analyze", {
          method: "POST",
          headers: { "content-type": "application/json", "x-forwarded-for": "203.0.113.9" },
          body: "{}",
        }),
      );
    for (let i = 0; i < 30; i++) expect((await hit()).status).toBe(400);
    const blocked = await hit();
    expect(blocked.status).toBe(429);
    expect((await blocked.json()).error.code).toBe("rate_limited");
    expect(Number(blocked.headers.get("retry-after"))).toBeGreaterThan(0);
  });
});

// ------------------------------------------------------------------ screenshots with a live provider

/**
 * A stand-in for the live provider, so the route, the image pipeline and the
 * error mapping run exactly as in production without calling the network.
 */
function liveProvider(analyze: AiProvider["analyze"]): AiProvider & { seen: TransientImage[][] } {
  const seen: TransientImage[][] = [];
  return {
    id: "anthropic",
    mode: "live",
    supportsImages: true,
    seen,
    modelFor: () => "claude-opus-5-5",
    analyze: async (input) => {
      seen.push(input.images);
      return analyze(input);
    },
    replies: async ({ images }) => {
      seen.push(images);
      return { note: "ok", replies: [{ style: "Natural", text: "yes!", why: "Easy." }], headsUp: null };
    },
    refine: async () => ({ options: [], note: null }),
    coach: async () => ({ message: "ok", suggestions: [], followUps: [], lesson: null, review: null, practice: null, headsUp: null }),
  };
}

const readable = async () => ({
  canReply: true,
  transcript: [{ speaker: "them" as const, text: "are we still on for friday?" }],
  latestMessage: "are we still on for friday?",
  latestFromMe: false,
  read: "They're checking in about Friday.",
  toneLabel: "Friendly",
  observations: [],
  assumptions: [],
  opportunity: "",
  suggestedIntents: ["natural" as const],
  headsUp: null,
  problem: "none" as const,
});

describe("screenshots end to end", () => {
  const upload = (path: string, payload: unknown, files: Uint8Array<ArrayBuffer>[]) =>
    multipart(path, payload, files.map((bytes, i) => ({ name: `shot-${i + 1}.jpg`, bytes, type: "image/jpeg" })));

  it("passes several valid screenshots to the provider as decoded images, in order", async () => {
    const provider = liveProvider(readable);
    setProviderForTests(provider);
    const first = asUint8(await screenshot("jpeg", { width: 700, height: 1300 }));
    const second = asUint8(await screenshot("png", { width: 900, height: 1300 }));
    const res = await analyze(upload("/api/v1/analyze", { conversation: "" }, [first, second]));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mode).toBe("live");
    expect(body.result.problem).toBe("none");
    expect(provider.seen[0].map((image) => [image.mediaType, image.width])).toEqual([
      ["image/jpeg", 700],
      ["image/png", 900],
    ]);
  });

  it("refuses a damaged screenshot before it reaches the provider, and says how to fix it", async () => {
    const provider = liveProvider(readable);
    setProviderForTests(provider);
    for (const bytes of [asUint8(await garbledJpeg()), asUint8(OLD_VERIFY_FIXTURE)]) {
      const res = await analyze(upload("/api/v1/analyze", {}, [bytes]));
      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error.code).toBe("unsupported_media");
      expect(body.error.message).toMatch(/screenshot/i);
    }
    expect(provider.seen).toHaveLength(0);
  });

  it("does not spend a reply on a screenshot that cannot be read", async () => {
    setProviderForTests(liveProvider(readable));
    const res = await replies(upload("/api/v1/replies", { intent: "natural" }, [asUint8(await garbledJpeg())]));
    expect(res.status).toBe(400);
    const usage = await (await status(new Request("http://test/api/v1/status", { headers: headers() }))).json();
    expect(usage.usage.generations.used).toBe(0);
  });

  it("reports an image the provider refuses as a problem with the screenshot, not with the AI", async () => {
    setProviderForTests(
      liveProvider(async () => {
        throw new ProviderError("rejected_input", "I couldn't read one of those screenshots. Try taking it again, or paste the text instead.", {
          reason: "image",
        });
      }),
    );
    const res = await analyze(upload("/api/v1/analyze", {}, [asUint8(await screenshot("jpeg"))]));
    expect(res.status).toBe(422);
    const body = await res.json();
    expect(body.error).toMatchObject({ code: "unsupported_media", reason: "image" });
    expect(body.error.message).toMatch(/paste the text/i);
  });

  it("reports a request the provider refuses as our problem", async () => {
    setProviderForTests(
      liveProvider(async () => {
        throw new ProviderError("misconfigured", "Something went wrong on our side. Please try again.", { reason: "request" });
      }),
    );
    const res = await analyze(upload("/api/v1/analyze", {}, [asUint8(await screenshot("jpeg"))]));
    expect(res.status).toBe(500);
    expect((await res.json()).error).toMatchObject({ code: "internal", reason: "request" });
  });

  it("returns an unreadable screenshot as an analysis the app can explain", async () => {
    setProviderForTests(
      liveProvider(async () => ({
        ...(await readable()),
        canReply: false,
        transcript: [],
        latestMessage: null,
        read: "I can't make out the messages: the screenshot is too blurry. A sharper one, or pasting the text, will work.",
        problem: "unreadable",
      })),
    );
    const res = await analyze(upload("/api/v1/analyze", {}, [asUint8(await screenshot("jpeg"))]));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.result).toMatchObject({ canReply: false, problem: "unreadable", transcript: [] });
  });
});
