# AI cost controls and model routing

How ReplyRight keeps AI spend under control, how to configure it, and how to check it on a Mac without a paid live run. Covers Phase 1 (keys, spend limit, usage ledger, retries) and Phase 2 (the ModelRouter).

Nothing here changes what the app sends or receives: request and response formats are the same, apart from the additive fields noted below.

## The routing matrix

Every AI request is given a route by `describeCall` in `backend/src/lib/ai/router.ts`. Each route has a model, an effort and a thinking setting. These are the defaults, a starting hypothesis to be confirmed with the eval (see the last section):

| Route | When | Model | Effort | Thinking | On refusal |
| --- | --- | --- | --- | --- | --- |
| `read_text` | Reading a pasted conversation | Sonnet 5.5 | low | adaptive | API's own fallback |
| `read_screenshot` | Reading screenshots | Sonnet 5.5 | low | adaptive | API's own fallback |
| `reply_simple` | Short, text-only, intent natural or keep it going, no instruction, at most 10 lines and 600 characters | Haiku 5.5 | medium | adaptive | one try on Sonnet 5.5 |
| `reply_standard` | Every other text reply (flirting, asking out, feelings, boundaries, humour...) and "Three more" | Sonnet 5.5 | medium | adaptive | API's own fallback |
| `reply_screenshot` | Replies written straight from screenshots (share sheet) | Sonnet 5.5 | medium | adaptive | API's own fallback |
| `starter` | Conversation starters | Haiku 5.5 | medium | adaptive | one try on Sonnet 5.5 |
| `refine` | Tweaks (shorter, funnier, more like me...) | Haiku 5.5 | low | adaptive | one try on Sonnet 5.5 |
| `tone` | Tone rewrites (flirty, playful, charming, low-key, warm) | Haiku 5.5 | low | adaptive | one try on Sonnet 5.5 |
| `coach_ask` | A question to the coach | Sonnet 5.5 | medium | adaptive | API's own fallback |
| `coach_review` | Feedback on the user's own message | Sonnet 5.5 | medium | adaptive | API's own fallback |
| `coach_practice` | A rehearsal turn | Sonnet 5.5 | medium | adaptive | API's own fallback |
| `coach_advanced` | Coaching with `depth: "deep"` (Pro only) | Opus 5.5 | medium | adaptive | API's own fallback |

