import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { POST as analyze } from "@/app/api/v1/analyze/route";
import { POST as coach } from "@/app/api/v1/coach/route";
import { POST as refine } from "@/app/api/v1/refine/route";
import { POST as replies } from "@/app/api/v1/replies/route";
import { resetProviderCache, setProviderForTests } from "@/lib/ai";
import { resetAiHealth } from "@/lib/ai/health";
import { ProviderError, type AiProvider, type CallContext } from "@/lib/ai/types";
import { resetEntitlementCache } from "@/lib/server/entitlements";
import { resetUsage } from "@/lib/server/usage";
import { asUint8, screenshot } from "./helpers/images";
import { xcodeTransaction } from "./helpers/storekit";

/**
 * The request pipeline around a live-looking provider: exact repeats share one
 * AI call, a caller that leaves stops it, and failures that may have cost
 * money tell the app not to repeat them on its own.
 */
const INSTALL_A = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const INSTALL_B = "9b2d6c1e-0a7f-4e5b-8c3d-2f1e0d9c8b7a";
let ip = 0;

type Gate = { release: () => void; promise: Promise<void> };
function gate(): Gate {
  let release = () => {};
  const promise = new Promise<void>((resolve) => (release = resolve));
  return { release, promise };
}

/** Records every call and its bookkeeping. Each call waits for `hold` when one is set. */
class StubProvider implements AiProvider {
  readonly id = "stub";
  readonly mode = "live" as const;
  readonly supportsImages = true;
  calls: CallContext[] = [];
  hold: Gate | null = null;
  failWith: ProviderError | null = null;
  /** What the stub says answered, the way the real provider reports it. */
  serves: string | null = null;
  modelFor() {
    return "claude-opus-5-5";
  }
  private async answer<T>(call: CallContext | undefined, value: T): Promise<T> {
    this.calls.push(call ?? {});
    if (call && this.serves) call.servedModel = this.serves;
    if (this.hold) {
      const hold = this.hold.promise;
      await new Promise<void>((resolve, reject) => {
        void hold.then(resolve);
        call?.signal?.addEventListener("abort", () => reject(new ProviderError("unavailable", "stopped", { reason: "cancelled" })), {
          once: true,
        });
      });
    }
    if (this.failWith) throw this.failWith;
    return value;
  }
  analyze({ call }: { call?: CallContext }) {
    return this.answer(call, {
      read: "They're keen.",
      transcript: [{ speaker: "them" as const, text: "free tonight?" }],
      latestMessage: "free tonight?",
      latestFromMe: false,
      canReply: true,
      problem: "none" as const,
      toneLabel: "Warm",
      observations: [],
      assumptions: [],
      opportunity: "Say yes.",
      suggestedIntents: ["natural" as const],
      headsUp: null,
    });
  }
  replies({ call }: { call?: CallContext }) {
    return this.answer(call, { note: "Here.", replies: [{ style: "Natural", text: `option ${this.calls.length}`, why: "Easy." }], headsUp: null });
  }
  refine({ call }: { call?: CallContext }) {
    return this.answer(call, { options: [{ style: "Shorter", text: "short", why: "Shorter." }], note: null });
  }
  coach({ call }: { call?: CallContext }) {
    return this.answer(call, { message: "ok", suggestions: [], followUps: [], lesson: null, review: null, practice: null, headsUp: null });
  }
}

let stub: StubProvider;

