# Verifying ReplyRight end to end

This is the procedure for proving that a conversation typed into the app comes back as a real AI answer, and for finding out which link is broken when it does not.

There are four links in the chain:

```
the app  ->  the ReplyRight server  ->  the AI provider  ->  back to the app
   1               2                        3                    4
```

Each step below checks one of them, from the server outwards. Do them in order.

## 0. What you need

- A Mac with Xcode 16 or later, and Node.js 20.9 or later.
- An Anthropic API key for live AI. Without one, steps 1, 2 and 4 still work in demo mode and step 3 cannot be done.

## 1. Start the server and check it answers

```bash
cd backend
npm install
cp .env.example .env.local          # first time only
npm run dev
```

Read the line `Local: http://localhost:3000`. **If it says another port** (Next.js moves to 3001 when 3000 is taken), the app must be pointed at that port: see step 4.

In a second terminal:

```bash
cd backend
npm run verify
```

This replays every request the iOS app makes, in the exact shapes the app uses, including the multipart screenshot upload. The screenshots are made-up chats in `backend/scripts/fixtures` (one readable, a second that continues it, one blurred past reading, one landscape with no chat in it), plus a damaged copy built on the fly. In live mode the script also checks what was read: the transcript has to contain the screenshots' messages, and the blurred and unrelated images have to be reported as such instead of being answered. It prints one line per check and a summary:

```
PASS  status                             HTTP 200 in 140 ms
PASS  analyze (pasted text)              HTTP 200 in 373 ms
PASS  analyze (one screenshot)           HTTP 200 in 15 ms
PASS  analyze (two screenshots)          HTTP 200 in 17 ms
...
AI mode            : demo
Result             : 21 of 21 checks passed
```

- All PASS and `AI mode: demo`: the server works and has no AI key. Go to step 2.
- `no answer from http://localhost:3000`: the server is not running, or is on another port. Pass the address: `npm run verify -- http://localhost:3001`.
- A FAIL line shows the HTTP status, the error code and a request id. The same id is in the server's terminal next to what went wrong.

## 2. Switch on live AI

Put the key in `backend/.env.local` and restart the server:

```
ANTHROPIC_API_KEY=sk-ant-...
```

The key lives only in this file on the server. It is never put in the app, in the Xcode project or in this repository.

## 3. Prove the AI answers

```bash
npm run verify:live
```

This runs the same checks, adds one small real AI call through the probe route, and fails unless the server answers in live mode. A full run makes about a dozen small AI calls.

- `Live AI answered every request in the shapes the app expects.` Link 3 works.
- `the AI call failed (reason: ...)`. The reason says what to fix:

| Reason | What it means | What to do |
| --- | --- | --- |
| `credentials` | The key was rejected, or may not use this model | Check `ANTHROPIC_API_KEY` |
| `billing` | The account has no credit | Add credit in the Anthropic console |
| `model` | The model name is not available to this key | Check `AI_MODEL` (default `claude-opus-5-5`) |
| `request` | The provider rejected the request itself (returned as `500 internal`) | Read the server terminal: in development it prints the provider's message |
| `image` | The provider could not use a screenshot (returned as `422 unsupported_media`) | Every image is decoded and re-checked on the server first, so this means an unusual file. The server terminal names the field |
| `overloaded` / `timeout` | The provider is busy | Try again |
| `network` | The server cannot reach the provider | Check the server's internet access |

The server terminal has one line per request: `[replyright] task=replies status=200 ms=4180 mode=live ... req=<id>`. It never contains a message, a draft or a screenshot.

**This step has not been run by the author.** No API key was available where this was written. The request the server sends was checked against the SDK's types and documentation, and the server recovers by itself if the optional refusal-fallback parameter is not accepted, but only this step proves it against the real service. If it fails with `reason: request`, the provider's message in the server terminal says which parameter to change in `backend/src/lib/ai/anthropic-provider.ts`.

## 4. Check the app

Run the **ReplyRight** scheme on an iPhone simulator.

1. On Home, look at the pill in the top right corner.
   - **Live AI**: all four links work.
   - **Demo mode**: the app reaches the server, and the server has no key (step 2).
   - **Can't reach ReplyRight**: the app cannot reach the server.
