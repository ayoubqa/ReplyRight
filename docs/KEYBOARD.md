# The ReplyRight keyboard

The keyboard is the centre of the product: replies inside the chat, without switching apps. This page covers how the app knows whether the keyboard is set up, why Full Access is asked for, what typing supports today, and what could come next.

## What the app can know about the keyboard

iOS gives an app no API to ask whether its keyboard is switched on, or whether Full Access is allowed. The app cannot read Settings and cannot see the keyboard being used. So ReplyRight never shows a live reading. It shows the most recent evidence, with its date.

There are three kinds of evidence:

| Evidence | How it arrives | What it proves | Needs Full Access |
| --- | --- | --- | --- |
| The user's word | "I've switched it on" in the setup steps | Nothing. Shown as "Turned on, not tested yet" | No |
| Check-in | The keyboard writes `keyboard-checkin.json` to the App Group when it opens, at most every 10 minutes | The keyboard ran, with Full Access, on that date | Yes. Without Full Access the keyboard cannot write to the shared container |
| Test sentence | The keyboard types "ReplyRight Keyboard ✓ Full Access on/off" into the test field on the Keyboard tab, when the user taps **Type a test message** in the keyboard's status panel | The keyboard works, and whether Full Access was on at that moment | No. Typing always works, so this is the only signal from a keyboard without Full Access |

`KeyboardSetupStatus.derive` turns the evidence into one of four states. The latest evidence wins, so turning Full Access off and testing again shows up.

| State | Shown as | When |
| --- | --- | --- |
| `notSetUp` | Not set up | No evidence at all |
| `enabledNotTested` | Turned on, not tested yet | Only the user's word |
| `limitedAccess` | Typing only | The latest evidence is a test without Full Access |
| `ready` | Ready, last confirmed (date) | The latest evidence is a check-in, or a test with Full Access |

Every screen that shows the status says: "iOS doesn't let apps check this directly. This is what your keyboard last reported, or what you told us."

Known limits, stated plainly:

- A status of Ready can be out of date. If the user removes the keyboard in Settings, the app keeps showing the last confirmation until new evidence arrives. The date is always shown.
- The test sentence is ordinary text. Someone who types it by hand marks their own setup as tested. It only affects that person's own screen.
- A check-in is written only when the keyboard opens. A keyboard that is switched on but never opened leaves no trace.

Code: `ReplyRightCore/Models/KeyboardStatus.swift`, `ReplyRightCore/Keyboard/KeyboardHandshake.swift`, `SharedStore.loadKeyboardCheckIn/saveKeyboardCheckIn/loadKeyboardSetup/saveKeyboardSetup`. Tests: `KeyboardStatusTests`.

## Setup in the app

