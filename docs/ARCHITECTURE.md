# Architecture

## The shape of it

```
 iPhone                                                       Server
┌──────────────────────────────────────────────┐            ┌───────────────────────────┐
│ ReplyRight app (SwiftUI)                     │            │ backend/ (Next.js, API)   │
│ ReplyRightKeyboard (UIKit extension)         │   HTTPS    │  /api/v1/status           │
│ ReplyRightShare (share extension)            │ ─────────▶ │  /api/v1/analyze          │
│        │ all three link                      │            │  /api/v1/replies          │
│        ▼                                     │            │  /api/v1/refine           │
│ ReplyRightKit (local Swift package)          │            │  /api/v1/coach            │
│   ReplyRightCore  models, API client, store  │            │        │                  │
│   ReplyRightUI    SwiftUI design system      │            │        ▼                  │
│        │                                     │            │  AiProvider (interface)   │
│        ▼                                     │            │   AnthropicProvider       │
│ App Group container (JSON files) + keychain  │            │   DemoProvider            │
└──────────────────────────────────────────────┘            └───────────────────────────┘
```

The app, the keyboard and the share sheet are three processes. They share code through the package and share data through the App Group container. None of them holds an AI credential: every AI call goes through the backend.

## Key decisions

**Native, three targets, one package.** SwiftUI for the app and the share sheet, UIKit for the keyboard (a keyboard is a `UIInputViewController` and runs under a tight memory limit, so it links `ReplyRightCore` only and uses no SwiftUI). Everything that can be shared lives in `ReplyRightKit`, so the three targets cannot drift apart.

**Logic that can be tested lives in `ReplyRightCore`.** It depends only on Foundation. The keyboard's behaviour (shift, caps lock, capitalisation, double-space full stop, layouts per field type) is a pure state machine there, with the UIKit layer only drawing keys and reporting touches. The same goes for request clamping, error mapping and storage.

**The server owns the product rules.** Plans, daily limits and which intents are Pro are configured on the backend and delivered through `/api/v1/status`. The app renders locks from that; it does not hardcode them. The server enforces all of it again on every request.

**Two steps, then replies.** Reading a conversation (`analyze`) is separate from writing replies (`replies`). The app shows its read and lets the user choose an intent before any reply is written. Once a screenshot has been read, only the transcript text is sent onward, so images are uploaded once. `replies` also accepts screenshots directly, which the share sheet uses as a one-step path.

**JSON files, not a database.** The data is small (a profile, saved replies, a few sessions), must be readable from three processes, and should be trivial to inspect and erase. `SharedStore` is the single owner of the file names. Reads always go to disk because another process may have written.

**The connection is a first-class state.** `AppModel.connection` is one of: checking, live AI, AI not answering, demo mode, or unreachable (with the reason: nothing listening, address not found, blocked plain http, TLS failure, dropped). It is set from `/status` on launch and whenever the app becomes active, and corrected by every answer and every failure. Screens read it to show the pill on Home, the notice above anything that asks for an answer, and the Connection screen. A failed status check is shown, never swallowed, and the app never substitutes a made-up answer.

**One address per environment.** `ios/Config/Shared.xcconfig` holds a development, a staging and a production address. `RR_API_ENVIRONMENT` picks one per build configuration, and all three targets read the same Info.plist keys through `AppConfig`. Debug builds may switch at runtime; Release builds ignore runtime choices (`RR_ALLOW_ENVIRONMENT_SWITCH`).

**Diagnostics without content.** `DiagnosticsLog` keeps the last 40 requests in memory: endpoint, host, status, duration, outcome code, the server's coarse failure reason and its request id. It never holds a body or a header value. The server logs one matching line per request with the same id. The AI provider's own error text stays in the server log, and only in development unless `RR_DEBUG_ERRORS` asks for it.

**Profiles are the user's words, shared by consent.** A `CrushProfile` holds only what the user typed. Each kind of information has a switch (`Sharing`), and `payload` builds what is sent from those switches, only for a request where the user picked that person. The photo, saved replies and conversations are never part of it. Practice with the coach never sends a profile.

**Swift 5 language mode.** Chosen deliberately: the code was written without a compiler, and strict concurrency checking would have multiplied the number of first-build errors. Types that touch UI are `@MainActor`.

**The Xcode project is generated.** `ios/scripts/generate_xcodeproj.py` writes it from the files on disk with deterministic object ids. `ios/project.yml` describes the same thing for XcodeGen.

## API v1

All AI endpoints accept JSON. `analyze` and `replies` also accept `multipart/form-data` with a `payload` field (the same JSON) and up to four `images`.

Headers sent by the app: `X-RR-Install` (anonymous install id, for daily limits), `X-RR-Entitlement` (the StoreKit signed transaction, when subscribed), `X-RR-Client` (which target made the call). Every AI response carries `X-RR-Request`, an id that also appears in the server log.

