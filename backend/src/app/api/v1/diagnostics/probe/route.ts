import { timingSafeEqual } from "node:crypto";
import { getProvider, ProviderError } from "@/lib/ai";
import { aiHealth } from "@/lib/ai/health";
import type { FailureReason } from "@/lib/domain/contracts";
import { serverEnvironment } from "@/lib/server/environment";
import { checkRateLimit, clientKey } from "@/lib/server/rate-limit";

export const maxDuration = 120;

/**
 * POST /api/v1/diagnostics/probe
 *
 * Makes one small real call to the AI provider and reports whether it worked.
 * It answers the question "is the server's key and model actually working?"
 * without anyone having to share a conversation.
 *
 * The call sends a fixed harmless sentence, never anything from a user, and
 * the response carries only a yes or no, a coarse reason and the latency.
 *
 * It costs a few tokens, so it is open only outside production. In staging and
 * production set DIAGNOSTICS_TOKEN and send it as `X-RR-Diagnostics`.
 */
function allowed(request: Request): boolean {
  const token = process.env.DIAGNOSTICS_TOKEN?.trim();
  if (token) {
    const given = Buffer.from(request.headers.get("x-rr-diagnostics") ?? "");
    const expected = Buffer.from(token);
    return given.length === expected.length && timingSafeEqual(given, expected);
  }
  return serverEnvironment() === "development";
}

export async function POST(request: Request) {
  const headers = { "Cache-Control": "no-store" };
  if (!allowed(request)) {
    return Response.json({ error: { code: "invalid_request", message: "Diagnostics are not open on this server." } }, { status: 403, headers });
  }
  const limit = checkRateLimit(clientKey(request));
  if (!limit.ok) {
    return Response.json(
      { error: { code: "rate_limited", message: "Give it a moment and try again." } },
      { status: 429, headers: { ...headers, "Retry-After": String(limit.retryAfterSeconds) } },
    );
  }

  const provider = getProvider();
  if (provider.mode !== "live") {
    return Response.json(
      { ok: false, mode: provider.mode, model: null, latencyMs: 0, reason: "not_configured", ai: aiHealth() },
      { headers },
    );
  }

  const started = Date.now();
  let ok = false;
  let reason: FailureReason | null = null;
  try {
    const result = await provider.refine({
      request: {
        text: "hey, how was your weekend?",
        action: "shorter",
        instruction: "",
        count: 1,
        conversation: "",
        locale: "en",
      },
      options: { includeSamples: false },
      call: { feature: "diagnostics_probe", route: "refine", client: "diagnostics", signal: request.signal },
    });
    ok = result.options.length > 0;
    if (!ok) reason = "output";
  } catch (error) {
    reason = error instanceof ProviderError ? error.reason : "unknown";
  }
  return Response.json(
    { ok, mode: provider.mode, model: provider.modelFor("refine"), latencyMs: Date.now() - started, reason, ai: aiHealth() },
    { headers },
  );
}
