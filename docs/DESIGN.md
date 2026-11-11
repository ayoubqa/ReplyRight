# Design system: "After Hours"

ReplyRight is set in the evening, when most of this texting happens. The goal is a product that feels like a well-made lifestyle app with a point of view, not an AI utility.

## Principles

1. **One confident action per screen.** The primary button is ivory on ink. Everything else is quieter.
2. **Editorial type.** Headlines are a serif with one phrase stressed in coral italics, the way a magazine would stress a word: "What's happening with *your crush?*"
3. **Messages look like messages.** Anything the user might send is drawn as a message bubble on the right. What the other person said is a bubble on the left. Advice is never in a bubble.
4. **Reasons in the margin.** The "why this could work" under each reply is a serif italic note with a thin rule, like an editor's comment.
5. **Loading has a pulse.** A typing bubble and a line that changes while you wait, never a bare spinner.
6. **Calm motion.** Quick springs for touch, slower ones for content arriving, an ambient glow that drifts. Reduce Motion turns the drift off.
7. **No hearts.** Warmth comes from colour, type and wording.

## Colour

Tokens live in `ReplyRightCore/Design/Palette.swift` as plain numbers, so SwiftUI (`Color.rr…` in `ReplyRightUI/Theme.swift`) and the UIKit keyboard (`UIColor.dynamic`) draw from the same source.

| Token | Evening (default) | Daylight | Use |
| --- | --- | --- | --- |
| background | `#0F0B15` | `#F7F2E9` | Screens: deep ink with a plum undertone, or warm ivory |
| surface | `#19131F` | `#FFFCF6` | Cards |
| surfaceRaised | `#231B2C` | `#F1EADD` | Chips, fields on cards |
| textPrimary | `#F6F1E7` | `#1B1422` | Ivory on ink, ink on ivory |
| textSecondary | `#B8AFC2` | `#5F5669` | Supporting text |
| accent | `#BBA9F5` | `#5B43A6` | Lavender: selection, links, icons |
| coral | `#F28C72` | `#D2553A` | Emphasis only: the stressed phrase, "fits", savings |
| bubbleMine | `#CDBEFA` to `#A892EE` | `#4A357F` to `#2F2152` | Messages the user might send |
| bubbleTheirs | `#2A2134` | `#E9E1D2` | Messages from the other person |
| buttonFill / buttonText | ivory / ink | ink / ivory | The primary action |

Evening is the default. Daylight and Match iPhone are under You, Appearance. Coral is deliberately rare: if it appears more than once or twice on a screen, something is wrong.

## Type

Display type is the system serif (New York); functional type is SF Pro. Every style scales with Dynamic Type (`rrText(_:)` uses `@ScaledMetric`).

| Style | Size | Face | Use |
| --- | --- | --- | --- |
| hero | 40 | serif | One per flow: onboarding |
| display | 32 | serif | Screen headline |
| title | 26 | serif | The read, the note above replies |
| titleSmall | 21 | serif | Card titles |
| headline | 17 semibold | sans | Row titles, buttons |
| bodyLarge / body | 18 / 16 | sans | Reading text |
| message | 17 | sans | Inside bubbles |
| callout / footnote / caption | 15 / 13 / 12 | sans | Supporting text |
| eyebrow | 11 semibold, tracked, caps | sans | Section labels, with a short coral rule |
| note | 15 italic | serif | Margin notes |

## Spacing and shape

Spacing steps: 4, 8, 12, 16, 24, 32, 48. Screen margin 20. Corner radii: 12 small, 18 controls, 22 bubbles, 26 cards. Bubbles are fully rounded except the corner nearest their sender. Tap targets are at least 40 points high; primary buttons are 54.

## Components (`ReplyRightUI`)

`EditorialTitle`, `Eyebrow`, `MessageBubble`, `BubbleShape`, `TypingDots`, `ThinkingView`, `MarginNote`, `HeadsUpNote`, `DemoBadge`, `ErrorNote`, `RRChip`, `FlowLayout`, `RRTextArea`, `RRField`, `AuroraBackground`, button styles (`.rrPrimary`, `.rrSecondary`, `.rrSecondaryCompact`, `.rrSecondaryWide`, `.rrQuiet`, `.rrPress`), `rrCard()`, `rrToast(_:)`, `rrScreenBackground()`, `Haptics`.

App-level pieces built from them are in `ios/ReplyRight/App/SharedViews.swift`: `ScreenScroll`, `ScreenHeader`, `ChoiceGroup`, `MultiChoiceGroup`, `PersonPicker`, `NavigationRow`.

## Haptics

Light tap for presses, selection for choosing from a set, success for copied, saved and purchased, warning when something is locked. All of it respects the Haptics switch under You.

## Keyboard

The keyboard uses the system keyboard backdrop with ReplyRight's key colours (plum-grey keys in the evening, white on warm grey in daylight), follows the host app's requested appearance, and adds one bar above the keys: a coral spark, a lavender Reply pill, Rewrite, and Saved. Panels replace the key area at the same height, with serif titles and the same pills.

## Voice

ReplyRight talks like a friend who is good at this.

- Short. Warm. Specific. "Okay, this is a good one. Let's not overthink it."
- Honest about uncertainty. "Only they know what they meant. This is a read, not a verdict."
- Never makes the user feel they need the app. "You made that one yours."
- Errors say what happened and what to do next, without blame.
- No exclamation marks doing the work of enthusiasm.

Lines used while waiting are in `ReplyRightCore/Support/Microcopy.swift`.
