#!/usr/bin/env node
/**
 * Summarises the local AI usage ledger (backend/.usage/*.jsonl): calls, tokens,
 * retries and estimated cost by day, feature and model. Reads numbers only;
 * the ledger never contains conversation content.
 *
 *   npm run usage                 this month
 *   npm run usage -- --all        every month in the ledger
 *   npm run usage -- --day 2026-11-13
 *
 * RR_USAGE_LOG_DIR points it at another ledger directory.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const args = process.argv.slice(2);
const dir = resolve(process.env.RR_USAGE_LOG_DIR?.trim() || ".usage");
const day = args.includes("--day") ? args[args.indexOf("--day") + 1] : null;
const month = new Date().toISOString().slice(0, 7);

if (!existsSync(dir)) {
  console.log(`No usage ledger at ${dir} yet. It is written by a development server and by eval runs.`);
  process.exit(0);
}
const files = readdirSync(dir)
  .filter((f) => /^ai-usage-\d{4}-\d{2}\.jsonl$/.test(f))
  .filter((f) => args.includes("--all") || f.includes(day ? day.slice(0, 7) : month))
  .sort();

const records = [];
for (const file of files) {
  for (const line of readFileSync(join(dir, file), "utf8").split("\n")) {
    if (!line.trim()) continue;
    try {
      const r = JSON.parse(line);
      if (!day || r.at?.startsWith(day)) records.push(r);
    } catch {
      // skip a damaged line
    }
  }
}
if (records.length === 0) {
  console.log("No AI calls recorded for this period.");
  process.exit(0);
}

const usd = (n) => `$${n.toFixed(4)}`;
function table(title, keyOf) {
  const groups = new Map();
  for (const r of records) {
    const key = keyOf(r);
    const g = groups.get(key) ?? { calls: 0, input: 0, output: 0, thinking: 0, cached: 0, retries: 0, failed: 0, blocked: 0, cost: 0, ms: 0 };
    g.calls += 1;
    g.input += r.inputTokens ?? 0;
    g.output += r.outputTokens ?? 0;
    g.thinking += r.thinkingTokens ?? 0;
    g.cached += r.cacheReadInputTokens ?? 0;
    g.retries += r.retries ?? 0;
    g.failed += r.status !== "ok" && r.status !== "blocked" ? 1 : 0;
    g.blocked += r.status === "blocked" ? 1 : 0;
    g.cost += r.estimatedCostUsd ?? 0;
    g.ms += r.durationMs ?? 0;
    groups.set(key, g);
  }
  console.log(`\n${title}`);
  console.log(
    ["", "calls", "input", "output", "thinking", "cache read", "retries", "failed", "blocked", "avg ms", "est. cost", "cost/call"]
      .map((h, i) => (i === 0 ? h.padEnd(24) : h.padStart(11)))
      .join(""),
  );
  for (const [key, g] of [...groups].sort((a, b) => b[1].cost - a[1].cost)) {
    console.log(
      [
        String(key).slice(0, 23).padEnd(24),
        ...[g.calls, g.input, g.output, g.thinking, g.cached, g.retries, g.failed, g.blocked, Math.round(g.ms / g.calls)].map((n) =>
          String(n).padStart(11),
        ),
        usd(g.cost).padStart(11),
        usd(g.cost / g.calls).padStart(11),
      ].join(""),
    );
  }
}

const total = records.reduce((s, r) => s + (r.estimatedCostUsd ?? 0), 0);
console.log(`AI usage from ${dir}: ${records.length} calls, estimated ${usd(total)}.`);
console.log("Estimates from reported tokens and list prices (backend/src/lib/ai/pricing.ts), not Anthropic's invoice.");
if (records.some((r) => r.usageKnown === false)) {
  console.log("Some calls timed out or were cancelled; they may have been billed without reporting usage.");
}
table("By day", (r) => r.at.slice(0, 10));
table("By feature", (r) => r.feature);
table("By model", (r) => r.servedModel ?? r.model);
table("By environment and client", (r) => `${r.environment}/${r.client}`);
