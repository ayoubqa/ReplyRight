#!/usr/bin/env node
/**
 * ReplyRight end-to-end check.
 *
 * Replays the requests the iOS app sends, in the exact shapes the app uses
 * (including the multipart screenshot upload), against a running backend, and
 * checks that every answer has the fields the app needs to decode it.
 *
 *   node scripts/verify.mjs                       # http://localhost:3000
 *   node scripts/verify.mjs https://staging.example.com
 *   node scripts/verify.mjs --probe               # also make one real AI call through the probe route
 *   node scripts/verify.mjs --require-live        # fail unless the server answers with live AI
 *
 * It prints status codes, timings and field names. It never prints an API
 * key, and the only "conversation" it sends is the fixed sample below.
 */
import { randomUUID } from "node:crypto";

const args = process.argv.slice(2);
const flags = new Set(args.filter((a) => a.startsWith("--")));
const base = (args.find((a) => !a.startsWith("--")) ?? process.env.RR_BASE_URL ?? "http://localhost:3000").replace(/\/+$/, "");
const diagnosticsToken = process.env.DIAGNOSTICS_TOKEN ?? "";

const headers = {
  Accept: "application/json",
  "X-RR-Client": "verify-script/1.0",
  // A fresh install id per run, so the check never eats into a real install's daily allowance.
  "X-RR-Install": randomUUID(),
};

const SAMPLE = "Them: ok be honest, pineapple on pizza?\nMe: depends who's asking\nThem: someone deciding whether we can be friends";

// A 16x16 grey JPEG. Enough to exercise the upload path; it is not a conversation.
const JPEG = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAAQABABAREA/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAA/AKpgA//Z",
  "base64",
);

const results = [];
let mode = "unknown";

function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(34)} ${detail}`);
}

/** Mirrors what the Swift decoders require. Returns the names of missing or mistyped fields. */
function missing(object, spec) {
  const problems = [];
  for (const [key, type] of Object.entries(spec)) {
    const value = object?.[key];
    const ok =
      type === "array" ? Array.isArray(value) : type === "object" ? value !== null && typeof value === "object" : typeof value === type;
    if (!ok) problems.push(key);
  }
  return problems;
}

const USAGE = { tier: "string", generations: "object", coach: "object", resetsAt: "string" };
const ENVELOPE = { mode: "string", provider: "string", usage: "object", result: "object" };
const SUGGESTION = { style: "string", text: "string", why: "string" };

async function call(name, path, init, check) {
  const started = Date.now();
  let response;
  try {
    response = await fetch(`${base}${path}`, { ...init, headers: { ...headers, ...init?.headers }, signal: AbortSignal.timeout(120_000) });
  } catch (error) {
    const cause = error?.cause?.code ?? error?.name ?? "error";
    record(name, false, `no answer from ${base} (${cause})`);
    return null;
  }
  const ms = Date.now() - started;
  let body = null;
  try {
    body = await response.json();
  } catch {
    record(name, false, `HTTP ${response.status} in ${ms} ms, body was not JSON`);
    return null;
  }
  const problem = check(response, body);
  const failure = body?.error ? ` code=${body.error.code}${body.error.reason ? ` reason=${body.error.reason}` : ""}` : "";
  const request = response.headers.get("x-rr-request");
  record(name, !problem, `HTTP ${response.status} in ${ms} ms${failure}${problem ? ` :: ${problem}` : ""}${!problem || !request ? "" : ` (request ${request})`}`);
  return problem ? null : body;
}

function envelope(resultSpec, extra) {
  return (response, body) => {
    if (response.status !== 200) return body?.error?.message ?? "unexpected status";
    const gaps = [...missing(body, ENVELOPE), ...missing(body.usage, USAGE).map((k) => `usage.${k}`), ...missing(body.result, resultSpec).map((k) => `result.${k}`)];
    if (gaps.length) return `missing ${gaps.join(", ")}`;
    return extra?.(body.result) ?? null;
  };
}

function json(payload) {
  return { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) };
}

/** Builds the multipart body byte for byte the way the app's MultipartBody does. */
function multipart(payload, images) {
  const boundary = `rr-boundary-${randomUUID().toUpperCase()}`;
  const parts = [Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="payload"\r\n\r\n`), Buffer.from(JSON.stringify(payload)), Buffer.from("\r\n")];
  images.forEach((image, index) => {
    parts.push(
      Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="images"; filename="screenshot-${index + 1}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`),
      image,
      Buffer.from("\r\n"),
    );
  });
  parts.push(Buffer.from(`--${boundary}--\r\n`));
  return { method: "POST", headers: { "Content-Type": `multipart/form-data; boundary=${boundary}` }, body: Buffer.concat(parts) };
}

