# Design system: "Low Light"

A quiet corner, late in the evening, with a friend who is good with words. ReplyRight should feel like that: warm, private, a little playful, and sure of itself. It should not look like an AI tool.

## The idea in one line

Bottle green ground, blush for the voice, a highlighter for the pencil, and a menu instead of a dashboard.

## Principles

1. **No cards.** Content sits straight on the ground in one left-aligned column. A hairline and some space separate one thing from the next. The only shapes are bubbles (messages), capsules (actions) and the one soft rectangle you write on.
2. **One filled action per screen.** The main action is the only filled control. Everything else is an outline or plain words in the voice colour.
3. **Messages look like messages.** Anything you might send is a blush bubble on the right. What they said is a bubble on the left. Advice is never in a bubble.
4. **The pencil marks what matters.** Highlighter yellow is used for the cursor, the reason beside a suggestion, and the one thing on a screen worth noticing. Once per screen at most.
5. **A menu, not a dashboard.** Choices are lines on a menu: what you get, in the display face, with a short description underneath.
6. **Loading is writing.** The mark's cursor blinks while ReplyRight works. No spinners, no sparkles.
7. **Flat.** No gradients, no glows, no shadows except under a toast.
8. **Plain words.** Sentence case everywhere. Labels are quiet and never in capitals. Errors say what happened and what to do next.

## Colour

Tokens live in `ReplyRightCore/Design/Palette.swift` as plain numbers, so SwiftUI (`Color.rr…` in `ReplyRightUI/Theme.swift`) and the UIKit keyboard (`UIColor.dynamic`) draw from one source.

| Name | After dark (default) | Daylight | Use |
| --- | --- | --- | --- |
| Ground (`background`) | Bottle `#0F231D` | Paper `#FBF1EC` | Every screen |
| `surface` | `#152C25` | `#FFF9F6` | The writing surface, sheets, notices |
| `surfaceRaised` | `#1C372F` | `#F6E7E0` | Pressed states, keyboard suggestion rows |
| `line` / `lineStrong` | Bone at 11% / 24% | Ink at 11% / 24% | Hairlines, outlines |
| `textPrimary` | Bone `#F4EEE6` | Ink `#12322A` | Text |
| `textSecondary` | `#A9BDB3` | `#4F6B62` | Supporting text |
| `textTertiary` | `#7C958A` | `#758C83` | Captions |
| Voice (`accent`) | Blush `#FFA79D` | Raspberry `#C2335A` | Approach names, links, selection |
| Pencil (`highlight`) | Highlighter `#F3DC5F` | `#F6DE6A` | Marks behind or beside text |
| `highlightInk` | `#F3DC5F` | `#7A5800` | The pencil as text: "demo sample", "worth a look" |
| `cursor` | Highlighter | Ink | The cursor of the mark, and text cursors |
| `buttonFill` / `buttonText` | Blush / Bottle | Ink / `#FFE7E1` | The main action, selected chips |
| `bubbleMine` / text | Blush / Bottle | Ink / `#FFF3EF` | Messages you might send |
| `bubbleTheirs` / text | `#21403A` / Bone | `#F1DDD4` / Ink | Messages from the other person |
| `success` | `#8FD9AC` | `#1F7A4D` | Live AI, a "good" check |
| `warning` | `#F2B866` | `#9A5F0B` | Limits, form hints |
| `danger` | `#FF7166` | `#B3261E` | Failures, permanent deletion |

Contrast: Bone on Bottle is about 15:1, secondary text about 8:1, Bottle on Blush about 9:1, Ink on Paper about 12:1, Raspberry on Paper about 5.6:1. All body text clears WCAG AA.

## Type

| Role | Face | Where |
| --- | --- | --- |
| Display | **Young Serif** (SIL Open Font License, bundled in `ReplyRightUI/Resources`) | The one big line on a screen, menu rows, the wordmark, lessons |
| Everything else | SF Pro (system) | Body, messages, controls, the keyboard |