function post(path: string, body: unknown, options: { install?: string; client?: string; signal?: AbortSignal } = {}) {
  return new Request(`http://test${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-forwarded-for": `10.9.${Math.floor(++ip / 250)}.${ip % 250}`,
      "x-rr-install": options.install ?? INSTALL_A,
      "x-rr-client": options.client ?? "ios-app/1.0.0",
    },
    body: JSON.stringify(body),
    signal: options.signal,
  });
}

const tick = (ms = 5) => new Promise((resolve) => setTimeout(resolve, ms));

beforeEach(() => {
  stub = new StubProvider();
  setProviderForTests(stub);
  resetEntitlementCache();
  resetUsage();
  resetAiHealth();
  process.env.REQUEST_LOG = "off";
  process.env.RR_ABORT_GRACE_MS = "20";
});
afterEach(() => {
  resetProviderCache();
  delete process.env.RR_ABORT_GRACE_MS;
  delete process.env.RR_DEDUPE_REQUESTS;
});

describe("duplicate requests", () => {
  it("answers an exact repeat from the same install with the same AI call, and counts it once", async () => {
    stub.hold = gate();
    const body = { conversation: "Them: free tonight?", intent: "natural" };
    const first = replies(post("/api/v1/replies", body));
    await tick();
    const second = replies(post("/api/v1/replies", body));
    await tick();
    stub.hold.release();
    const [a, b] = await Promise.all([first, second]);
    expect(stub.calls).toHaveLength(1);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    const [bodyA, bodyB] = [await a.json(), await b.json()];
    expect(bodyB).toEqual(bodyA);
    expect(bodyA.usage.generations.used).toBe(1);
    // Each response still has its own request id.
    expect(a.headers.get("X-RR-Request")).not.toBe(b.headers.get("X-RR-Request"));

    // Once it has finished, the same request is a new request.
    stub.hold = null;
    const third = await (await replies(post("/api/v1/replies", body))).json();
    expect(stub.calls).toHaveLength(2);
    expect(third.usage.generations.used).toBe(2);
  });

  it("never shares between installs, or between different requests", async () => {
    stub.hold = gate();
    const body = { conversation: "Them: free tonight?", intent: "natural" };
    const pending = [
      replies(post("/api/v1/replies", body, { install: INSTALL_A })),
      replies(post("/api/v1/replies", body, { install: INSTALL_B })),
      replies(post("/api/v1/replies", { ...body, intent: "flirt" }, { install: INSTALL_A })),
    ];
    await tick();
    stub.hold.release();
    await Promise.all(pending);
    expect(stub.calls).toHaveLength(3);
  });

  it("can be switched off", async () => {
    process.env.RR_DEDUPE_REQUESTS = "off";
    stub.hold = gate();
    const body = { conversation: "Them: free tonight?", intent: "natural" };
    const pending = [replies(post("/api/v1/replies", body)), replies(post("/api/v1/replies", body))];
    await tick();
    stub.hold.release();
    await Promise.all(pending);
    expect(stub.calls).toHaveLength(2);
  });
});

describe("cancellation", () => {
  it("stops the AI call when the app goes away, after a short grace period", async () => {
    stub.hold = gate();
    const controller = new AbortController();
    const pending = replies(post("/api/v1/replies", { conversation: "Them: hi", intent: "natural" }, { signal: controller.signal }));
    await tick();
    const signal = stub.calls[0].signal!;
    controller.abort();
    await tick(2);
    expect(signal.aborted).toBe(false); // still inside the grace period
    await tick(40);
    expect(signal.aborted).toBe(true);
    const response = await pending;
    expect(response.status).toBe(503);
    expect(response.headers.get("X-RR-Retry")).toBe("no");
  });

  it("keeps going while another caller still waits for the same answer", async () => {
    stub.hold = gate();
    const controller = new AbortController();
    const body = { conversation: "Them: hi", intent: "natural" };
    const first = replies(post("/api/v1/replies", body, { signal: controller.signal }));
    await tick();
    const second = replies(post("/api/v1/replies", body));
    await tick();
    controller.abort();
    await tick(40);
    expect(stub.calls[0].signal!.aborted).toBe(false);
    stub.hold.release();
    expect((await second).status).toBe(200);
    expect((await first).status).toBe(200);
    expect(stub.calls).toHaveLength(1);
  });

  it("lets a repeat that arrives during the grace period pick up the running call", async () => {
    stub.hold = gate();
    const controller = new AbortController();
    const body = { conversation: "Them: hi", intent: "natural" };
    void replies(post("/api/v1/replies", body, { signal: controller.signal }));
    await tick();
    controller.abort();
    const again = replies(post("/api/v1/replies", body));
    await tick(40);
    expect(stub.calls[0].signal!.aborted).toBe(false);
    stub.hold.release();
    expect((await again).status).toBe(200);
    expect(stub.calls).toHaveLength(1);
  });
});

describe("retry hints for the app", () => {
  it.each([
    [new ProviderError("bad_output", "garbled", { reason: "output" }), 502, "no"],
    [new ProviderError("unavailable", "slow", { reason: "timeout" }), 503, "no"],
    [new ProviderError("unavailable", "limit", { reason: "budget" }), 503, "no"],
    [new ProviderError("unavailable", "key", { reason: "credentials" }), 503, "no"],
    [new ProviderError("misconfigured", "bug", { reason: "request" }), 500, "no"],
    [new ProviderError("unavailable", "busy", { reason: "overloaded" }), 503, null],
    [new ProviderError("unavailable", "offline", { reason: "network" }), 503, null],
  ])("%s -> %i with X-RR-Retry %s", async (error, status, hint) => {
    stub.failWith = error;
    const response = await refine(post("/api/v1/refine", { text: "hey, how was your weekend?", action: "shorter" }));
    expect(response.status).toBe(status);
    expect(response.headers.get("X-RR-Retry")).toBe(hint);
    // The user is never charged for a failure.
    stub.failWith = null;
    const ok = await (await refine(post("/api/v1/refine", { text: "hey, how was your weekend?", action: "funnier" }))).json();
    expect(ok.usage.generations.used).toBe(1);
  });

  it("explains a reached spend limit with its own reason", async () => {
    stub.failWith = new ProviderError("unavailable", "Development AI spending has reached its limit.", { reason: "budget" });
    const response = await replies(post("/api/v1/replies", { conversation: "Them: hi", intent: "natural" }));
    expect(response.status).toBe(503);
    const body = await response.json();
    expect(body.error).toMatchObject({ code: "ai_unavailable", reason: "budget" });
    expect(body.error.message).toMatch(/spending has reached its limit/);
  });
});

describe("model routing through the pipeline", () => {
  it("routes each request centrally and names the model that answered in the response", async () => {
    stub.serves = "claude-haiku-5-5";
    const simple = await (await replies(post("/api/v1/replies", { conversation: "Them: what are you up to", intent: "natural" }))).json();
    expect(stub.calls[0].route).toBe("reply_simple");
    expect(simple.model).toBe("claude-haiku-5-5");

    stub.serves = "claude-sonnet-5-5";
    const flirt = await (await replies(post("/api/v1/replies", { conversation: "Them: what are you up to", intent: "flirt" }))).json();
    expect(stub.calls[1].route).toBe("reply_standard");
    expect(flirt.model).toBe("claude-sonnet-5-5");
    // The envelope keeps its shape.
    expect(Object.keys(flirt).sort()).toEqual(["mode", "model", "provider", "result", "usage"]);
  });

  it("asks free users to upgrade for deep coaching, without calling the AI", async () => {
    const response = await coach(post("/api/v1/coach", { depth: "deep", messages: [{ role: "user", text: "they keep cancelling plans" }] }));
    expect(response.status).toBe(402);
    expect((await response.json()).error.code).toBe("upgrade_required");
    expect(stub.calls).toHaveLength(0);
  });

  it("sends deep coaching from Pro to the advanced route, and ordinary coaching to Sonnet's routes", async () => {
    process.env.ENTITLEMENT_TRUST_XCODE = "true";
    resetEntitlementCache();
    const token = xcodeTransaction({ bundleId: "com.replyright.app", productId: "com.replyright.pro.annual", expiresDate: Date.now() + 3_600_000 });
    const pro = (body: unknown) =>
      new Request("http://test/api/v1/coach", {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": "10.7.0.1", "x-rr-install": INSTALL_A, "x-rr-entitlement": token },
        body: JSON.stringify(body),
      });
    expect((await coach(pro({ depth: "deep", messages: [{ role: "user", text: "they keep cancelling plans" }] }))).status).toBe(200);
    expect((await coach(pro({ messages: [{ role: "user", text: "they keep cancelling plans" }] }))).status).toBe(200);
    expect(stub.calls.map((c) => [c.feature, c.route])).toEqual([
      ["coach_ask_deep", "coach_advanced"],
      ["coach_ask", "coach_ask"],
    ]);
    delete process.env.ENTITLEMENT_TRUST_XCODE;
  });
});

describe("feature labels for the usage ledger", () => {
  it("names what each request is for, and which client asked", async () => {
    await analyze(post("/api/v1/analyze", { conversation: "Them: free tonight?\nMe: maybe" }));
    const form = new FormData();
    form.set("payload", JSON.stringify({}));
    form.append("images", new File([asUint8(await screenshot("png"))], "s.png", { type: "image/png" }));
    await analyze(
      new Request("http://test/api/v1/analyze", {
        method: "POST",
        headers: { "x-forwarded-for": "10.8.0.1", "x-rr-install": INSTALL_A, "x-rr-client": "ios-share/1.0.0" },
        body: form,
      }),
    );
    await replies(post("/api/v1/replies", { conversation: "Them: hi", intent: "natural" }));
    await replies(post("/api/v1/replies", { conversation: "Them: hi", intent: "natural", avoid: ["hey"] }));
    await replies(post("/api/v1/replies", { kind: "starter", intent: "natural" }));
    await refine(post("/api/v1/refine", { text: "hey there you", action: "shorter" }, { client: "ios-keyboard/1.0.0" }));
    await coach(post("/api/v1/coach", { mode: "review", draft: "hey you", messages: [] }));

    expect(stub.calls.map((c) => [c.feature, c.route])).toEqual([
      ["read_text", "read_text"],
      ["read_screenshot", "read_screenshot"],
      ["replies", "reply_simple"],
      ["regenerate", "reply_simple"],
      ["starter", "starter"],
      ["refine", "refine"],
      ["coach_review", "coach_review"],
    ]);
    expect(stub.calls.map((c) => [c.feature, c.client])).toEqual([
      ["read_text", "app"],
      ["read_screenshot", "share"],
      ["replies", "app"],
      ["regenerate", "app"],
      ["starter", "app"],
      ["refine", "keyboard"],
      ["coach_review", "app"],
    ]);
    for (const call of stub.calls) expect(call.requestId).toMatch(/^[0-9a-f-]{36}$/);
  });
});