- **Onboarding** no longer includes keyboard setup. The user gets a first result first: a worked example that makes no request, or their own chat with one request.
- **Home** shows a keyboard card until the keyboard is ready: "Get replies inside any chat", a drawing of the keyboard, **Set up the keyboard** and **Not now** (back after a week). When the latest evidence is a test without Full Access, the card says so and offers the way to turn it on. Once ready, the card becomes one line: "Keyboard ready · confirmed (date)".
- **Keyboard tab**: status with its evidence date, the test field, how to use it in a chat, the Full Access explanation, what the keyboard can see, the conversation currently shared with it, saved lines, the default person, and what typing supports.
- **Setup journey** (sheet, four steps): add the keyboard (opens ReplyRight's own Settings page, where Keyboards is), allow Full Access (with the explanation and a note about the iOS warning), test it, use it in a chat. It starts at the step the evidence points to.

## Full Access

iOS requires Full Access for any keyboard that uses the network, the shared App Group container or the general clipboard. ReplyRight needs it for:

- Reply and Rewrite (network).
- Saved lines, people and conversations shared from the app (shared container). Without Full Access iOS may keep the container closed; the keyboard says so rather than showing an empty list as if nothing were saved.
- Offering a copied message as what the user is replying to (clipboard).

How text is handled, as the app explains it:

- Nothing is sent while the user types. Text leaves the device only when they tap Reply or Rewrite.
- Only the draft in the field and the conversation the user chose to give the keyboard are sent.
- Keystrokes are never collected or stored. Nothing is ever sent to another person.
- AI features switch off in secure, password, one-time code, payment, username and number fields (`FieldSensitivity`).
- The keyboard tells the app only when it last opened and how many suggestions were shown and inserted. Numbers and dates, never text.

When Full Access is switched on, iOS shows its own warning that the keyboard's developer could transmit anything typed. The app tells the user that this warning appears for every keyboard, and what ReplyRight actually sends.

## Replying with what was copied

Before: Reply → "What are you replying to?" → **Use copied message** → setup → **Write replies**.

Now, when the user taps Reply with nothing handed over yet and something on the clipboard:

1. The keyboard reads the clipboard (only because Reply was tapped; Full Access is already required for Reply).
2. `CopiedText.looksLikeMessage` filters out things that are not a chat message: single tokens with digits or symbols (passwords, codes), long runs of digits (cards, phone numbers) and links.
3. If it passes, the setup screen opens with the copied text quoted, a note "This is what you copied", and **Not this**. Nothing is sent until **Write replies**.
4. The copied text is held in memory only. It is not written to the shared container unless the user taps **Use copied message**, as before. **Not this** remembers the clipboard's change count so the same text is not offered again.

Whether iOS shows its paste permission banner when a keyboard extension reads the clipboard has not been checked on a device. If it does, it appears after the user taps Reply, which is the moment the keyboard needs the text.

## Ordinary typing: what it supports and what could come next

Today: English and Spanish layouts, long-press accents, shift and caps lock, double space for a full stop, number and symbol pages, field-aware layouts (email, URL, number pads), the system click, Reduce Motion support.

Investigated for later phases. Nothing here is built yet, and the app says "Not yet" for each.

| Feature | Feasible for a third-party keyboard? | How | Effort and notes |
| --- | --- | --- | --- |
| Autocorrect | Yes | `UITextChecker` for spelling candidates in the keyboard's language; `UILexicon` via `requestSupplementaryLexicon` for the user's contacts' names and text replacements. Apply on space or punctuation, with undo on backspace | Medium. Must feel as good as the system keyboard or it hurts. Runs on device, nothing sent |
| Predictive bar | Partly | `UITextChecker.completions(forPartialWordRange:)` for completions. No access to the system's language model | Medium. Competes for the toolbar; would need a toggle between the ReplyRight bar and suggestions |
| Emoji | Yes | An emoji page built from the Unicode emoji list, with recents stored in the keyboard's own `UserDefaults` | Medium. Large data set, memory must stay under the extension's limit, which is a few dozen megabytes; measure on a device |
| Dictation | **No** | iOS does not give third-party keyboards the microphone or the system dictation key | Not possible. The app tells users to switch to the iPhone keyboard with the globe key |
| Swipe typing | Technically yes | Path recognition plus a word model on device | Large. Out of scope |

Recommended order: emoji page, then autocorrect with undo, then a predictive bar behind a setting. Each needs device testing for memory and latency before it ships.

## Measuring adoption

The primary product metric is **weekly users who successfully generate and use at least one ReplyRight suggestion**. Keyboard adoption and keyboard insertions are tracked separately.

What is recorded, on the device only (`ProductActivity`, `activity.json`):

| Count | When |
| --- | --- |
| `suggestionsShown` | A set of live AI suggestions arrived (app, share sheet or keyboard). Demo samples are never counted |
| `suggestionsUsed` | A live suggestion was copied (app, share sheet) or inserted (keyboard). Saved lines and reopened saved sessions are not counted |
| `keyboardSuggestionsShown`, `keyboardInsertions` | The keyboard's share of the two above |

A week is successful when `suggestionsShown > 0` and `suggestionsUsed > 0`. Keyboard adoption is the share of users whose status is Ready.

These are plain numbers per UTC day, kept for 12 weeks, deleted with "Erase everything". **Nothing is sent anywhere.** Counting successful users across installs needs a reporting channel (for example a daily anonymous ping with the install id and these counts) that has not been built and needs the user's approval and a privacy policy update first.
