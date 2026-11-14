/**
 * Model comparison for every ReplyRight route: Haiku, Sonnet and Opus on the
 * same invented cases, through the app's real provider, prompts and router.
 *
 *   npm run eval -- --dry-run                         plan and cost estimate, calls nothing
 *   npm run eval -- --yes                             every route, Haiku vs Sonnet vs Opus, 1 rep
 *   npm run eval -- --routes reply_simple,refine --yes
 *   npm run eval -- --candidates claude-haiku-5-5,claude-sonnet-5-5:off,claude-sonnet-5-5 --yes
 *   npm run eval -- --judge none --yes                deterministic checks only (cheapest)
 *   npm run eval -- --filter screenshot --yes         one tag or case id
 *
 * A candidate is a model id, optionally with ":off" (thinking off, where the
 * model allows it) or ":auto" (adaptive thinking). Without a suffix it uses
 * the route's configured setting. Every other route setting (effort, prompts)
 * stays as the router has it; the refusal fallback model is switched off so
 * each model is measured on its own.
 *
 * Evals are development traffic: they use ANTHROPIC_API_KEY_DEV, never the
 * production key, and every call (judge included) is written to the usage
 * ledger and counts against the development spend limit
 * (RR_DEV_SPEND_LIMIT_USD). The run stops when the limit is reached.
 *
 * Attempts that fail for infrastructure reasons go to errors.jsonl and are
 * never scored as model failures.
 */
import Anthropic from "@anthropic-ai/sdk";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AnthropicProvider } from "@/lib/ai/anthropic-provider";
import { checkSpend } from "@/lib/ai/budget";
import { resolveAnthropicKey } from "@/lib/ai/credentials";
import { estimateCostUsd, knownPrice } from "@/lib/ai/pricing";
import { describeCall, resolveRoutes, ROUTES, thinkingParam, type RouteKey, type RouteTable, type ThinkingMode } from "@/lib/ai/router";
import { ProviderError, type CallContext, type TransientImage } from "@/lib/ai/types";
import { onUsageRecorded, recordAiUsage, type AiUsageRecord } from "@/lib/ai/usage-log";
import { analyzeRequestSchema, coachRequestSchema, refineRequestSchema, repliesRequestSchema } from "@/lib/domain/contracts";
import { prepareImage } from "@/lib/server/images";
import { CASES, type EvalCase, type Fixture } from "./cases";
import { runChecks, runCoachChecks, runReadChecks, type CheckResults } from "./checks";
import { judge, repliesMaterial, scoreMean, type AnyScores, type JudgeKind } from "./judge";

// ---------------------------------------------------------------- arguments

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const flag = (name: string) => process.argv.includes(`--${name}`);

interface Candidate {
  label: string;
  model: string;
  /** Null: use the route's configured thinking setting. */
  thinking: ThinkingMode | null;
}

function parseCandidate(spec: string): Candidate {
  const [model, suffix] = spec.trim().split(":");
  const thinking = suffix === "off" || suffix === "auto" ? suffix : null;
  return { label: spec.trim(), model, thinking };
}

const DEFAULT_CANDIDATES = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"];
const candidates = (arg("candidates") ?? arg("models") ?? DEFAULT_CANDIDATES.join(","))
  .split(",")
  .filter((s) => s.trim())
  .map(parseCandidate);
const reps = Math.max(1, Number(arg("reps") ?? 1));
const judgeModel = arg("judge") ?? "claude-fable-5-2";
const useJudge = judgeModel !== "none";
const filter = arg("filter");
const routeFilter = arg("routes")
  ?.split(",")
  .map((r) => r.trim())
  .filter(Boolean);
const concurrency = Math.max(1, Math.min(4, Number(arg("concurrency") ?? 2)));
/** How far below the best judge score a cheaper model may be and still be suggested. */
const margin = Number(arg("margin") ?? 0.3);

// ---------------------------------------------------------------- cases

const fixtureCache = new Map<Fixture, TransientImage>();
async function fixture(name: Fixture): Promise<TransientImage> {
  const cached = fixtureCache.get(name);
  if (cached) return cached;
  const image = await prepareImage(new Uint8Array(readFileSync(join("scripts", "fixtures", `${name}.jpg`))));
  fixtureCache.set(name, image);
  return image;
}

