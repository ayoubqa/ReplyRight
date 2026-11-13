/**
 * Model comparison for ReplyRight's reply generation.
 *
 *   npm run eval -- --models claude-opus-5-5,claude-sonnet-5-5,claude-haiku-5-5 --reps 2 --yes
 *   npm run eval -- --dry-run          (prints the plan and cost estimate, calls nothing)
 *
 * Every candidate runs the same cases through the app's real provider code
 * and prompts. Attempts that fail for infrastructure reasons go to
 * errors.jsonl and are never scored as model failures.
 */
import Anthropic from "@anthropic-ai/sdk";
import { mkdirSync, writeFileSync, appendFileSync } from "node:fs";
import { join } from "node:path";
import { AnthropicProvider, type CallMetrics } from "@/lib/ai/anthropic-provider";
import { resolveEfforts } from "@/lib/ai";
import { AI_TASKS, type AiTask } from "@/lib/ai/types";
import { refineRequestSchema, repliesRequestSchema } from "@/lib/domain/contracts";
import { CASES, type EvalCase } from "./cases";
import { runChecks, type CheckResults } from "./checks";
import { judge, type JudgeScores } from "./judge";

/** USD per million tokens (input, output). List prices as of 2026-11-03; confirm before relying on totals. */
const PRICES: Record<string, [number, number]> = {
  "claude-opus-5-5": [4, 20],
  "claude-sonnet-5-5": [2, 10],
  "claude-haiku-5-5": [0.1, 0.5],
  "claude-fable-5-2": [8, 40],
};
const DEFAULT_MODELS = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"];

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}
const flag = (name: string) => process.argv.includes(`--${name}`);

const models = (arg("models") ?? DEFAULT_MODELS.join(",")).split(",").map((m) => m.trim()).filter(Boolean);
const reps = Number(arg("reps") ?? 2);
const judgeModel = arg("judge") ?? "claude-fable-5-2";
const useJudge = judgeModel !== "none";
const filter = arg("filter");
const cases = filter ? CASES.filter((c) => c.id.includes(filter) || c.tags.includes(filter)) : CASES;

const cost = (model: string, input: number, output: number) => {
  const [inPrice, outPrice] = PRICES[model] ?? [0, 0];
  return (input * inPrice + output * outPrice) / 1_000_000;
};

interface Row {
  model: string;
  case: string;
  rep: number;
  tags: string[];
  texts: string[];
  headsUp: string | null;
  checks: CheckResults;
  judge: JudgeScores | null;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  judgeCostUsd: number;
}

async function runCase(provider: AnthropicProvider, c: EvalCase) {
  if (c.task === "replies") {
    const request = repliesRequestSchema.parse(c.request);
    const result = await provider.replies({ request, images: [], options: { includeSamples: true } });
    return { request, texts: result.replies.map((r) => r.text), headsUp: result.headsUp, requested: 3, avoid: request.avoid };
  }
  const request = refineRequestSchema.parse(c.request);
  const result = await provider.refine({ request, options: { includeSamples: true } });
  return { request, texts: result.options.map((r) => r.text), headsUp: result.note, requested: request.count, avoid: [] };
}

function mean(values: number[]) {
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : NaN;
}
function percentile(values: number[], p: number) {
  if (!values.length) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}

