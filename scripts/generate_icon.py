#!/usr/bin/env python3
"""Generate the TinyTodo app icon set with Pillow.

Usage: python3 scripts/generate_icon.py
Writes PNGs into TinyTodo/Resources/Assets.xcassets/AppIcon.appiconset/
"""
import json
import math
import pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "TinyTodo/Resources/Assets.xcassets/AppIcon.appiconset"
MASTER = 1024


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def make_master():
    size = MASTER
    gradient = Image.new("RGBA", (size, size))
    top = (108, 132, 255)       # indigo
    bottom = (66, 92, 224)      # deep blue
    px = gradient.load()
    for y in range(size):
        color = lerp(top, bottom, y / (size - 1))
        for x in range(size):
            px[x, y] = (*color, 255)

    # Soft diagonal highlight.
    highlight = Image.new("L", (size, size), 0)
    hd = ImageDraw.Draw(highlight)
    hd.ellipse([-size * 0.35, -size * 0.75, size * 1.15, size * 0.45], fill=70)
    gradient = Image.composite(Image.new("RGBA", (size, size), (255, 255, 255, 255)), gradient, highlight)

    mask = rounded_mask(size, round(size * 0.22))
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(gradient, (0, 0), mask)

    draw = ImageDraw.Draw(icon)
    # Checkmark with a small task list hint.
    stroke = round(size * 0.085)
    points = [(size * 0.28, size * 0.53), (size * 0.44, size * 0.69), (size * 0.73, size * 0.35)]
    draw.line(points, fill=(255, 255, 255, 255), width=stroke, joint="curve")
    for point in points:
        r = stroke / 2
        draw.ellipse([point[0] - r, point[1] - r, point[0] + r, point[1] + r], fill=(255, 255, 255, 255))

    # Inner border for depth.
    border = ImageDraw.Draw(icon)
    border.rounded_rectangle([2, 2, size - 3, size - 3], radius=round(size * 0.22), outline=(255, 255, 255, 46), width=3)
    return icon


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    master = make_master()
    master.save(OUT / "icon_1024.png")

    images = [
        ("icon_16.png", 16, "16x16", "1x"),
        ("icon_32.png", 32, "16x16", "2x"),
        ("icon_32.png", 32, "32x32", "1x"),
        ("icon_64.png", 64, "32x32", "2x"),
        ("icon_128.png", 128, "128x128", "1x"),
        ("icon_256.png", 256, "128x128", "2x"),
        ("icon_256b.png", 256, "256x256", "1x"),
        ("icon_512.png", 512, "256x256", "2x"),
        ("icon_512b.png", 512, "512x512", "1x"),
        ("icon_1024.png", 1024, "512x512", "2x"),
    ]
    seen = set()
    contents = []
    for filename, pixels, size_spec, scale in images:
        if filename not in seen:
            resized = master.resize((pixels, pixels), Image.LANCZOS)
            resized.save(OUT / filename)
            seen.add(filename)
        contents.append({"filename": filename, "idiom": "mac", "scale": scale, "size": size_spec})

    (OUT / "Contents.json").write_text(json.dumps({"images": contents, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print(f"wrote {len(contents)} icon entries to {OUT}")


if __name__ == "__main__":
    main()
