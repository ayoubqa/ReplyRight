/**
 * A stand-in for the Anthropic HTTP API, used as the SDK's `fetch`. The real
 * SDK runs on top of it (request building, error classes, middleware), so the
 * provider's retry, cancellation and usage tracking are exercised end to end
 * without a key and without spending anything.
 */
export type Step =
  | { kind: "message"; text: string; usage?: Record<string, unknown>; stop?: string; model?: string }
  | { kind: "error"; status: number; type?: string; headers?: Record<string, string> }
  /** Never answers; ends only when the SDK aborts the request (its timeout or the caller's signal). */
  | { kind: "hang" };

export function message(result: unknown, usage: Record<string, unknown> = { input_tokens: 1000, output_tokens: 200 }): Step {
  return { kind: "message", text: JSON.stringify(result), usage };
}

export function fakeAnthropic(steps: Step[]) {
  const queue = [...steps];
  const bodies: string[] = [];
  const fetch = async (_input: unknown, init?: RequestInit): Promise<Response> => {
    bodies.push(typeof init?.body === "string" ? init.body : "");
    const step = queue.shift();
    if (!step) throw new Error("fakeAnthropic: no more steps");
    if (step.kind === "hang") {
      return new Promise<Response>((_, reject) => {
        const signal = init?.signal;
        const abort = () => reject(new DOMException("The operation was aborted.", "AbortError"));
        if (signal?.aborted) abort();
        else signal?.addEventListener("abort", abort, { once: true });
      });
    }
    if (step.kind === "error") {
      return new Response(
        JSON.stringify({ type: "error", error: { type: step.type ?? "api_error", message: `status ${step.status}` } }),
        { status: step.status, headers: { "content-type": "application/json", ...step.headers } },
      );
    }
    const body = {
      id: "msg_test",
      type: "message",
      role: "assistant",
      model: step.model ?? "claude-opus-5-5",
      content: [{ type: "text", text: step.text }],
      stop_reason: step.stop ?? "end_turn",
      stop_sequence: null,
      usage: step.usage ?? { input_tokens: 1000, output_tokens: 200 },
    };
    return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
  };
  return { fetch: fetch as typeof globalThis.fetch, bodies, remaining: () => queue.length };
}