async function main() {
  const total = models.length * cases.length * reps;
  // Rough planning numbers: ~1.6k input and ~900 output tokens per generation (thinking included).
  const estimate =
    models.reduce((sum, m) => sum + cost(m, 1600, 900) * cases.length * reps, 0) +
    (useJudge ? cost(judgeModel, 900, 500) * total : 0);

  console.log(`Models:  ${models.join(", ")}`);
  console.log(`Cases:   ${cases.length} x ${reps} reps = ${total} generations`);
  console.log(`Judge:   ${useJudge ? judgeModel : "off (deterministic checks only)"}`);
  console.log(`Estimated cost: about $${estimate.toFixed(2)} (planning estimate; actual cost is reported from API usage)`);
  if (useJudge && models.includes(judgeModel)) {
    console.warn("Warning: the judge is also a candidate. Judges tend to prefer their own style; pick a different --judge.");
  }
  for (const m of [...models, ...(useJudge ? [judgeModel] : [])]) {
    if (!PRICES[m]) console.warn(`Warning: no price for ${m}; its cost will read as $0. Add it to PRICES.`);
  }
  if (flag("dry-run")) return;

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error("\nANTHROPIC_API_KEY is not set. This eval makes real, billed API calls. Set the key and re-run.");
    process.exit(1);
  }
  if (!flag("yes")) {
    console.error("\nThis will spend real money. Re-run with --yes to proceed.");
    process.exit(1);
  }

  const outDir = join("evals", "out", new Date().toISOString().replace(/[:.]/g, "-"));
  mkdirSync(outDir, { recursive: true });
  const client = new Anthropic({ apiKey, maxRetries: 2, timeout: 90_000 });
  const rows: Row[] = [];
  let errors = 0;

  for (const model of models) {
    const perTask = Object.fromEntries(AI_TASKS.map((t) => [t, model])) as Record<AiTask, string>;
    for (const c of cases) {
      for (let rep = 1; rep <= reps; rep++) {
        // A fresh provider per attempt keeps metrics isolated.
        const provider = new AnthropicProvider({ apiKey, models: perTask, efforts: resolveEfforts(), timeoutMs: 90_000 });
        let metrics: CallMetrics | null = null;
        provider.onMetrics = (m) => (metrics = m);
        try {
          const output = await runCase(provider, c);
          const m = metrics as CallMetrics | null;
          if (!m) throw new Error("no usage metrics recorded");
          if (!m.model.startsWith(model)) throw new Error(`served_model_mismatch: asked ${model}, got ${m.model}`);

          let scores: JudgeScores | null = null;
          let judgeCost = 0;
          if (useJudge) {
            try {
              const judged = await judge(client, judgeModel, output);
              scores = judged.scores;
              judgeCost = cost(judgeModel, judged.inputTokens, judged.outputTokens);
            } catch (error) {
              // A judge failure is a grader problem, not a model failure.
              appendFileSync(join(outDir, "errors.jsonl"), JSON.stringify({ model, case: c.id, rep, class: "judge_error", message: String(error) }) + "\n");
            }
          }
          const row: Row = {
            model,
            case: c.id,
            rep,
            tags: c.tags,
            texts: output.texts,
            headsUp: output.headsUp,
            checks: runChecks(output, c.expect),
            judge: scores,
            latencyMs: m.latencyMs,
            inputTokens: m.inputTokens,
            outputTokens: m.outputTokens,
            costUsd: cost(model, m.inputTokens, m.outputTokens),
            judgeCostUsd: judgeCost,
          };
          rows.push(row);
          appendFileSync(join(outDir, "results.jsonl"), JSON.stringify(row) + "\n");
          process.stdout.write(".");
        } catch (error) {
          errors++;
          appendFileSync(join(outDir, "errors.jsonl"), JSON.stringify({ model, case: c.id, rep, class: "harness_or_serving_error", message: String(error) }) + "\n");
          process.stdout.write("x");
        }
      }
    }
  }

  const lines = [
    "# ReplyRight model comparison",
    "",
    `Cases: ${cases.length}, reps: ${reps}, judge: ${useJudge ? judgeModel : "off"}. Errors (excluded from scores): ${errors}.`,
    `With n = ${cases.length * reps} per model, differences in pass rate smaller than about ±${Math.round(100 / Math.sqrt(cases.length * reps))} points are within noise.`,
    "",
    "| Model | Scored | Checks passed | Natural | Intent | Voice | Distinct | Context | Principles ok | p50 latency | p90 latency | Cost / 1k generations |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
  ];
  for (const model of models) {
    const mine = rows.filter((r) => r.model === model);
    const checkValues = mine.flatMap((r) => Object.values(r.checks));
    const judged = mine.map((r) => r.judge).filter((j): j is JudgeScores => j !== null);
    const j = (key: "natural" | "intent_fit" | "voice_fit" | "distinct_purposes" | "context_use") =>
      judged.length ? mean(judged.map((s) => s[key])).toFixed(2) : "n/a";
    lines.push(
      `| ${model} | ${mine.length} | ${(100 * mean(checkValues.map(Number))).toFixed(1)}% | ${j("natural")} | ${j("intent_fit")} | ${j("voice_fit")} | ${j("distinct_purposes")} | ${j("context_use")} | ${
        judged.length ? `${((100 * judged.filter((s) => s.principles_ok).length) / judged.length).toFixed(0)}%` : "n/a"
      } | ${(percentile(mine.map((r) => r.latencyMs), 50) / 1000).toFixed(1)}s | ${(percentile(mine.map((r) => r.latencyMs), 90) / 1000).toFixed(1)}s | $${(1000 * mean(mine.map((r) => r.costUsd))).toFixed(2)} |`,
    );
  }
  lines.push("", "## Failed checks by model", "");
  for (const model of models) {
    const failures = new Map<string, string[]>();
    for (const r of rows.filter((row) => row.model === model)) {
      for (const [name, ok] of Object.entries(r.checks)) if (!ok) failures.set(name, [...(failures.get(name) ?? []), r.case]);
    }
    lines.push(`- **${model}**: ${failures.size ? [...failures].map(([n, ids]) => `${n} (${[...new Set(ids)].join(", ")})`).join("; ") : "none"}`);
  }
  lines.push(
    "",
    `Judge cost: $${rows.reduce((s, r) => s + r.judgeCostUsd, 0).toFixed(2)}. Generation cost: $${rows.reduce((s, r) => s + r.costUsd, 0).toFixed(2)}.`,
    "",
    "Read a sample of results.jsonl yourself before deciding. A rubric score is a guide, not a verdict.",
  );
  writeFileSync(join(outDir, "report.md"), lines.join("\n") + "\n");
  console.log(`\n\n${lines.join("\n")}\n\nWrote ${outDir}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
