#!/usr/bin/env python3
"""Builds ReplyRight's brand artwork from its geometry.

The mark is an opening quotation mark followed by a text cursor: the moment
just before you say something. The primary logo is the same idea with the name
written between the two.

Everything here is original vector artwork. The wordmark is set in Young Serif
(SIL Open Font License, see fonts/OFL.txt) and converted to outlines, so no
file depends on an installed font.

    pip install fonttools
    python3 brand/build.py          # writes the SVG files next to this script
    node brand/render.js            # renders the PNGs and fills the Xcode asset catalog

Colours:
    Bottle       #0F231D   the ground, after dark
    Bone         #F4EEE6   text on Bottle
    Blush        #FFA79D   the voice: quotation marks, primary actions
    Highlighter  #F3DC5F   the cursor, and the one thing worth noticing
    Paper        #FBF1EC   the ground, in daylight
    Ink          #12322A   text on Paper
    Raspberry    #C2335A   Blush's daylight counterpart
"""
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

HERE = Path(__file__).parent
FONT = HERE / "fonts" / "YoungSerif-Regular.ttf"

BOTTLE, BOTTLE_DEEP, BOTTLE_LIFT = "#0F231D", "#0A1814", "#17362D"
BONE, BLUSH, HIGHLIGHTER = "#F4EEE6", "#FFA79D", "#F3DC5F"
PAPER, INK, RASPBERRY = "#FBF1EC", "#12322A", "#C2335A"


def n(value: float) -> str:
    return ("%.2f" % value).rstrip("0").rstrip(".")


def stroke_path(width: float, height: float) -> str:
    """One quotation stroke: pressed down round and heavy at the top, lifting to a soft point.

    The origin is the top centre. The same numbers are used by `BrandMark` in
    ReplyRightUI, so the artwork and the in-app drawing are the same shape.
    """
    r = width / 2
    return (
        f"M {n(-r)} {n(r)} A {n(r)} {n(r)} 0 1 1 {n(r)} {n(r)} "
        f"C {n(r)} {n(r + height * 0.35)}, {n(r * 0.55)} {n(height * 0.82)}, {n(r * 0.12)} {n(height)} "
        f"C {n(-r * 0.2)} {n(height * 1.02)}, {n(-r * 0.45)} {n(height * 0.98)}, {n(-r * 0.5)} {n(height * 0.9)} "
        f"C {n(-r * 0.9)} {n(height * 0.6)}, {n(-r)} {n(r + height * 0.3)}, {n(-r)} {n(r)} Z"
    )


# The mark on a 100 x 100 grid. Two strokes lean 12 degrees; the cursor stands straight.
STROKE_W, STROKE_H, LEAN = 14.8, 30.0, 12
STROKES_X = (26.0, 48.4)
STROKES_Y = 26.0
CURSOR = (67.2, 23.6, 7.6, 50.0)  # x, y, width, height
# The optical centre of the whole mark on that grid (the lean pushes the strokes left).
CENTER_X, CENTER_Y = 43.4, 48.6


def mark(quote: str, cursor: str, scale: float = 1.0, dx: float = 0.0, dy: float = 0.0) -> str:
    d = stroke_path(STROKE_W, STROKE_H)
    x, y, w, h = CURSOR
    parts = [
        f'<path d="{d}" transform="translate({n(sx)} {n(STROKES_Y)}) rotate({LEAN})" fill="{quote}"/>' for sx in STROKES_X
    ]
    parts.append(f'<rect x="{n(x)}" y="{n(y)}" width="{n(w)}" height="{n(h)}" rx="{n(w / 2)}" fill="{cursor}"/>')
    return f'<g transform="translate({n(dx)} {n(dy)}) scale({n(scale)})">{"".join(parts)}</g>'


def text_path(text: str, size: float, tracking: float = 0.0):
    font = TTFont(FONT)
    glyphs, cmap, hmtx = font.getGlyphSet(), font.getBestCmap(), font["hmtx"]
    scale = size / font["head"].unitsPerEm
    x, parts = 0.0, []
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs, ntos=n)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        parts.append(pen.getCommands())
        x += hmtx[name][0] * scale + tracking * size
    return " ".join(p for p in parts if p), x - tracking * size


def svg(width: float, height: float, body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {n(width)} {n(height)}" '
        f'width="{n(width)}" height="{n(height)}">{body}</svg>\n'
    )


def symbol(quote: str, cursor: str) -> str:
    # Centred in a 64 x 64 box with a little breathing room.
    scale = 0.86
    return svg(64, 64, mark(quote, cursor, scale, 32 - CENTER_X * scale, 32 - CENTER_Y * scale))


def logo(text: str, quote: str, cursor: str) -> str:
    size = 60.0
    d, width = text_path("ReplyRight", size, -0.01)
    d_stroke = stroke_path(11.2, 22.6)
    quotes = "".join(
        f'<path d="{d_stroke}" transform="translate({n(x)} 17) rotate({LEAN})" fill="{quote}"/>' for x in (11.5, 28.5)
    )
    word_x = 46.0
    cursor_x = word_x + width + 7
    body = (
        quotes
        + f'<path d="{d}" transform="translate({n(word_x)} 62)" fill="{text}"/>'
        + f'<rect x="{n(cursor_x)}" y="14" width="6" height="54" rx="3" fill="{cursor}"/>'
    )
    return svg(cursor_x + 6 + 10, 82, body)


def app_icon(ground: str, lift: str, quote: str, cursor: str) -> str:
    # Full-bleed square. iOS applies the corner mask.
    body = (
        f'<defs><radialGradient id="g" cx="0.3" cy="0.2" r="0.95">'
        f'<stop offset="0" stop-color="{lift}"/><stop offset="1" stop-color="{ground}"/></radialGradient></defs>'
        f'<rect width="1024" height="1024" fill="url(#g)"/>'
        + mark(quote, cursor, 11.8, 512 - CENTER_X * 11.8, 512 - CENTER_Y * 11.8)
    )
    return svg(1024, 1024, body)


def launch_mark() -> str:
    return svg(120, 120, mark(BLUSH, HIGHLIGHTER, 1.6, 60 - CENTER_X * 1.6, 60 - CENTER_Y * 1.6))


FILES = {
    # Standalone symbol
    "symbol.svg": symbol(BLUSH, HIGHLIGHTER),  # on Bottle and other dark grounds
    "symbol-light.svg": symbol(RASPBERRY, INK),  # on Paper and other light grounds
    "symbol-mono.svg": symbol("#000000", "#000000"),  # one colour, for stamps and templates
    # Primary logo
    "logo.svg": logo(BONE, BLUSH, HIGHLIGHTER),
    "logo-light.svg": logo(INK, RASPBERRY, INK),
    # App icon
    "app-icon.svg": app_icon(BOTTLE, BOTTLE_LIFT, BLUSH, HIGHLIGHTER),
    "app-icon-dark.svg": app_icon(BOTTLE_DEEP, "#10261F", BLUSH, HIGHLIGHTER),
    "app-icon-tinted.svg": app_icon("#000000", "#1C1C1C", "#FFFFFF", "#BDBDBD"),
    "launch-mark.svg": launch_mark(),
}

if __name__ == "__main__":
    for name, content in FILES.items():
        (HERE / name).write_text(content)
        print("wrote", name)