type Prepared =
  | { task: "replies"; request: ReturnType<typeof repliesRequestSchema.parse>; images: TransientImage[] }
  | { task: "refine"; request: ReturnType<typeof refineRequestSchema.parse>; images: TransientImage[] }
  | { task: "analyze"; request: ReturnType<typeof analyzeRequestSchema.parse>; images: TransientImage[] }
  | { task: "coach"; request: ReturnType<typeof coachRequestSchema.parse>; images: TransientImage[] };

async function prepare(c: EvalCase): Promise<Prepared> {
  const images = await Promise.all(("images" in c && c.images ? c.images : []).map(fixture));
  switch (c.task) {
    case "replies":
      return { task: "replies", request: repliesRequestSchema.parse(c.request), images };
    case "refine":
      return { task: "refine", request: refineRequestSchema.parse(c.request), images: [] };
    case "analyze":
      return { task: "analyze", request: analyzeRequestSchema.parse(c.request), images };
    case "coach":
      return { task: "coach", request: coachRequestSchema.parse(c.request), images: [] };
  }
}

interface Ran {
  checks: CheckResults;
  kind: JudgeKind;
  material: string;
  output: unknown;
}

async function runCase(provider: AnthropicProvider, c: EvalCase, p: Prepared, call: CallContext): Promise<Ran> {
  if (p.task === "replies" && c.task === "replies") {
    const r = await provider.replies({ request: p.request, images: p.images, options: { includeSamples: true }, call });
    const texts = r.replies.map((x) => x.text);
    return {
      checks: runChecks({ texts, headsUp: r.headsUp, requested: 3, avoid: p.request.avoid }, c.expect),
      kind: "replies",
      material: repliesMaterial({ request: c.request, texts, headsUp: r.headsUp }),
      output: { texts, headsUp: r.headsUp },
    };
  }
  if (p.task === "refine" && c.task === "refine") {
    const r = await provider.refine({ request: p.request, options: { includeSamples: true }, call });
    const texts = r.options.map((x) => x.text);
    return {
      checks: runChecks({ texts, headsUp: r.note, requested: p.request.count, avoid: [] }, c.expect),
      kind: "replies",
      material: repliesMaterial({ request: c.request, texts, headsUp: r.note }),
      output: { texts, note: r.note },
    };
  }
  if (p.task === "analyze" && c.task === "analyze") {
    const a = await provider.analyze({ request: p.request, images: p.images, call });
    const read = { canReply: a.canReply, problem: a.problem, read: a.read, observations: a.observations, assumptions: a.assumptions, opportunity: a.opportunity, headsUp: a.headsUp };
    return {
      checks: runReadChecks(a, c.read),
      kind: "read",
      material: `<transcript>\n${a.transcript.map((l) => `${l.speaker}: ${l.text}`).join("\n") || "(empty)"}\n</transcript>\n\n<read>\n${JSON.stringify(read, null, 2)}\n</read>`,
      output: { transcript: a.transcript, latestMessage: a.latestMessage, ...read },
    };
  }
  if (p.task === "coach" && c.task === "coach") {
    const r = await provider.coach({ request: p.request, options: { includeSamples: true }, call });
    const asked = { mode: p.request.mode, topic: p.request.topic, messages: p.request.messages, draft: p.request.draft, goal: p.request.goal, scenario: p.request.scenario };
    return {
      checks: runCoachChecks(r, p.request, c.coach),
      kind: "coach",
      material: `<request>\n${JSON.stringify(asked, null, 2)}\n</request>\n\n<coach_answer>\n${JSON.stringify(r, null, 2)}\n</coach_answer>`,
      output: r,
    };
  }
  throw new Error(`case ${c.id} does not match its prepared task`);
}

/** The route table for one attempt: the case's route on the candidate, everything else as configured. */
function routesFor(base: RouteTable, route: RouteKey, candidate: Candidate): RouteTable {
  return {
    ...base,
    [route]: { ...base[route], model: candidate.model, thinking: candidate.thinking ?? base[route].thinking, fallback: null, source: "eval" },
  };
}

// ---------------------------------------------------------------- estimates (dry run)

/** Planning numbers, not measurements: input from the measured prompt sizes, output and thinking guessed. */
const PLAN: Record<EvalCase["task"], { input: number; output: number }> = {
  replies: { input: 3000, output: 300 },
  refine: { input: 2500, output: 150 },
  analyze: { input: 2800, output: 500 },
  coach: { input: 3800, output: 600 },
};
const IMAGE_TOKENS = 1708; // the 780x1688 fixtures
function plannedThinking(candidate: Candidate, base: RouteTable, route: RouteKey): number {
  const mode = candidate.thinking ?? base[route].thinking;
  if (thinkingParam(candidate.model, mode)) return 0; // thinking switched off
  if (candidate.model.includes("haiku")) return 400;
  if (candidate.model.includes("sonnet")) return 700;
  return 1000;
}
const usd = (n: number) => `$${n.toFixed(n < 0.1 ? 4 : 2)}`;