const suggestions = (list, count) => {
  if (!Array.isArray(list)) return "options missing";
  if (count !== null && list.length !== count) return `expected ${count} options, got ${list.length}`;
  const gaps = list.flatMap((item) => missing(item, SUGGESTION));
  return gaps.length ? `option missing ${[...new Set(gaps)].join(", ")}` : null;
};

console.log(`ReplyRight check against ${base}\n`);

const status = await call("status", "/api/v1/status", { method: "GET" }, (response, body) => {
  if (response.status !== 200) return "unexpected status";
  const gaps = [...missing(body, { apiVersion: "number", mode: "string", provider: "string", supportsImages: "boolean", plans: "object", usage: "object" }), ...missing(body.usage, USAGE).map((k) => `usage.${k}`)];
  return gaps.length ? `missing ${gaps.join(", ")}` : null;
});

if (!status) {
  console.log(`\nThe server did not answer at ${base}.`);
  console.log("Start it with `npm run dev` in backend/, or pass the address of a deployed server.");
  process.exit(1);
}

mode = status.mode;
const person = { alias: "Sam", stage: "talking", notes: "", metAt: "climbing gym", language: "", interests: ["climbing", "ramen"], background: "", preferences: "", details: "", history: "" };

const analysis = await call("analyze (pasted text)", "/api/v1/analyze", json({ conversation: SAMPLE, locale: "en" }), envelope({ canReply: "boolean", read: "string" }));

await call(
  "analyze (screenshot upload)",
  "/api/v1/analyze",
  multipart({ conversation: "", locale: "en" }, [JPEG]),
  envelope({ canReply: "boolean", read: "string" }),
);

const transcript = (analysis?.result?.transcript ?? []).filter((line) => line.text);
await call(
  "replies",
  "/api/v1/replies",
  json({ kind: "reply", conversation: SAMPLE, transcript, situation: "", intent: "laugh", instruction: "", draft: "", avoid: [], crush: person, locale: "en" }),
  envelope({ note: "string", replies: "array" }, (result) => suggestions(result.replies, 3)),
);

await call(
  "replies (conversation starter)",
  "/api/v1/replies",
  json({ kind: "starter", conversation: "", transcript: [], situation: "We matched yesterday. Their profile mentions climbing.", intent: "natural", instruction: "", draft: "", avoid: [], locale: "en" }),
  envelope({ note: "string", replies: "array" }, (result) => suggestions(result.replies, 3)),
);

for (const action of ["more_natural", "more_direct", "ask_question", "keep_going"]) {
  await call(
    `refine (${action})`,
    "/api/v1/refine",
    json({ text: "I was wondering if maybe you would like to get a coffee sometime, no pressure", action, instruction: "", count: 1, conversation: "", locale: "en" }),
    envelope({ options: "array" }, (result) => suggestions(result.options, 1)),
  );
}

await call(
  "coach (question)",
  "/api/v1/coach",
  json({ mode: "ask", topic: "asking_out", messages: [{ role: "user", text: "How do I move from chatting to suggesting a coffee without making it awkward?" }], conversation: "", draft: "", goal: "", locale: "en" }),
  envelope({ message: "string", suggestions: "array", followUps: "array" }),
);