- **Model IDs and prices** were checked against Anthropic's models overview and pricing pages on 13 November 2026: `claude-haiku-5-5` ($0.10 / $0.50 per million input / output tokens, up to 100K-token prompts), `claude-sonnet-5-5` ($2 / $10), `claude-opus-5-5` ($4 / $20). All three support images, structured output and the effort setting.
- **Thinking stays adaptive by default**, as it was on Opus, so the first change is the model only. `thinking=off` is available per route and is what the eval should test next: Sonnet 5.5 uses `{type: "between_tools"}`, Haiku 5.5 `{type: "disabled"}`; Opus 5.5 cannot turn thinking off.
- **Fallbacks.** Sonnet and Opus keep the API's server-side refusal fallback, as before. Haiku has none, so a Haiku refusal gets exactly one try on Sonnet. Errors, timeouts and unusable answers are never re-sent to a bigger model, and nothing escalates to Opus automatically.
- **Deep coaching** is a new optional request field, `depth: "deep"`, on `/api/v1/coach`. Free users get `402 upgrade_required`. The app does not send it yet, so no traffic reaches Opus until a control for it is added.
- **Additive response changes:** `/status` has a new `ai.routes` map (route to model), and the response `model` field now names the model that actually answered. `ai.models` keeps its shape (one model per task, the task's main route).

## Configuration

All in `backend/.env.local` (development) or the host's environment (production). Full comments are in `backend/.env.example`.

```
# Keys: production uses only ANTHROPIC_API_KEY; everything else only ANTHROPIC_API_KEY_DEV.
ANTHROPIC_API_KEY_DEV=sk-ant-...

# One route: model[,effort=low|medium|high][,thinking=auto|off][,fallback=model|none]
AI_ROUTE_REPLY_SIMPLE=claude-haiku-5-5,thinking=off
AI_ROUTE_COACH_REVIEW=claude-opus-5-5

# The simple-reply rule
AI_SIMPLE_REPLIES=on                       # off: every reply is standard
AI_SIMPLE_REPLY_INTENTS=natural,keep_going
AI_SIMPLE_REPLY_MAX_CHARS=600

# Rollback: everything back on claude-opus-5-5 with adaptive thinking, exactly as before routing
AI_ROUTING=off

# Development spend limit (never applied in production)
RR_DEV_SPEND_LIMIT_USD=5
RR_DEV_SPEND_PERIOD=day                     # or month
RR_DEV_SPEND_WARN_AT=50,75,90
```

Precedence for a route's model: `AI_ROUTE_<ROUTE>`, then `AI_MODEL_<TASK>`, then `AI_MODEL`, then the default. `AI_ROUTING=off` overrides all of them. A value that cannot be read is logged at start-up and the route keeps its default. The server prints the table it is using on the first AI request: `[replyright] AI routes: read_text=claude-sonnet-5-5 ... reply_simple=claude-haiku-5-5>claude-sonnet-5-5 ...`.

> If `backend/.env.local` already sets `AI_MODEL` (for example `AI_MODEL=claude-opus-5-5` from an earlier setup), every route uses that model and routing has no effect. Remove the line to use the routing matrix.

## Validating on an Intel Mac with Xcode 16.2

Everything below is free except the optional steps marked with a cost. No full paid verification run is needed.

### 0. Prerequisites

```bash
xcodebuild -version              # Xcode 16.2
node -v                          # v22 or later
cd ReplyRight/backend && npm ci
```

### 1. Backend tests (free)

```bash
cd backend
npm test                         # expect: Tests 214 passed (214)
npm run typecheck && npm run lint && npm run build
```

### 2. Development key isolation (free: no AI calls)

The `/status` route never calls the AI, so these checks cost nothing. The provider is created on the first request, so the log lines appear after the first `curl`.

1. In `backend/.env.local`, put only a **fake** production key and no development key:
   ```
   ANTHROPIC_API_KEY=sk-ant-fake-production-key-for-testing
   ```
   ```bash
   npm run dev
   curl -s localhost:3000/api/v1/status | grep -o '"mode":"[a-z]*"'    # "mode":"demo"
   ```
   The server terminal shows: `ANTHROPIC_API_KEY is the production key and is not used in development. Put a development key in ANTHROPIC_API_KEY_DEV. Running in demo mode.`
2. Add the same value as `ANTHROPIC_API_KEY_DEV`, restart, repeat the `curl`. Still demo, and the log says `ANTHROPIC_API_KEY_DEV is the same key as ANTHROPIC_API_KEY`.
3. Remove `ANTHROPIC_API_KEY`, set `ANTHROPIC_API_KEY_DEV` to your real development key, restart, repeat the `curl`. Now `"mode":"live"`, and the log says `Live AI in development using ANTHROPIC_API_KEY_DEV.` followed by the route table. No key appears in any log line.
4. Production never reads the development key:
   ```bash
   npm run build && RR_ENVIRONMENT=production npx next start -p 3001
   curl -s localhost:3001/api/v1/status | grep -o '"mode":"[a-z]*"'    # "mode":"demo" (no ANTHROPIC_API_KEY set)
   ```
   Stop it with Ctrl-C.

### 3. Development spend limit (free: nothing is sent)

Use a separate ledger folder for this test so your real records stay clean.

```bash
cd backend
mkdir -p .usage-test
# In .env.local, with the real ANTHROPIC_API_KEY_DEV from step 2.3:
#   RR_USAGE_LOG_DIR=.usage-test
#   RR_DEV_SPEND_LIMIT_USD=5
npm run dev
```

In a second terminal, add a made-up record worth $2.60 (52% of the limit) and look at the status:

```bash
cd backend
node -e 'const f=`.usage-test/ai-usage-${new Date().toISOString().slice(0,7)}.jsonl`;require("fs").appendFileSync(f,JSON.stringify({at:new Date().toISOString(),environment:"development",feature:"manual_test",estimatedCostUsd:2.6})+"\n")'
curl -s localhost:3000/api/v1/status | python3 -c 'import json,sys; print(json.load(sys.stdin)["ai"]["spend"])'
# {'active': True, 'limitUsd': 5, 'percent': 52, 'state': 'warning', ...}
```

Add another $2.50 (102%), then try a rewrite. It is refused before anything reaches Anthropic:

```bash
node -e 'const f=`.usage-test/ai-usage-${new Date().toISOString().slice(0,7)}.jsonl`;require("fs").appendFileSync(f,JSON.stringify({at:new Date().toISOString(),environment:"development",feature:"manual_test",estimatedCostUsd:2.5})+"\n")'
curl -si -X POST localhost:3000/api/v1/refine -H 'content-type: application/json' \
  -d '{"text":"hey, how was your weekend?","action":"shorter"}' | grep -iE "^HTTP|x-rr-retry|reason"
# HTTP/1.1 503 ... x-rr-retry: no ... "reason":"budget"
```

The server log shows `Development AI spend limit reached: $5.10 of $5.00 this day. AI requests are blocked until ...`. Afterwards, delete `.usage-test` and remove `RR_USAGE_LOG_DIR` from `.env.local`.

The 50, 75 and 90% warnings are printed as real calls are recorded; the unit tests cover each threshold (`tests/spend.test.ts`).

### 4. Usage ledger and report (optional, under $0.001)

One real call through the diagnostics probe, which uses the cheapest route (Haiku):

```bash
curl -s -X POST localhost:3000/api/v1/diagnostics/probe | python3 -m json.tool   # "ok": true, "model": "claude-haiku-5-5"
ls .usage                                                                     # ai-usage-2026-11.jsonl
tail -n 1 .usage/ai-usage-*.jsonl | python3 -m json.tool                      # route, model, tokens, thinkingTokens, estimatedCostUsd
grep -c "weekend" .usage/*.jsonl                                               # 0: the probe's sentence is never logged
npm run usage                                                                  # totals by day, feature, model and client
```

### 5. iOS build (free)

In Xcode 16.2: open `ios/ReplyRight.xcodeproj`, choose the **ReplyRight** scheme and an **iPhone 16** simulator, then Product > Clean Build Folder (Shift-Cmd-K) and Product > Build (Cmd-B). The keyboard and share extensions build with the app. Or from Terminal:

```bash
cd ios
xcrun simctl list devices available | grep iPhone        # pick a simulator name if iPhone 16 is missing
xcodebuild -project ReplyRight.xcodeproj -scheme ReplyRight \
  -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug clean build | tail -3
# ** BUILD SUCCEEDED **
```

### 6. iOS unit tests (free)

```bash
cd ios/Packages/ReplyRightKit
swift test 2>&1 | tail -3                                  # Executed 121 tests, with 0 failures
swift test --filter APIClientTests 2>&1 | grep -E "NoAutomaticRetry|Executed"
```

`testNoAutomaticRetryWhenTheServerSaysARepeatCouldCostAnotherAICall` is the Phase 1 test for the app side of the retry change. The UI tests (Product > Test in Xcode) need the backend running; demo mode is enough.

### 7. Existing app behaviour (free in demo mode)

1. Run the backend in demo mode (`AI_PROVIDER=demo` in `.env.local`, or no key) and `npm run verify`: expect `21 of 21 checks passed`.
2. Run the app in the simulator: paste `Them: free this weekend?`, tap Read it, then Write my replies. Every answer says **Demo sample, not written for you**. Try a tweak, a coach question and the keyboard's Rewrite.

**Optional live smoke test (about $0.03 to $0.05):** with the development key, do one reply moment from a pasted conversation (read, replies, one tweak), then run `npm run usage`. Expect `read_text` on Sonnet 5.5, the replies on Haiku 5.5 (short, natural) or Sonnet 5.5, and the tweak on Haiku 5.5, each with real token counts.

### 8. Routing (free)

```bash
curl -s localhost:3000/api/v1/status | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["ai"]["routes"], indent=1))'
```

Then set `AI_ROUTING=off`, restart, and run it again: every route reads `claude-opus-5-5`. Remove the line afterwards.

## Comparing models before finalising (Phase 3)

The eval runs 41 invented cases covering every route through the real provider, router and prompts, with Haiku, Sonnet and Opus as candidates. It reports deterministic checks, rubric-judge scores (naturalness, context, flirting quality, tone, coaching), screenshot reading checked against the fixtures' known text, latency, the tokens each call actually used, cost per call and cost per successful task, and suggests the cheapest model within 0.3 judge points of the best for each route.

```bash
cd backend
npm run eval -- --dry-run                                   # plan and estimate; free
RR_DEV_SPEND_LIMIT_USD=4 npm run eval -- --judge none --yes # stage 1: checks only, about $2.40
RR_DEV_SPEND_LIMIT_USD=12 npm run eval -- --yes             # stage 2: with the judge, about $8
npm run eval -- --candidates claude-haiku-5-5:off,claude-sonnet-5-5:off,claude-sonnet-5-5 --routes reply_simple,reply_standard,refine,tone --yes
```

The report is in `backend/evals/out/<timestamp>/report.md`. Estimates are planning numbers; the report and the ledger have the real figures. With two to thirteen cases per route the comparison is directional: read `results.jsonl` before changing a route, and change one route at a time.
