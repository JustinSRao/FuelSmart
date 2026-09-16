#!/usr/bin/env python3
"""Generate the FuelSmart app icon and asset catalog.

    python Scripts/generate_appicon.py

The mark is two cost trajectories meeting at a break-even point — the mark *is*
the chart, which is the one moment the whole product exists to find. It is drawn
from the same geometry as the in-app `BrandMark` view, at the proportions the
design reference specifies for the 1024 px App Store icon:

    ground     linear gradient #242636 → #14161f at 160°
    neutral    stroke at −24°, the vehicle that starts ahead
    accent     stroke at +22°, the vehicle that starts behind and catches up
    dot        the crossing, in accent-200, with the product's only glow

Generated rather than hand-drawn so the icon cannot drift away from the brand
mark in the app, and so it can be regenerated at any size.

Requires Pillow (development only — it is not an app dependency, and nothing in
the shipped product imports it).
"""

from __future__ import annotations

import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ASSETS = os.path.join(REPO, "App", "FuelSmart", "Resources", "Assets.xcassets")

# Nocturne tokens, as hex, matching DesignSystem/Theme.swift.
GRADIENT_TOP = (0x24, 0x26, 0x36)
GRADIENT_BOTTOM = (0x14, 0x16, 0x1F)
NEUTRAL_500 = (0x93, 0x97, 0xAB)
ACCENT = (0x91, 0x84, 0xD9)
ACCENT_200 = (0xE7, 0xE5, 0xFE)

# Proportions taken from the design reference's 180 px master.
MASTER = 180.0
STROKE_INSET = 28 / MASTER
STROKE_HEIGHT = 5 / MASTER
NEUTRAL_TOP = 112 / MASTER
ACCENT_TOP = 62 / MASTER
DOT_CENTRE = 93 / MASTER
DOT_SIZE = 22 / MASTER


def gradient_background(size: int) -> Image.Image:
    """A 160° linear gradient, approximated along the diagonal."""
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    angle = math.radians(160)
    dx, dy = math.cos(angle), math.sin(angle)

    # Project each pixel onto the gradient axis and normalise to 0...1.
    extent = abs(dx) * size + abs(dy) * size
    for y in range(size):
        for x in range(size):
            t = ((x * dx + y * dy) + extent / 2) / extent
            # The reference stops the gradient at 70%.
            t = min(max(t / 0.7, 0.0), 1.0)
            pixels[x, y] = tuple(
                int(GRADIENT_TOP[i] + (GRADIENT_BOTTOM[i] - GRADIENT_TOP[i]) * t)
                for i in range(3)
            )
    return image


def stroke_layer(size: int, top: float, angle: float, colour: tuple[int, int, int]) -> Image.Image:
    """One rotated capsule stroke on its own transparent layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    inset = STROKE_INSET * size
    height = STROKE_HEIGHT * size
    y = top * size

    draw.rounded_rectangle(
        [inset, y, size - inset, y + height],
        radius=height / 2,
        fill=colour + (255,),
    )
    # Rotate about the centre so both strokes cross where the dot sits.
    return layer.rotate(-angle, resample=Image.BICUBIC, center=(size / 2, size / 2))


def render(size: int) -> Image.Image:
    """The full mark at a given pixel size."""
    canvas = gradient_background(size).convert("RGBA")

    # Neutral stroke: starts ahead, rises gently.
    canvas = Image.alpha_composite(canvas, stroke_layer(size, NEUTRAL_TOP, -24, NEUTRAL_500))

    # Accent stroke, with the glow that only ever appears on the dark ground.
    accent = stroke_layer(size, ACCENT_TOP, 22, ACCENT)
    glow = accent.filter(ImageFilter.GaussianBlur(size * 0.03))
    canvas = Image.alpha_composite(canvas, glow)
    canvas = Image.alpha_composite(canvas, accent)

    # The crossing.
    dot = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    radius = DOT_SIZE * size / 2
    centre = DOT_CENTRE * size
    ImageDraw.Draw(dot).ellipse(
        [centre - radius, centre - radius, centre + radius, centre + radius],
        fill=ACCENT_200 + (255,),
    )
    dot_glow = dot.filter(ImageFilter.GaussianBlur(size * 0.045))
    canvas = Image.alpha_composite(canvas, dot_glow)
    canvas = Image.alpha_composite(canvas, dot)

    # App icons must be fully opaque with square corners: the system applies the
    # mask. A transparent or pre-rounded icon is rejected at upload.
    return canvas.convert("RGB")


def write_catalog() -> None:
    icon_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    # One 1024 px universal image covers iOS 17+; macOS still wants its own set.
    master = render(1024)
    master.save(os.path.join(icon_dir, "icon-1024.png"))

    images = [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}]

    mac_sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    for points, scale in mac_sizes:
        pixels = points * scale
        name = f"icon-mac-{points}x{points}@{scale}x.png"
        render(pixels).save(os.path.join(icon_dir, name))
        images.append({
            "filename": name,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{points}x{points}",
        })

    with open(os.path.join(icon_dir, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, handle, indent=2)

    # The tint the system applies to controls, matching the Nocturne accent.
    accent_dir = os.path.join(ASSETS, "AccentColor.colorset")
    os.makedirs(accent_dir, exist_ok=True)
    with open(os.path.join(accent_dir, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump({
            "colors": [
                {
                    "idiom": "universal",
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "blue": "0xD9", "green": "0x84", "red": "0x91"},
                    },
                },
                {
                    # On a light ground the accent drops a step to hold 4.5:1.
                    "idiom": "universal",
                    "appearances": [{"appearance": "luminosity", "value": "light"}],
                    "color": {
                        "color-space": "srgb",
                        "components": {"alpha": "1.000", "blue": "0xBF", "green": "0x6C", "red": "0x79"},
                    },
                },
            ],
            "info": {"author": "xcode", "version": 1},
        }, handle, indent=2)

    with open(os.path.join(ASSETS, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump({"info": {"author": "xcode", "version": 1}}, handle, indent=2)


if __name__ == "__main__":
    write_catalog()
    total = sum(
        os.path.getsize(os.path.join(root, name))
        for root, _, names in os.walk(ASSETS) for name in names
    )
    print(f"wrote {ASSETS}")
    print(f"  {sum(len(n) for _, _, n in os.walk(ASSETS))} files, {total:,} bytes")
