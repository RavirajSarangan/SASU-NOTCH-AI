#!/usr/bin/env python3
"""Builds Assets/AppIcon.icns from Nova's head art.

Dark rounded-square plate (macOS icon grid: 824 px body on a 1024 canvas),
soft top light, subtle cyan rim, and the head centered.
Usage: python3 scripts/make_icon.py
"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
HEAD = ROOT / "Sources/Nova/Resources/Mascot/nova_head.png"
ICONSET = ROOT / "build/AppIcon.iconset"
OUT = ROOT / "Assets/AppIcon.icns"

SIZE, BODY, RADIUS = 1024, 824, 185


def plate() -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    inset = (SIZE - BODY) // 2
    box = (inset, inset, inset + BODY, inset + BODY)

    # Drop shadow.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 14, box[2], box[3] + 14), RADIUS, fill=(0, 0, 0, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))

    # Vertical gradient body.
    gradient = Image.new("RGBA", (SIZE, SIZE))
    top, bottom = (28, 32, 48), (9, 10, 16)
    for y in range(SIZE):
        t = min(max((y - inset) / BODY, 0), 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        ImageDraw.Draw(gradient).line([(0, y), (SIZE, y)], fill=color)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, RADIUS, fill=255)
    canvas.paste(gradient, (0, 0), mask)

    # Soft cyan glow behind the head.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((300, 330, 724, 730), fill=(83, 231, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    clipped = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    clipped.paste(glow, (0, 0), mask)
    canvas.alpha_composite(clipped)

    # Rim: thin cyan-to-violet hairline.
    rim = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(box, RADIUS, outline=(120, 200, 255, 120), width=4)
    canvas.alpha_composite(rim)
    return canvas


def paint_eyes(head: Image.Image) -> None:
    """The art's eyes are erased (Nova draws them live), so paint the idle
    eyes for the icon, matching Character/EyeGeometry (units of image width)."""
    unit = head.width
    w, h = int(0.072 * unit), int(0.18 * unit)
    for cx, cy in ((0.4233, 0.6194), (0.7172, 0.7063)):
        pill = Image.new("RGBA", (w * 4, h * 2), (0, 0, 0, 0))
        draw = ImageDraw.Draw(pill)
        x0, y0 = (pill.width - w) // 2, (pill.height - h) // 2
        for i in range(h):  # vertical gradient: light cyan → blue
            t = i / h
            color = (int(170 - 90 * t), int(235 - 95 * t), 255, 255)
            draw.line([(x0, y0 + i), (x0 + w, y0 + i)], fill=color)
        mask = Image.new("L", pill.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x0 + w, y0 + h), w // 2, fill=255)
        shape = Image.new("RGBA", pill.size, (0, 0, 0, 0))
        shape.paste(pill, (0, 0), mask)
        glow = Image.new("RGBA", pill.size, (0, 0, 0, 0))
        glow.paste((115, 220, 255, 150), (0, 0), mask)
        glow = glow.filter(ImageFilter.GaussianBlur(w * 0.45))
        layer = Image.alpha_composite(glow, shape).rotate(-17, resample=Image.BICUBIC, expand=False)
        head.alpha_composite(layer, (int(cx * unit - layer.width / 2), int(cy * unit - layer.height / 2)))


def main() -> None:
    icon = plate()
    head = Image.open(HEAD).convert("RGBA")
    paint_eyes(head)
    # Fade the bottom edge (where the body was cut off) into the plate.
    alpha = head.getchannel("A")
    fade = Image.new("L", head.size, 255)
    span = 110
    for i in range(span):
        ImageDraw.Draw(fade).line([(0, head.height - span + i), (head.width, head.height - span + i)], fill=int(255 * (1 - i / span)))
    head.putalpha(Image.fromarray(__import__("numpy").minimum(__import__("numpy").array(alpha), __import__("numpy").array(fade))))
    width = 600
    head = head.resize((width, int(head.height * width / head.width)), Image.LANCZOS)
    icon.alpha_composite(head, ((SIZE - head.width) // 2, (SIZE - head.height) // 2 + 30))

    ICONSET.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(OUT)], check=True)
    icon.save(ROOT / "build/AppIcon-preview.png")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
