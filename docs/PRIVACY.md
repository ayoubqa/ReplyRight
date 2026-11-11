# Privacy and security model

ReplyRight handles private dating conversations. These are the rules the code follows, and where each one is enforced.

## What leaves the device, and when

Nothing is uploaded until the user taps a button that asks for something: Read the conversation, Write my replies, a tweak, a question to the coach, or Reply and Rewrite in the keyboard.

| Sent | When | Kept by the server |
| --- | --- | --- |
| Screenshots (resized, re-encoded, metadata removed on the device) | Reading a conversation | No. Held in memory for one request, then discarded |
| Conversation text, draft, custom instruction | The request that needs them | No |
| My Voice (a trimmed copy) and, if selected, a person's nickname and notes | With each request | No |
| A random install id | Every request | Only as a key for today's usage count, in memory |
| The signed App Store transaction, when subscribed | Every request | Only a short-lived verification cache, keyed by hash |

The backend writes no conversation content to disk or to logs. Its log lines carry error kinds and status codes only (`backend/src/lib/ai/anthropic-provider.ts`, `backend/src/lib/server/pipeline.ts`). Responses are sent with `Cache-Control: no-store`. The iOS networking layer uses an ephemeral `URLSession` with no cookie store and no disk cache.

Content is processed by the configured AI provider (Anthropic) under its API terms.

## What stays on the device

Voice profile, saved replies, saved sessions, people (under nicknames), favourite styles and settings are JSON files in the App Group container, written with file protection. Saved sessions hold text only, never screenshots.

Two things are temporary by design:

- **Keyboard context**: conversation text the user handed to the keyboard. Text only. Deleted after 24 hours or when cleared.
- **Share inbox**: something shared to ReplyRight "for later", including its screenshots. Deleted when opened, when dismissed, or after 2 hours.

The Privacy Center in the app deletes any category, or everything. Erasing everything keeps only the install id (so daily limits still work) and the subscription record (so Pro is not lost).

## The keyboard

- It can see only the text field being edited. It cannot read other apps' conversations and never claims to.
- Typing works without Full Access. Full Access is requested only because iOS requires it for network use, and the app explains that in plain language.
- With Full Access on, the keyboard still makes no request while the user types. Requests happen only on an explicit tap.
- Nothing typed is stored. The typing engine is a pure state machine that keeps no text.
- The clipboard is read only when the user taps "Use copied message".
- AI features are switched off in secure fields and in fields marked as passwords, one-time codes, payment details or usernames, and on number pads (`FieldSensitivity`).

## What the product will not do

- Read, scrape or connect to WhatsApp, Instagram, Tinder, Messages or any other app.
- Monitor anything in the background.
- Send a message on the user's behalf.
- Run analytics on conversation content. There is no analytics SDK in the app.
- Learn from the user without being asked. "Learn from my edits" is off by default, offered once, and everything it keeps is visible and deletable in My Voice.

## Behaviour of the assistant

Enforced in the prompts (`backend/src/lib/ai/prompts/principles.ts`) and checked by the eval cases:

- It describes how a message comes across in hedged language and keeps observations apart from assumptions. It never claims to know what someone feels.
- No manipulation: no negging, guilt, jealousy plays, pressure or games.
- If the other person has said no or asked for space, it will not write replies that push past that.
- Adults only. Any sign that either person is under 18 means no romantic or flirtatious content.
- Signs of threats, harassment or coercion put the user's safety first.
- Text inside screenshots and pasted conversations is content, never instructions.
- Passwords, codes and card numbers that appear in shared content are not repeated.

## Credentials and verification

- The Anthropic API key exists only in the backend's environment. Nothing in `ios/` contains or needs one.
- Subscription status is never taken on the client's word. The server verifies the App Store's signature chain itself.
- The install id is a random UUID, not derived from the device or the Apple Account. It is stored in the keychain so limits survive a reinstall.

## Known limits of this model

- The install id is supplied by the client, so a determined user could reset their daily limit. App Attest would close that.
- Requests pass through the AI provider. Review its data retention terms against your own promises before launch.
- The legal pages in `backend/src/app` are drafts that describe the software's behaviour. They need legal review.