Styles are in `RRTextStyle`: `hero` 37, `display` 30, `title` 25, `titleSmall` 20, `menu` 21 (all Young Serif), then `headline` 17 semibold, `bodyLarge` 18, `body` 16, `message` 17, `callout` 15, `footnote` 13, `caption` 12, `eyebrow` 13 medium. Every style scales with Dynamic Type through `ScaledMetric`.

The font is registered with Core Text the first time it is needed (`RRFonts`). If registration ever fails, the system serif is used, so nothing depends on it.

Headlines are set evenly. No word is picked out in another colour or style.

## Layout

- Screen margin 22, one column, max width 640 on large devices.
- Spacing scale: 4, 8, 12, 16, 24, 36, 56.
- Sections are separated by a `Rule()` (1 pt hairline) and vertical space, never by a box. `rrCard()` is kept as a name and now draws a ruled section.
- `rrPanel()` is the one filled rectangle: the place you write on Home, and sheets.
- Bars use the ground colour. Navigation titles are set in Young Serif.

## Components (`ReplyRightUI`)

| Component | What it is |
| --- | --- |
| `BrandMark`, `BrandLogo` | The mark and the logo, drawn from the same geometry as the icon. `isWriting` blinks the cursor |
| `MenuRow` | A line on the menu: title in the display face, a description, a chevron |
| `MessageBubble`, `BubbleShape` | A message, mine or theirs |
| `MarginNote` | The reason beside a suggestion, with a pencil line |
| `Highlighted` | A highlighter stroke under a few words |
| `ThinkingView` | Loading: the mark with a blinking cursor and a changing line |
| `ProvenanceLabel` | "Written by live AI" or "Demo sample, not written for you" |
| `ConnectionPill` | A small summary of the connection, tappable |
| `ErrorNote` | A failure with a retry (when one can help) and an optional second action |
| `DemoBadge` | The demo-mode notice |
| `HeadsUpNote` | A gentle note when something deserves care |
| `EmptyNote` | An invitation to act where there is nothing yet |
| `RRChip` | Outline when idle, filled when chosen |
| `RRTextArea`, `RRField` | The writing surface, and a field on a line |
| Button styles | `.rrPrimary` (filled), `.rrSecondary` (outline), `.rrQuiet` (words), `.rrPress` (rows) |

## Motion and haptics

- `Animation.rrSnappy` for touch, `Animation.rrGentle` for content arriving.
- The cursor blink (0.52 s, ease in and out) is the product's signature motion. It stops when Reduce Motion is on.
- The keyboard fades between keys and panel in 0.16 s; with Reduce Motion the swap is immediate.
- Haptics: a light tap for actions, a selection tick for choices, success for copy and save, warning before a paywall. All respect the Haptics switch in You.

## States

- **Empty**: `EmptyNote` says what will appear here and how to make it appear.
- **Loading**: `ThinkingView`. In a practice conversation only, typing dots in a "theirs" bubble, because someone there really is typing.
- **Failure**: `ErrorNote`/`FailureNote`. A heading that names the problem, one sentence, "Try again" only when retrying can help, and "Connection details" when the connection is the problem.
- **Demo**: every screen that shows generated content carries `ProvenanceLabel` or `DemoBadge`.

## The keyboard

UIKit, same palette (`KeyboardTheme`). The toolbar shows the mark, Reply (filled), Rewrite and Saved (outlines) and the language switch. Panels use the system face so they sit naturally beside the keys. The mark is drawn with Core Animation in `KeyboardBrand.swift` from the same numbers as the app.

## Accessibility

- Dynamic Type on every text style; layouts wrap rather than truncate.
- Touch targets are at least 44 pt.
- VoiceOver labels on every control; decorative marks are hidden.
- Colour is never the only signal: live and demo are written out, review verdicts are words.
- Reduce Motion stops the blink and the fades.
- Light ("Daylight") and dark ("Evening") are both first-class; You, Appearance chooses, or follows the iPhone.