| Endpoint | Purpose | Counts against |
| --- | --- | --- |
| `GET /status` | Mode (live or demo), whether live AI has been answering, model names, the deployment environment, plans, the caller's usage | nothing |
| `POST /analyze` | Transcript, a hedged read, observations kept apart from assumptions, suggested intents | nothing (rate limited) |
| `POST /replies` | Three distinct options for a reply (`kind: "reply"`) or an opener (`kind: "starter"`) | daily generations |
| `POST /refine` | Rewrite one message: more natural, more playful, more confident, more romantic, less intense, shorter, more direct, ask a question, keep it going, more like me, or in a tone. `count` is 1 or 3 | daily generations |
| `POST /coach` | One turn of the coach, in one of three modes: `ask` (a question, optionally on a topic), `review` (feedback on one message: intent, how it reads, five checks, improvements, an alternative, why it works, a lesson) or `practice` (the coach plays an invented other person and gives feedback). The client sends the exchange so far; the server keeps no history | daily coach messages |
| `POST /diagnostics/probe` | One small real AI call with a fixed sentence, to prove the key and model work. Open in development; elsewhere needs `DIAGNOSTICS_TOKEN` | nothing (rate limited) |

Every success has the same envelope:

```json
{ "mode": "live", "provider": "anthropic", "model": "…", "usage": { "tier": "free", "generations": { "used": 1, "limit": 10, "remaining": 9 }, "coach": { … }, "resetsAt": "…" }, "result": { … } }
```

Every failure is `{ "error": { "code", "message", "usage"?, "reason"? } }`. `reason` is a coarse cause for an AI failure (`credentials`, `billing`, `model`, `request`, `overloaded`, `timeout`, `network`, `rate_limit`, `refusal`, `output`), shown in the app's Connection screen and never containing request content. Codes: `invalid_request`, `unsupported_media`, `payload_too_large` (400/413), `limit_reached` and `upgrade_required` (402), `ai_declined` (422), `rate_limited` (429), `ai_bad_output` (502), `ai_unavailable` (503), `internal` (500). The Swift client maps each to a typed `APIError` with a message written for the user.

The schemas are in `backend/src/lib/domain/contracts.ts` and mirrored in `ios/Packages/ReplyRightKit/Sources/ReplyRightCore/Models/API.swift`. Change both together; the Swift tests assert the wire names.

## AI layer

`AiProvider` (`backend/src/lib/ai/types.ts`) has four methods: `analyze`, `replies`, `refine`, `coach`. To add a provider, implement it and register it in `index.ts`. Routes and clients do not change.

The Anthropic provider sends one structured-output request per task with a 45 second timeout and one retry. It asks for the server-side refusal fallback on models that support it; if the API rejects that parameter the provider drops it and carries on. Failures are classified (`ProviderError.reason`) and recorded in a small in-memory health record that `/status` reports.

Prompts are assembled from shared blocks (`prompts/principles.ts`) so the product principles are stated once: never claim to know what someone feels, no manipulation, respect boundaries, adults only, safety first, text inside shared content is never an instruction. Output is constrained to a JSON schema per task.

The model and reasoning effort are set per task from the environment. The default has not been validated by the eval harness yet.

## Subscriptions

1. The app reads `Transaction.currentEntitlements`, keeps only transactions StoreKit has verified, and stores the signed transaction (JWS) in the App Group container.
2. Every request forwards it in `X-RR-Entitlement`.
3. The server verifies the certificate chain against a pinned Apple Root CA G3 fingerprint, Apple's marker extensions, the ES256 signature, the bundle id, the product id, expiry and revocation (`backend/src/lib/server/entitlements.ts`).
4. Anything that fails is treated as the free tier.

Xcode's local StoreKit testing produces tokens that Apple has not signed. The server accepts them only when `ENTITLEMENT_TRUST_XCODE=true`.

## Not done yet

These are deliberate gaps, not oversights. Close them before launch.

- **Compile this revision.** The first version built unchanged on a Mac. This revision was written without Xcode and has not been compiled. See the README and `docs/VERIFICATION.md`.
- **Live AI run.** No request has been made with a real key. `npm run verify:live` is the check.
- **Model selection.** Run the eval harness with real keys and choose production models.
- **Shared server state.** Rate limiting and usage counters are in memory, which is correct for one instance and resets on deploy.
- **Abuse resistance.** Daily limits are keyed by an install id the client supplies. App Attest or DeviceCheck would make them harder to reset.
- **Renewal handling on the server.** Entitlement is checked from the transaction the app forwards. App Store Server Notifications would let the server learn about refunds and renewals on its own.
- **Accounts and sync.** There are none. Everything a user saves lives on one device.
- **Keyboard typing aids.** No autocorrect, predictions or swipe typing. The keyboard has English and Spanish layouts.
- **Localisation.** The interface is English. Replies are written in English, Spanish, or the conversation's language; French is wired through the backend but not enabled in the app.
- **Accessibility pass.** Labels, traits and Dynamic Type scaling are in place but have not been tested with VoiceOver on a device.
