# Choosing production models

ReplyRight's replies have to sound natural, arrive quickly and cost little per
request. Those pull in different directions, so the model is configurable per
task (`AI_MODEL_REPLIES`, `AI_MODEL_ANALYZE`, `AI_MODEL_REFINE`,
`AI_MODEL_COACH`) and this harness exists to compare candidates on the same
cases before you pick.

```bash
npm run eval -- --dry-run                                   # plan and cost estimate, no API calls
npm run eval -- --yes                                       # every route, Haiku vs Sonnet vs Opus
npm run eval -- --routes reply_simple,refine --yes          # some routes
npm run eval -- --candidates claude-haiku-5-5:off,claude-sonnet-5-5 --yes   # ":off" = thinking off
npm run eval -- --filter safety --yes                       # one tag or case id
npm run eval -- --judge none --yes                          # deterministic checks only
```

It makes real, billed API calls and needs `ANTHROPIC_API_KEY_DEV`, the
development key; it never uses the production key. Nothing runs without
`--yes`. Every call, judge included, is written to the usage ledger and counts
against the development spend limit (`RR_DEV_SPEND_LIMIT_USD`, $5 a day by
default). The run stops early, with partial results, when the limit is reached.
For a bigger run, raise the limit for that run only:
`RR_DEV_SPEND_LIMIT_USD=15 npm run eval -- --yes`.

## What it measures

| Signal | How |
| --- | --- |
| Behaviour | Deterministic checks in `checks.ts`: three options, distinct wording, no wrapping quotes or em dashes, at most one question, voice limits (length, emoji), language, forbidden phrases, and correct declines. Reads: every expected message transcribed, speakers right, order kept, nothing invented, latest message, and `problem` for blurred or non-chat images (the fixtures' text is known). Coaching: the parts each mode needs, and no claims about the other person's mind. |
| Taste | Rubric judges in `judge.ts`: replies and rewrites (naturalness, intent fit, voice and tone fit, distinct purposes, context use, charm, which is flirting quality on flirt cases), reads (accuracy, hedging, usefulness) and coaching (helpful, specific, honest, tone), each with a principles pass/fail. |
| Latency | p50 and p90 per route and candidate, from the usage ledger. |
| Cost | From the token usage each call reported (thinking tokens included): cost per call and cost per successful task. |
| Routing | Each case goes through the app's own router, so results are per route. The report suggests, per route, the cheapest candidate within 0.3 judge points and 5 check points of the best, with no principle failures. |

## Reading the results

- Output lands in `evals/out/<timestamp>/`: `results.jsonl` (every scored
  attempt with its text), `errors.jsonl` (timeouts, serving errors and judge
  failures, which are never scored as model failures) and `report.md`.
- Most routes have two to five cases, so pass-rate differences of a few points
  are noise. Raise `--reps` before acting on a small gap.
- The judge defaults to a model that is not a candidate. Do not judge a model
  with itself.
- The rubric judge has not been calibrated against human ratings. Read a
  sample of `results.jsonl` yourself; a person who texts is the real grader.
- Cases are hand-written and graded by properties, not by similarity to a
  reference answer, so no model is favoured by construction.

The graders themselves are unit-tested on known-good and known-bad outputs in
`tests/eval-checks.test.ts`.

## Status

The harness has been dry-run (41 cases, 123 generations with three
candidates, about $8 with the default judge or $2.40 with `--judge none`) and
its graders are tested. It has **not** been run against live models yet, so the
routing defaults in `src/lib/ai/router.ts` are a starting hypothesis, not a
measured choice.