// ---------------------------------------------------------------- results

interface Row {
  route: RouteKey;
  candidate: string;
  model: string;
  case: string;
  rep: number;
  tags: string[];
  task: EvalCase["task"];
  error: string | null;
  checks: CheckResults;
  scores: AnyScores | null;
  judgeMean: number | null;
  principlesOk: boolean | null;
  usage: AiUsageRecord | null;
  judgeCostUsd: number;
  output: unknown;
}

const recordsById = new Map<string, (record: AiUsageRecord) => void>();
onUsageRecorded((record) => {
  if (record.requestId) recordsById.get(record.requestId)?.(record);
});

function mean(values: number[]) {
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : NaN;
}
function percentile(values: number[], p: number) {
  if (!values.length) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}
const fmt = (n: number, digits = 2) => (Number.isFinite(n) ? n.toFixed(digits) : "n/a");
const pct = (n: number) => (Number.isFinite(n) ? `${(100 * n).toFixed(0)}%` : "n/a");

function succeeded(row: Row): boolean {
  return row.error === null && Object.values(row.checks).every(Boolean) && row.principlesOk !== false;
}

interface Summary {
  candidate: string;
  runs: number;
  errors: number;
  checks: number;
  judge: number;
  principles: number;
  principleFailures: number;
  p50: number;
  p90: number;
  input: number;
  output: number;
  thinking: number;
  costPerCall: number;
  costPerSuccess: number;
}

function summarise(rows: Row[], candidate: string): Summary {
  const mine = rows.filter((r) => r.candidate === candidate);
  const scored = mine.filter((r) => r.error === null);
  const judged = scored.filter((r) => r.judgeMean !== null);
  const usages = mine.map((r) => r.usage).filter((u): u is AiUsageRecord => u !== null);
  const cost = usages.reduce((s, u) => s + u.estimatedCostUsd, 0);
  const successes = mine.filter(succeeded).length;
  return {
    candidate,
    runs: mine.length,
    errors: mine.length - scored.length,
    checks: mean(scored.flatMap((r) => Object.values(r.checks).map(Number))),
    judge: mean(judged.map((r) => r.judgeMean!)),
    principles: mean(judged.map((r) => Number(r.principlesOk))),
    principleFailures: judged.filter((r) => r.principlesOk === false).length,
    p50: percentile(usages.map((u) => u.durationMs), 50),
    p90: percentile(usages.map((u) => u.durationMs), 90),
    input: mean(usages.map((u) => u.inputTokens)),
    output: mean(usages.map((u) => u.outputTokens)),
    thinking: mean(usages.map((u) => u.thinkingTokens ?? 0)),
    costPerCall: usages.length ? cost / usages.length : NaN,
    costPerSuccess: successes ? cost / successes : NaN,
  };
}

/** The cheapest candidate within `margin` of the best judge score and 5 points of the best checks, with no principle failures. */
function suggest(summaries: Summary[]): { pick: Summary | null; note: string } {
  const usable = summaries.filter((s) => s.runs - s.errors >= 2);
  if (usable.length === 0) return { pick: null, note: "not enough scored runs" };
  const bestChecks = Math.max(...usable.map((s) => s.checks));
  const bestJudge = useJudge ? Math.max(...usable.map((s) => (Number.isFinite(s.judge) ? s.judge : -Infinity))) : NaN;
  const eligible = usable.filter(
    (s) =>
      s.principleFailures === 0 &&
      s.checks >= bestChecks - 0.05 &&
      (!useJudge || !Number.isFinite(bestJudge) || (Number.isFinite(s.judge) && s.judge >= bestJudge - margin)),
  );
  if (eligible.length === 0) return { pick: null, note: "no candidate passed without principle failures" };
  const pick = [...eligible].sort((a, b) => a.costPerCall - b.costPerCall)[0];
  return { pick, note: eligible.length === usable.length ? "all candidates within margin" : `${usable.length - eligible.length} below the bar` };
}

// ---------------------------------------------------------------- main