2. Tap the pill to open **Connection**. It shows the address this build is using, what the server says about itself, and a plain explanation of what to check. In a Debug build it also lets you:
   - choose Development, Staging or Production, or type an address (for example `http://localhost:3001` if the server moved ports);
   - tap **Run a live check**, which asks the server to make one small real AI call with a fixed sentence and reports whether it worked;
   - read the last requests the app made (address, status, timing, request id) and copy them as a report. The report contains no messages, screenshots or keys.
3. Type a message on Home, tap **Read it**, then **Write my replies**. Under the heading it says **Written by live AI** or **Demo sample, not written for you**. The app never shows a demo sample without that label, and never makes up an answer when the server fails.
4. Tap the pill again and check the request list shows `Analyze, HTTP 200` and `Replies, HTTP 200`, each marked Live AI.

### On a real iPhone

`localhost` on a phone means the phone. Start the server with `npm run dev -- --hostname 0.0.0.0`, then either set `RR_API_DEV_HOST` in `ios/Config/Shared.xcconfig` to your Mac's network name (`my-mac.local:3000`), or type `http://my-mac.local:3000` in Connection. The phone and the Mac must be on the same Wi-Fi, and iOS will ask for local network permission the first time.

Running the script twice within a minute can trip the per-address rate limit (`RATE_LIMIT_PER_MINUTE`, 30 by default); it says so when that happens.

## 5. Check the failure states

| Do this | Expect |
| --- | --- |
| Stop the server, then tap Read it | "Can't reach ReplyRight", a Try again button, and Connection details. The pill turns red |
| Start the server again and tap Try again | The read appears |
| Remove the key and restart the server | The pill says Demo mode and every result is labelled as a sample |
| Put a wrong key in `.env.local`, restart, tap Read it | "That didn't go through". Connection says the AI isn't answering and names the key as the cause |
| Turn on Airplane Mode | "You're offline" |
| Use up the free allowance | The paywall opens. Nothing is charged for failed requests |
| Share a blurred screenshot, or a photo that is not a chat | The read says it couldn't read it, or that it isn't a conversation, and offers another screenshot or pasting the text. No replies are written |
| Share a damaged image file | "One of the screenshots couldn't be opened" before anything is sent to the AI |

## 6. Automated tests

```bash
cd backend && npm test                              # 109 server tests, no network
cd ios/Packages/ReplyRightKit && swift test         # 120 unit tests, on a Mac
```

In Xcode, Product, Test also runs the 6 UI tests. The ones that ask for an answer need the server running; demo mode is enough.

Checks that work without Xcode:

```bash
pip install tree-sitter tree-sitter-swift
python3 ios/scripts/check_swift_syntax.py        # syntax only
python3 ios/scripts/check_swift_references.py    # types, members, argument labels and switch cases; a heuristic, not a compiler
python3 ios/scripts/check_xcodeproj.py           # project file structure
```

## What has and has not been verified

| | State |
| --- | --- |
| Server: type check, lint, production build, 109 tests | Verified where this was written |
| Server: every request shape the app sends, over HTTP, in demo mode (`npm run verify`, 21 checks) | Verified where this was written |
| Server: screenshot decoding, normalisation and refusal of damaged, unsupported, tiny and oversized images | Verified where this was written (unit and route tests, and `verify` against both `next dev` and a production build) |
| Server: live AI calls | **Not verified.** No key was available. Do step 3 |
| App, keyboard and share sheet: compile, run, unit tests, UI tests | **Not verified.** Written without Xcode. All Swift files parse, the project file is structurally valid, and a text-level check of types, members and argument labels passes. A compiler has not seen this revision |
| Keyboard and share sheet on a device, App Groups, Full Access | **Not verified** |
| StoreKit purchase and restore, server-side transaction checks against Apple | **Not verified** (the server checks are unit-tested with a locally generated certificate chain) |
| Accessibility with VoiceOver, Dynamic Type at the largest sizes, memory under the keyboard's limit | **Not verified** on a device |
