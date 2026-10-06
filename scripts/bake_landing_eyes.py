#!/usr/bin/env python3
"""Paints Nova's eyes onto the landing page's copies of the mascot art.

The app draws the eyes live (they follow the cursor and change with the
mood), so the source PNGs have an empty visor. The website can't run that
renderer, so this bakes a resting pair of eyes in, using the same geometry
as NovaCharacterRenderer / PoseGeometry.generated.swift.

    python3 scripts/bake_landing_eyes.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources/Nova/Resources"
OUT = ROOT / "landing/assets"

# (left, right, width, length, tilt°) in units of image width.
STANDARD = ((0.4233, 0.6194), (0.7172, 0.7063), 0.072, 0.18, 17)
POSES = {
    "idle": ((0.5940, 0.4815), (0.8199, 0.5300), 0.0573, 0.1433, 12.1),
    "happy": ((0.5138, 0.5185), (0.7300, 0.4134), 0.0596, 0.1490, -25.9),
    "thinking": ((0.5395, 0.5502), (0.7967, 0.5882), 0.0645, 0.1612, 8.4),
    "typing": ((0.4031, 0.5168), (0.5076, 0.4544), 0.0400, 0.1000, -30.9),
    "sleep": ((0.3754, 0.4131), (0.4738, 0.4581), 0.0400, 0.1000, 24.6),
    "alert": ((0.5999, 0.4340), (0.8333, 0.4206), 0.0580, 0.1450, -3.3),
    "dizzy": ((0.4492, 0.3773), (0.7027, 0.4264), 0.0640, 0.1601, 11.0),
    "success": ((0.5228, 0.4711), (0.7719, 0.5504), 0.0648, 0.1621, 17.6),
    "listening": ((0.5040, 0.4376), (0.6927, 0.4679), 0.0474, 0.1185, 9.1),
    "loading": ((0.6022, 0.5267), (0.8252, 0.5565), 0.0558, 0.1395, 7.6),
}
# Mood tint and openness, matching EyeParameters' resting shapes.
CYAN, MINT, AMBER, CORAL = (115, 219, 255), (115, 242, 199), (255, 199, 107), (255, 128, 128)
STYLE = {"sleep": (CYAN, 0.12), "dizzy": (CORAL, 0.8), "alert": (AMBER, 1.0), "success": (MINT, 0.85),
         "happy": (CYAN, 0.8), "typing": (CYAN, 0.8)}


def eye_layer(size, w, h, color):
    """One pill-shaped eye with a soft glow, centred in a square layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx = cy = size / 2
    box = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(box, radius=min(w, h) / 2, fill=color + (150,))
    layer = Image.alpha_composite(layer, glow.filter(ImageFilter.GaussianBlur(w * 0.45)))
    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    # Vertical gradient: lighter at the top, deeper at the bottom.
    top = tuple(min(255, int(c + (255 - c) * 0.45)) for c in color)
    bottom = (int(color[0] * 0.55 + 51 * 0.45), int(color[1] * 0.55 + 89 * 0.45), int(color[2] * 0.55 + 230 * 0.45))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=min(w, h) / 2, fill=255)
    for y in range(int(box[1]), int(box[3]) + 1):
        t = (y - box[1]) / max(h, 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c + (255,))
    body.putalpha(mask)
    layer = Image.alpha_composite(layer, body)
    if h > w * 0.9:   # small highlight near the top
        hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(hl).rounded_rectangle([cx - w * 0.18, cy - h / 2 + w * 0.18, cx + w * 0.18, cy - h / 2 + w * 0.40],
                                             radius=w * 0.11, fill=(255, 255, 255, 90))
        layer = Image.alpha_composite(layer, hl)
    return layer


def bake(src, dst, geometry, color=CYAN, openness=1.0):
    img = Image.open(src).convert("RGBA")
    unit = img.width
    left, right, width, length, tilt = geometry
    w = width * unit
    h = max(length * unit * openness, w * 0.2)
    size = int(max(w, h) * 3)
    for (x, y) in (left, right):
        eye = eye_layer(size, w, h, color).rotate(-tilt, resample=Image.BICUBIC)
        img.alpha_composite(eye, (int(x * unit - size / 2), int(y * unit - size / 2)))
    img.save(dst, optimize=True)


def main():
    for name in ("nova_head", "nova_body"):
        bake(SRC / "Mascot" / f"{name}.png", OUT / f"{name}.png", STANDARD)
    for pose, geometry in POSES.items():
        color, openness = STYLE.get(pose, (CYAN, 1.0))
        bake(SRC / "Poses" / f"pose_{pose}.png", OUT / "poses" / f"pose_{pose}.png", geometry, color, openness)
    print("Baked eyes into", OUT)


if __name__ == "__main__":
    main()