async function main() {
  const base = resolveRoutes().routes;
  const selected = CASES.filter((c) => !filter || c.id.includes(filter) || c.tags.includes(filter));
  const prepared = new Map<string, { prepared: Prepared; route: RouteKey }>();
  for (const c of selected) {
    const p = await prepare(c);
    const { route } = describeCall(c.task, p.request, p.images);
    if (routeFilter && !routeFilter.includes(route)) continue;
    prepared.set(c.id, { prepared: p, route });
  }
  const cases = selected.filter((c) => prepared.has(c.id));

  // Plan and estimate.
  const perRoute = new Map<RouteKey, number>();
  let estimate = 0;
  for (const c of cases) {
    const { route, prepared: p } = prepared.get(c.id)!;
    perRoute.set(route, (perRoute.get(route) ?? 0) + 1);
    for (const candidate of candidates) {
      const planned = PLAN[c.task];
      const thinking = plannedThinking(candidate, base, route);
      const tokens = {
        inputTokens: planned.input + p.images.length * IMAGE_TOKENS,
        outputTokens: planned.output + thinking,
        cacheReadInputTokens: 0,
        cacheWrite5mInputTokens: 0,
        cacheWrite1hInputTokens: 0,
      };
      estimate += estimateCostUsd(candidate.model, tokens).costUsd * reps;
      if (useJudge) {
        estimate +=
          estimateCostUsd(judgeModel, { ...tokens, inputTokens: 1200 + planned.output * 2, outputTokens: 300 + 500 }).costUsd * reps;
      }
    }
  }
  const total = cases.length * candidates.length * reps;
  console.log(`Candidates: ${candidates.map((c) => c.label).join(", ")}`);
  console.log(`Cases:      ${cases.length} x ${candidates.length} candidates x ${reps} rep(s) = ${total} generations`);
  console.log(`Routes:     ${ROUTES.filter((r) => perRoute.has(r)).map((r) => `${r} (${perRoute.get(r)})`).join(", ")}`);
  console.log(`Judge:      ${useJudge ? judgeModel : "off (deterministic checks only)"}`);
  console.log(`Estimated cost: about ${usd(estimate)} (planning estimate; actual cost comes from the API's usage, in report.md and the ledger)`);
  if (useJudge && candidates.some((c) => c.model === judgeModel)) {
    console.warn("Warning: the judge is also a candidate. Judges tend to prefer their own style; pick a different --judge.");
  }
  for (const m of [...candidates.map((c) => c.model), ...(useJudge ? [judgeModel] : [])]) {
    if (!knownPrice(m)) console.warn(`Warning: no price for ${m}; it is estimated at the highest known prices.`);
  }
  if (flag("dry-run")) return;

  // Always development traffic, whatever RR_ENVIRONMENT says.
  const key = resolveAnthropicKey("development");
  if (!key.ok) {
    console.error(`\n${key.message} This eval makes real, billed API calls. Set the development key and re-run.`);
    process.exit(1);
  }
  const spendAtStart = checkSpend();
  if (!spendAtStart.allowed) {
    console.error(`\n${spendAtStart.message}`);
    process.exit(1);
  }
  if (!flag("yes")) {
    console.error("\nThis will spend real money. Re-run with --yes to proceed.");
    process.exit(1);
  }

  const outDir = join("evals", "out", new Date().toISOString().replace(/[:.]/g, "-"));
  mkdirSync(outDir, { recursive: true });
  // No hidden SDK retries for the judge: a failed judgement is recorded and skipped, never silently paid for twice.
  const client = new Anthropic({ apiKey: key.apiKey, maxRetries: 0, timeout: 90_000, logLevel: "warn" });
  const rows: Row[] = [];
  let stoppedBy: string | null = null;

  const jobs = cases.flatMap((c) => candidates.flatMap((candidate) => Array.from({ length: reps }, (_, i) => ({ c, candidate, rep: i + 1 }))));
  let next = 0;
  async function worker() {
    while (next < jobs.length && !stoppedBy) {
      const { c, candidate, rep } = jobs[next++];
      const { prepared: p, route } = prepared.get(c.id)!;
      const requestId = crypto.randomUUID();
      let usage: AiUsageRecord | null = null;
      recordsById.set(requestId, (record) => (usage = record));
      const provider = new AnthropicProvider({
        apiKey: key.ok ? key.apiKey : "",
        routes: routesFor(base, route, candidate),
        environment: "development",
        timeoutMs: 90_000,
      });
      const row: Row = {
        route,
        candidate: candidate.label,
        model: candidate.model,
        case: c.id,
        rep,
        tags: c.tags,
        task: c.task,
        error: null,
        checks: {},
        scores: null,
        judgeMean: null,
        principlesOk: null,
        usage: null,
        judgeCostUsd: 0,
        output: null,
      };
      try {
        const ran = await runCase(provider, c, p, { feature: `eval_${route}`, route, client: "eval", requestId });
        row.checks = ran.checks;
        row.output = ran.output;
        if (useJudge && checkSpend().allowed) {
          const started = Date.now();
          try {
            const judged = await judge(client, judgeModel, ran.kind, ran.material);
            row.scores = judged.scores;
            row.judgeMean = scoreMean(judged.scores);
            row.principlesOk = judged.scores.principles_ok;
            row.judgeCostUsd = recordJudge(judgeModel, started, "ok", judged.model, judged.usage);
          } catch (error) {
            recordJudge(judgeModel, started, "error", null, null);
            appendFileSync(join(outDir, "errors.jsonl"), JSON.stringify({ route, candidate: candidate.label, case: c.id, rep, class: "judge_error", message: String(error).slice(0, 300) }) + "\n");
          }
        }
        process.stdout.write(Object.values(row.checks).every(Boolean) ? "." : "f");
      } catch (error) {
        if (error instanceof ProviderError && error.reason === "budget") {
          stoppedBy = error.message;
          recordsById.delete(requestId);
          return;
        }
        row.error = error instanceof ProviderError ? `${error.kind}:${error.reason}` : String(error).slice(0, 200);
        appendFileSync(join(outDir, "errors.jsonl"), JSON.stringify({ route, candidate: candidate.label, case: c.id, rep, class: "harness_or_serving_error", message: row.error }) + "\n");
        process.stdout.write("x");
      }
      row.usage = usage;
      recordsById.delete(requestId);
      rows.push(row);
      appendFileSync(join(outDir, "results.jsonl"), JSON.stringify(row) + "\n");
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));
  if (stoppedBy) console.warn(`\n\nStopped early: ${stoppedBy}`);

  // ---------------------------------------------------------------- report
  const labels = candidates.map((c) => c.label);
  const lines: string[] = [
    "# ReplyRight model comparison by route",
    "",
    ...(stoppedBy ? ["**Stopped early by the development spend limit.** Results below are partial.", ""] : []),
    `Cases: ${cases.length}, candidates: ${labels.join(", ")}, reps: ${reps}, judge: ${useJudge ? judgeModel : "off"}.`,
    `A run succeeds when every deterministic check passes and the judge finds no principle failure. Costs are estimated from the tokens each call reported.`,
    `With a handful of cases per route, differences of a few points are noise. Read results.jsonl before deciding.`,
    "",
    "## Suggested routing",
    "",
    "| Route | Suggested | Why | Cost per success | Configured now |",
    "|---|---|---|---|---|",
  ];
  const routeTables: string[] = [];
  for (const route of ROUTES) {
    const routeRows = rows.filter((r) => r.route === route);
    if (routeRows.length === 0) continue;
    const summaries = labels.map((label) => summarise(routeRows, label));
    const { pick, note } = suggest(summaries);
    lines.push(`| ${route} | ${pick?.candidate ?? "none"} | ${note} | ${pick ? usd(pick.costPerSuccess) : "n/a"} | ${base[route].model} |`);
    routeTables.push(
      "",
      `### ${route}`,
      "",
      "| Candidate | Runs | Errors | Checks | Judge (1-5) | Principles ok | p50 | p90 | Avg input | Avg output | Avg thinking | Cost / call | Cost / success |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
      ...summaries.map(
        (s) =>
          `| ${s.candidate} | ${s.runs} | ${s.errors} | ${pct(s.checks)} | ${fmt(s.judge)} | ${pct(s.principles)} | ${fmt(s.p50 / 1000, 1)}s | ${fmt(s.p90 / 1000, 1)}s | ${fmt(s.input, 0)} | ${fmt(s.output, 0)} | ${fmt(s.thinking, 0)} | ${usd(s.costPerCall)} | ${Number.isFinite(s.costPerSuccess) ? usd(s.costPerSuccess) : "n/a"} |`,
      ),
    );
  }

  // Quality by dimension, across routes.
  const judgedOf = (label: string, test: (r: Row) => boolean) => rows.filter((r) => r.candidate === label && r.error === null && r.scores && test(r));
  const scoreOf = (r: Row, key: string) => (r.scores as Record<string, unknown> | null)?.[key];
  const avgScore = (list: Row[], keys: string[]) =>
    mean(list.flatMap((r) => keys.map((k) => scoreOf(r, k)).filter((v): v is number => typeof v === "number")));
  lines.push(
    "",
    "## Quality by dimension",
    "",
    `| Dimension | ${labels.join(" | ")} |`,
    `|---|${labels.map(() => "---").join("|")}|`,
    `| Naturalness of replies (judge) | ${labels.map((l) => fmt(avgScore(judgedOf(l, (r) => r.task === "replies"), ["natural"]))).join(" | ")} |`,
    `| Context understanding (judge) | ${labels.map((l) => fmt(avgScore(judgedOf(l, (r) => r.task === "replies" || r.task === "analyze"), ["context_use", "accuracy"]))).join(" | ")} |`,
    `| Flirting quality (judge, flirt cases) | ${labels.map((l) => fmt(avgScore(judgedOf(l, (r) => r.tags.includes("flirt")), ["charm"]))).join(" | ")} |`,
    `| Tone accuracy (judge, rewrites) | ${labels.map((l) => fmt(avgScore(judgedOf(l, (r) => r.task === "refine"), ["intent_fit", "voice_fit"]))).join(" | ")} |`,
    `| Screenshot comprehension (checks) | ${labels
      .map((l) => pct(mean(rows.filter((r) => r.candidate === l && r.error === null && r.task === "analyze" && r.tags.includes("screenshot")).flatMap((r) => Object.values(r.checks).map(Number)))))
      .join(" | ")} |`,
    `| Coaching quality (judge) | ${labels.map((l) => fmt(mean(judgedOf(l, (r) => r.task === "coach").map((r) => r.judgeMean!)))).join(" | ")} |`,
    `| Principle failures (judge) | ${labels.map((l) => String(rows.filter((r) => r.candidate === l && r.principlesOk === false).length)).join(" | ")} |`,
    `| Median latency | ${labels.map((l) => `${fmt(percentile(rows.filter((r) => r.candidate === l && r.usage).map((r) => r.usage!.durationMs), 50) / 1000, 1)}s`).join(" | ")} |`,
    `| Estimated cost of the run | ${labels.map((l) => usd(rows.filter((r) => r.candidate === l && r.usage).reduce((s, r) => s + r.usage!.estimatedCostUsd, 0))).join(" | ")} |`,
    "",
    "## By route",
    ...routeTables,
    "",
    `Judge cost: ${usd(rows.reduce((s, r) => s + r.judgeCostUsd, 0))}. Generation cost: ${usd(rows.reduce((s, r) => s + (r.usage?.estimatedCostUsd ?? 0), 0))}.`,
    "",
    "Read a sample of results.jsonl yourself before deciding. A rubric score is a guide, not a verdict.",
  );
  writeFileSync(join(outDir, "report.md"), lines.join("\n") + "\n");
  console.log(`\n\n${lines.join("\n")}\n\nWrote ${outDir}`);
}

