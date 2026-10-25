#!/usr/bin/env python3
"""Draws biblioteca's application icon and crops the splash-screen key art.

The icon is a shelf of book spines on deep ink blue, the last volume leaning
on the rest: a library, which is what the name says. The banner across the top
of the splash screen is a band of a real bookshelf, documents/bookshelf.jpg.

    python3 Scripts/make-icon.py

Writes:
    Biblioteca/Resources/Assets.xcassets/AppIcon.appiconset
    Biblioteca/Resources/SplashArt.jpg
    documents/icon.png
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Biblioteca/Resources/Assets.xcassets/AppIcon.appiconset"
SPLASH = ROOT / "Biblioteca/Resources/SplashArt.jpg"
PHOTO = ROOT / "documents/bookshelf.jpg"
PREVIEW = ROOT / "documents/icon.png"

# PIL does not anti-alias polygons, so everything is drawn large and reduced.
SUPERSAMPLE = 4

INK_TOP = (34, 48, 84)
INK_BOTTOM = (14, 20, 40)
WOOD = (176, 122, 74)
WOOD_EDGE = (120, 78, 44)
SPINES = [
    (200, 85, 61),    # terracotta
    (224, 165, 38),   # mustard
    (42, 157, 143),   # teal
    (239, 230, 210),  # cream
    (125, 46, 70),    # burgundy
    (70, 110, 170),   # cobalt
]

# macOS icon grid: an 824 pt body centred on a 1024 pt canvas.
CANVAS = 1024
BODY = 824
CORNER = 185


def shade(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, round(c * factor))) for c in color)


def gradient(size: tuple[int, int]) -> Image.Image:
    width, height = size
    column = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / max(1, height - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(INK_TOP, INK_BOTTOM)))
    return column.resize(size)


def spine(width: int, height: int, color: tuple[int, int, int]) -> Image.Image:
    """One upright book spine with cloth bands near its head and foot."""
    book = Image.new("RGBA", (width, height), color + (255,))
    draw = ImageDraw.Draw(book)
    band = max(2, round(height * 0.035))
    for top, factor in ((height * 0.12, 0.72), (height * 0.12 + band * 1.8, 1.25), (height * 0.86, 0.72)):
        draw.rectangle((0, round(top), width, round(top) + band), fill=shade(color, factor) + (255,))
    # A darker strip on the right reads as the curve of the spine.
    draw.rectangle((round(width * 0.84), 0, width, height), fill=shade(color, 0.82) + (255,))
    return book


def place_spine(art: Image.Image, left: float, base: float, width: float, height: float,
                color: tuple[int, int, int], lean: float = 0) -> float:
    """Stands a spine on `base` from `left`; returns the x where the next book may start.

    A leaning book (`lean` degrees, top towards the left) rests its upper
    corner on the book before it and its foot on the shelf.
    """
    book = spine(round(width), round(height), color)
    if lean:
        book = book.rotate(lean, resample=Image.BICUBIC, expand=True)
    art.alpha_composite(book, (round(left), round(base - book.height)))
    return left + book.width


def draw_shelf(draw: ImageDraw.ImageDraw, left: float, right: float, top: float, depth: float) -> None:
    draw.rectangle((left, top, right, top + depth), fill=WOOD)
    draw.rectangle((left, top + depth * 0.72, right, top + depth), fill=WOOD_EDGE)


def icon(size: int = CANVAS) -> Image.Image:
    s = SUPERSAMPLE
    big = CANVAS * s
    inset = (CANVAS - BODY) // 2 * s
    body = BODY * s

    art = gradient((body, body)).convert("RGBA")
    draw = ImageDraw.Draw(art)

    shelf_top = body * 0.76
    draw_shelf(draw, 0, body, shelf_top, body * 0.07)

    books = [  # (width, height, colour index) as shares of the body
        (0.105, 0.50, 0),
        (0.085, 0.44, 3),
        (0.12, 0.55, 2),
        (0.09, 0.47, 1),
        (0.11, 0.52, 4),
    ]
    x = body * 0.12
    for width, height, colour in books:
        x = place_spine(art, x, shelf_top, body * width, body * height, SPINES[colour]) + body * 0.012
    # The last volume leans on the others.
    place_spine(art, x - body * 0.012, shelf_top, body * 0.1, body * 0.5, SPINES[5], lean=16)

    mask = Image.new("L", (body, body), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, body - 1, body - 1), radius=CORNER * s, fill=255)

    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (inset, inset + 10 * s, inset + body, inset + body + 10 * s), radius=CORNER * s, fill=(0, 0, 0, 90))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14 * s)))
    canvas.paste(art, (inset, inset), mask)
    return canvas.resize((size, size), Image.LANCZOS)


def splash(width: int = 1280, height: int = 440, centre: float = 0.55) -> Image.Image:
    """A band across the bookshelf photograph, at the splash banner's proportions.

    `centre` is where the band sits, as a share of the photo's height: low
    enough to keep the titles on the spines, high enough to keep their tops.
    """
    photo = Image.open(PHOTO).convert("RGB")
    band = round(photo.width * height / width)
    top = min(max(0, round(photo.height * centre - band / 2)), photo.height - band)
    return photo.crop((0, top, photo.width, top + band)).resize((width, height), Image.LANCZOS)


def write_iconset() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = icon(CANVAS)
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            master.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name)
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (ICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    (ICONSET.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    master.save(PREVIEW)


if __name__ == "__main__":
    write_iconset()
    splash().save(SPLASH, quality=88, optimize=True)
    print(f"wrote {ICONSET.relative_to(ROOT)}, {SPLASH.relative_to(ROOT)}, {PREVIEW.relative_to(ROOT)}")
