# Choosing production models

ReplyRight's replies have to sound natural, arrive quickly and cost little per
request. Those pull in different directions, so the model is configurable per
task (`AI_MODEL_REPLIES`, `AI_MODEL_ANALYZE`, `AI_MODEL_REFINE`,
`AI_MODEL_COACH`) and this harness exists to compare candidates on the same
cases before you pick.

```bash
npm run eval -- --dry-run                                   # plan and cost estimate, no API calls
npm run eval -- --models claude-opus-5-5,claude-sonnet-5-5,claude-haiku-5-5 --reps 2 --yes
npm run eval -- --filter safety --yes                       # one tag or case id
npm run eval -- --judge none --yes                          # deterministic checks only
```

It makes real, billed API calls and needs `ANTHROPIC_API_KEY`. Nothing runs
without `--yes`.

## What it measures

| Signal | How |
| --- | --- |
| Behaviour | Deterministic checks in `checks.ts`: three options, distinct wording, no wrapping quotes or em dashes, at most one question, voice limits (length, emoji), language, forbidden phrases, and correct declines. |
| Taste | A rubric judge in `judge.ts` scores naturalness, intent fit, voice fit, distinct purposes and context use (1 to 5), plus a principles pass/fail. |
| Latency | p50 and p90 of the generation call. |
| Cost | From the token usage the API reports, per 1,000 generations. |

## Reading the results

- Output lands in `evals/out/<timestamp>/`: `results.jsonl` (every scored
  attempt with its text), `errors.jsonl` (timeouts, serving errors and judge
  failures, which are never scored as model failures) and `report.md`.
- With 18 cases and 2 reps, pass-rate differences under roughly 17 points are
  noise. Raise `--reps` before acting on a small gap.
- The judge defaults to a model that is not a candidate. Do not judge a model
  with itself.
- The rubric judge has not been calibrated against human ratings. Read a
  sample of `results.jsonl` yourself; a person who texts is the real grader.
- Cases are hand-written and graded by properties, not by similarity to a
  reference answer, so no model is favoured by construction.

The graders themselves are unit-tested on known-good and known-bad outputs in
`tests/eval-checks.test.ts`.

## Status

The harness has been dry-run and its checks are tested. It has **not** been
run against live models yet, so the default model (`claude-opus-5-5` for every
task) is a starting point, not a measured choice.