/** Judge calls bypass the provider, so they are written to the usage ledger here. Numbers only. Returns the cost. */
function recordJudge(
  model: string,
  started: number,
  status: "ok" | "error",
  servedModel: string | null,
  usage: Anthropic.Beta.BetaUsage | null,
): number {
  const tokens = {
    inputTokens: usage?.input_tokens ?? 0,
    outputTokens: usage?.output_tokens ?? 0,
    cacheReadInputTokens: usage?.cache_read_input_tokens ?? 0,
    cacheWrite5mInputTokens: usage?.cache_creation?.ephemeral_5m_input_tokens ?? usage?.cache_creation_input_tokens ?? 0,
    cacheWrite1hInputTokens: usage?.cache_creation?.ephemeral_1h_input_tokens ?? 0,
  };
  const { costUsd, priced } = estimateCostUsd(servedModel ?? model, tokens);
  recordAiUsage({
    at: new Date(started).toISOString(),
    environment: "development",
    feature: "eval_judge",
    task: "judge",
    route: "judge",
    client: "eval",
    requestId: null,
    model,
    servedModel,
    status,
    reason: null,
    httpStatus: null,
    durationMs: Date.now() - started,
    attempts: 1,
    retries: 0,
    usageKnown: usage !== null,
    inputTokens: tokens.inputTokens,
    outputTokens: tokens.outputTokens,
    thinkingTokens: usage?.output_tokens_details?.thinking_tokens ?? null,
    cacheReadInputTokens: tokens.cacheReadInputTokens,
    cacheCreationInputTokens: tokens.cacheWrite5mInputTokens + tokens.cacheWrite1hInputTokens,
    estimatedCostUsd: costUsd,
    priced,
  });
  return costUsd;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
