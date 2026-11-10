# ReplyRight

**Say it better. Be yourself.**

ReplyRight is a mobile-first AI dating communication assistant. Share a screenshot or paste a conversation, pick a tone, optionally add a nudge ("make it less eager", "make them laugh"), and get three natural, distinct reply options you can edit, regenerate and copy.

It is deliberately not a generic chatbot: suggestions respect the other person's boundaries, avoid manipulative tactics, never claim to know how someone feels, and always offer options rather than "the one perfect line".

## Features

- **Landing page** explaining the product, tones, principles and privacy.
- **Compose** (`/app`): screenshot upload (tap, drag and drop, or paste from the clipboard, up to 4) or pasted text.
- **AI interpretation**: a short, hedged "read" of the conversation, plus a transcript of what was read from the screenshots so you can check it.
- **Five tones**: Flirty, Confident, Playful, Charming, Subtle.
- **Custom instruction** with one-tap suggestions.
- **Three reply options**, each with an approach label and a short "why". You can copy, edit inline, undo edits, regenerate (with previous options excluded), and apply quick tweaks (Shorter, Less eager, Funnier, Bolder).
- **Communication profile** (`/app/profile`): default tone, language, humour, message length, emoji use, writing style and an optional "about me". Saved automatically on the device.
- **Demo mode**: runs without credentials and is clearly labelled everywhere it appears.
- **Privacy page** (`/privacy`).

## Tech stack

- Next.js 16 (App Router, Turbopack, Cache Components) with React 19 and TypeScript
- Tailwind CSS v4 (CSS-first theme in `src/app/globals.css`)
- Anthropic TypeScript SDK (`@anthropic-ai/sdk`) for multimodal generation with structured outputs
- Zod for request and response validation, shared by client and server

## Getting started

Requires Node.js 20.9+ (tested on Node 22).

```bash
npm install
cp .env.example .env.local   # optional: add ANTHROPIC_API_KEY for real AI replies
npm run dev                  # http://localhost:3000
```

Production build:

```bash
npm run build
npm start
```

Lint and type-check:

```bash
npm run lint
npx tsc --noEmit
```

## Environment variables

All variables are read **on the server only**. API keys never reach browser code.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ANTHROPIC_API_KEY` | For AI mode | none | Anthropic API key. Without it the app runs in demo mode. |
| `AI_PROVIDER` | No | inferred | `anthropic` or `demo`. If unset, `anthropic` is used when a key is present. |
| `ANTHROPIC_MODEL` | No | `claude-opus-5-5` | Model ID to use. |
| `AI_EFFORT` | No | `medium` | `low`, `medium` or `high`. Trades latency and cost against nuance. |
| `RATE_LIMIT_PER_MINUTE` | No | `20` | Per-IP limit for `POST /api/replies`. |

The AI mode is resolved at request time, so you can change these variables without rebuilding.

### Demo mode

With no `ANTHROPIC_API_KEY` (or with `AI_PROVIDER=demo`), ReplyRight returns **pre-written sample replies**. It does not read your screenshots or messages and does not apply custom instructions. This is labelled in the header badge ("Demo mode"), on a banner above the results, in the "read" summary, and with a "Sample" tag on every reply card. API responses carry `"mode": "demo"`.

## Privacy behaviour

- **Screenshots are never stored.** The browser redraws each image to a canvas, which resizes it to at most 2000px on the long edge and strips EXIF and location metadata. It is then uploaded as multipart form data. The server reads it into memory, checks its real type from magic bytes, sends it to the AI provider for that one request and then discards it. Nothing is written to disk, saved to a database or logged.
- **Pasted text** is handled the same way and isn't persisted on the server or in the browser.
- **The profile** is stored in `localStorage` on the device and sent with each request.
- **No scraping.** ReplyRight never connects to or scrapes WhatsApp, Instagram, Tinder or any other app. Users decide what to share.
- When AI mode is on, content goes to Anthropic under its API terms and data retention policy.

## Architecture

```
src/
  app/
    page.tsx                 Landing page
    privacy/page.tsx         Privacy explainer
    app/layout.tsx           App shell (header, mode badge, mobile bottom nav)
    app/page.tsx             Compose screen
    app/profile/page.tsx     Communication profile
    api/replies/route.ts     POST endpoint: validation, rate limit, provider call, error mapping
  components/
    compose/                 Composer, ScreenshotInput, ReplyCard, Results states
    profile/ProfileForm.tsx
    app/, brand/, ui/        Navigation, logo, design primitives
  lib/
    domain/                  Tones, profile and reply schemas (shared, Zod)
    ai/
      types.ts               ReplyProvider interface (provider abstraction)
      prompt.ts              System prompt and product principles
      anthropic-provider.ts  Claude implementation (images + structured JSON output)
      demo-provider.ts       Labelled sample provider
      index.ts               Provider selection from env
    server/                  Transient image handling, rate limiter
    client/                  API client, on-device image preparation
    profile/store.ts         ProfileStore interface + localStorage implementation
```

### AI provider abstraction

Every provider implements `ReplyProvider` (`src/lib/ai/types.ts`):

```ts
interface ReplyProvider {
  id: string;
  mode: "live" | "demo";
  model: string | null;
  supportsImages: boolean;
  generateReplies(input: { request: ReplyRequest; images: TransientImage[] }): Promise<ReplyResult>;
}
```

To add another provider, implement the interface, throw a `ProviderError` with the right `kind` on failure, and register it in `src/lib/ai/index.ts`. The route handler and UI don't change.

The Anthropic provider sends screenshots as base64 image blocks and asks for output that matches `replyResultSchema` (structured outputs via `betaZodOutputFormat`). It uses adaptive thinking, the configured effort level and server-side refusal fallbacks. Refusals, truncation, schema failures, auth errors, rate limits and connection errors each map to a typed API error with a user-friendly message.

### API

`POST /api/replies` takes `multipart/form-data`:

- `payload`: JSON `{ conversation?, tone, instruction?, profile?, avoid? }`
- `images`: 0–4 image files (PNG, JPEG, WebP or GIF, at most 4 MB each after on-device compression)

At least one of `conversation` or `images` is required. It returns `{ mode, provider, model, result }`. On failure it returns `{ error: { code, message } }` with an appropriate HTTP status (400, 413, 422, 429, 502, 503).

### Ready for what's next (not implemented yet)

- **Authentication and Supabase**: add a remote `ProfileStore` next to the localStorage one, and identify users in the route handler. The rate limiter is a single-instance in-memory MVP; replace it with a shared store when scaling out.
- **Stripe**: gate `POST /api/replies` on entitlement in the route handler, before the provider call.
- **Native keyboard extensions**: the reply API is a plain multipart HTTP endpoint with a versionable JSON contract, so a keyboard extension can call it directly.
