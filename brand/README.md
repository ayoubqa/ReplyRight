# ReplyRight brand

## The mark

A closing quotation mark followed by a text cursor: **what they said, and the moment before you answer.**

Their words end; your cursor waits. The quotation strokes are drawn like a pen pressed down and lifted, and they lean forward. The cursor stands straight. There is no speech bubble and no sparkle.

The primary logo is the same idea with the name written between the two: quote, ReplyRight, cursor. The symbol is the logo with the name taken out.

## Files

| File | Use |
| --- | --- |
| `logo.svg` | Primary logo on Bottle and other dark grounds |
| `logo-light.svg` | Primary logo on Paper and other light grounds |
| `symbol.svg` | Standalone symbol, dark grounds |
| `symbol-light.svg` | Standalone symbol, light grounds |
| `symbol-mono.svg` | One colour, for stamps and templates |
| `app-icon.svg` | iOS app icon (full bleed; iOS applies the corner mask) |
| `app-icon-dark.svg` | App icon, dark appearance |
| `app-icon-tinted.svg` | App icon, tinted appearance (greyscale for iOS to tint) |
| `launch-mark.svg` | The mark shown while the app launches |
| `png/` | Rendered previews |
| `fonts/` | Young Serif and its licence |

In the Xcode project (`ios/ReplyRight/Resources/Assets.xcassets`): `AppIcon` (any, dark, tinted), `BrandSymbol` and `BrandLogo` (vector, light and dark), `LaunchMark`, `LaunchBackground`, `AccentColor`.

Inside the app the mark is drawn in code (`ReplyRightUI/Brand.swift`, and `ReplyRightKeyboard/KeyboardBrand.swift` for the keyboard) from the same geometry, so it can blink its cursor while ReplyRight is working.

## Colours

| Name | Hex | Role |
| --- | --- | --- |
| Bottle | `#0F231D` | The ground, after dark |
| Bone | `#F4EEE6` | Text on Bottle |
| Blush | `#FFA79D` | The voice: quotation marks, messages, the main action |
| Highlighter | `#F3DC5F` | The cursor, and the one thing worth noticing |
| Paper | `#FBF1EC` | The ground, in daylight |
| Ink | `#12322A` | Text on Paper |
| Raspberry | `#C2335A` | Blush's daylight counterpart |

## Type

The wordmark is set in **Young Serif** (SIL Open Font License 1.1, `fonts/OFL.txt`) and converted to outlines, so no logo file needs the font installed.

## Using it

- Keep clear space around the logo equal to the height of the cursor's width times four.
- On dark grounds use `logo.svg`; on light grounds `logo-light.svg`. Do not recolour the parts.
- Do not put the mark inside a speech bubble, add sparkles, or set it on a gradient.
- Smallest size: the symbol at 20 pt, the logo at 80 pt wide.

## Rebuilding the artwork

Everything is generated from geometry, so a change is a change to numbers.

```bash
pip install fonttools
python3 brand/build.py     # writes the SVG files
node brand/render.js       # renders PNGs and fills the Xcode asset catalog (needs Playwright with Chromium)
```

If you change the mark's numbers in `build.py`, change `BrandGeometry` in `ios/Packages/ReplyRightKit/Sources/ReplyRightUI/Brand.swift` and the constants in `ios/ReplyRightKeyboard/KeyboardBrand.swift` to match.

## How it was chosen

Eight directions were drawn and compared at icon sizes before this one was picked: a quotation mark with a cursor, a tilted variant, two quotation marks leaning towards each other, a cursive double-r with a tick, a heart made of quotation marks, a proofreader's insertion caret, a lowercase r over three "keep this" dots, and a single quote with a cursor. The quote-and-cursor family was the only one that said what the product is for, stayed legible at 29 pt, and could move (the cursor blinks). The round "66" quotation marks read as numerals, so the strokes were redrawn as tapered pen presses.