await call(
  "coach (message review)",
  "/api/v1/coach",
  json({ mode: "review", topic: "general", messages: [], conversation: "", draft: "Hey!! I had the BEST time last night, I really really hope we can do it again soon, let me know!!", goal: "Show I enjoyed it without sounding too eager", locale: "en" }),
  envelope({ message: "string", suggestions: "array", followUps: "array", review: "object" }, (result) => {
    const gaps = missing(result.review, { intent: "string", comesAcross: "string", checks: "array", improvements: "array", alternative: "string", whyItWorks: "string", lesson: "string" });
    return gaps.length ? `review missing ${gaps.join(", ")}` : null;
  }),
);

// Practice counts against the daily coaching allowance, so it runs as its own install.
headers["X-RR-Install"] = randomUUID();

const opening = await call(
  "coach (practice, opening)",
  "/api/v1/coach",
  json({ mode: "practice", topic: "general", messages: [], conversation: "", draft: "", goal: "", scenario: { id: "keep_it_going", detail: "" }, locale: "en" }),
  envelope({ message: "string", suggestions: "array", followUps: "array", practice: "object" }, (result) => (typeof result.practice.finished === "boolean" ? null : "practice.finished missing")),
);

if (opening) {
  const turns = [];
  if (opening.result.practice.partnerReply) turns.push({ role: "coach", text: opening.result.practice.partnerReply });
  turns.push({ role: "user", text: "haha busy but good. I finally tried that ramen place, have you been?" });
  await call(
    "coach (practice, next turn)",
    "/api/v1/coach",
    json({ mode: "practice", topic: "general", messages: turns, conversation: "", draft: "", goal: "", scenario: { id: "keep_it_going", detail: "" }, locale: "en" }),
    envelope({ message: "string", suggestions: "array", followUps: "array", practice: "object" }),
  );
}

await call("rejects an empty rewrite", "/api/v1/refine", json({ text: "", action: "shorter" }), (response, body) =>
  response.status === 400 && body?.error?.code === "invalid_request" && typeof body.error.message === "string" ? null : "expected a 400 with an error message",
);

await call("rejects a file that is not an image", "/api/v1/analyze", multipart({ conversation: "", locale: "en" }, [Buffer.from("not an image")]), (response, body) =>
  response.status === 400 && typeof body?.error?.message === "string" ? null : "expected a 400 with an error message",
);

if (flags.has("--probe")) {
  await call(
    "live AI probe",
    "/api/v1/diagnostics/probe",
    { method: "POST", headers: diagnosticsToken ? { "X-RR-Diagnostics": diagnosticsToken } : {} },
    (response, body) => {
      if (response.status === 403) return "the probe is closed on this server (set DIAGNOSTICS_TOKEN)";
      if (response.status !== 200) return "unexpected status";
      if (body.mode !== "live") return flags.has("--require-live") ? "the server has no AI key, so there is nothing to probe" : null;
      return body.ok ? null : `the AI call failed (reason: ${body.reason ?? "unknown"})`;
    },
  );
}

const failed = results.filter((r) => !r.ok);
console.log("");
console.log(`Server environment : ${status.environment ?? "unknown"}`);
console.log(`AI mode            : ${mode}${mode === "live" && status.ai?.models ? ` (${[...new Set(Object.values(status.ai.models))].join(", ")})` : ""}`);
console.log(`Result             : ${results.length - failed.length} of ${results.length} checks passed`);

if (mode !== "live") {
  console.log("\nThis server is in DEMO MODE: it has no ANTHROPIC_API_KEY, so every answer above is a labelled sample.");
  console.log("The request and response formats are verified. Live AI is NOT verified by this run.");
  console.log("To verify live AI: put ANTHROPIC_API_KEY in backend/.env.local, restart the server, and run this again with --require-live.");
}
if (failed.length === 0 && mode === "live") {
  console.log("\nLive AI answered every request in the shapes the app expects.");
}
process.exit(failed.length > 0 || (flags.has("--require-live") && mode !== "live") ? 1 : 0);
