#!/usr/bin/env python3
"""Cut Nova's 10 poses out of Assets/source/nova_poses.png.

For each card: un-blend the character from the dark card background, keep the
body (dropping the floating effects, which Nova draws live), fill the visor,
erase the painted eyes and measure where they were.

Writes:
  Sources/Nova/Resources/Poses/pose_<name>.png
  Sources/Nova/Character/PoseGeometry.generated.swift

Usage: python3 scripts/prepare_poses.py
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets/source/nova_poses.png"
OUT = ROOT / "Sources/Nova/Resources/Poses"
SWIFT = ROOT / "Sources/Nova/Character/PoseGeometry.generated.swift"

# (name, x, y, w, h) of the art area of each card (labels excluded).
CARDS = [
    ("idle", 12, 15, 300, 210), ("happy", 340, 15, 300, 210), ("thinking", 662, 15, 300, 210),
    ("typing", 975, 15, 300, 210), ("sleep", 1295, 15, 289, 210),
    ("alert", 12, 298, 300, 202), ("dizzy", 340, 298, 300, 202), ("success", 662, 298, 300, 202),
    ("listening", 975, 298, 300, 202), ("loading", 1295, 298, 289, 202),
]
SCALE = 2


def components(mask: np.ndarray) -> list[np.ndarray]:
    """4-connected components, largest first."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    comps = []
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        pts = []
        q = deque([(sy, sx)])
        seen[sy, sx] = True
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        comp = np.zeros_like(mask)
        ys, xs = zip(*pts)
        comp[list(ys), list(xs)] = True
        comps.append(comp)
    comps.sort(key=lambda c: -c.sum())
    return comps


def fill_holes(mask: np.ndarray, floor: bool = False) -> np.ndarray:
    """Regions not reachable from the border through ~mask. With `floor`, the
    bottom edge counts as a wall (for poses lying on the ground)."""
    outside = np.zeros_like(mask)
    h, w = mask.shape
    q = deque()
    for y in range(h - 1 if floor else h):
        for x in (0, w - 1):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    for x in range(w):
        for y in ((0,) if floor else (0, h - 1)):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not mask[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True; q.append((ny, nx))
    return ~outside


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    img = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * r + 1))
    return np.array(img) > 127


def erode(mask: np.ndarray, r: int) -> np.ndarray:
    return ~dilate(~mask, r)


def inpaint(rgb: np.ndarray, hole: np.ndarray, iters: int = 600) -> np.ndarray:
    out = rgb.copy()
    known = dilate(hole, 4) & ~hole
    if known.any():
        out[hole] = np.median(out[known], axis=0)
    for _ in range(iters):
        avg = (np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 4.0
        out[hole] = avg[hole]
    return out


def process(sheet: np.ndarray, name: str, x: int, y: int, w: int, h: int):
    card = sheet[y:y + h, x:x + w, :3].astype(np.float64)
    r, g, b = card[..., 0], card[..., 1], card[..., 2]
    lum = card.mean(axis=2)

    # Card background tone from the darkest decile.
    bg = np.percentile(card.reshape(-1, 3), 8, axis=0)

    # Pick the body with a strict mask (so glow halos don't bridge it to the
    # floating effects), then grow back into the looser mask for soft edges.
    fg = (lum > 75) | ((b > 105) & (b - r > 30))
    core = components(erode(fg & (lum > 60), 2))[0]
    body = components(fg & dilate(core, 8))[0]
    body = erode(dilate(body, 2), 2)          # close pinholes
    # A harsher core breaks thin glow bridges to floating effects. Used only
    # to trim the final silhouette, never to find the visor (the visor needs
    # the full outline to read as enclosed).
    harsh = components(erode(fg & (lum > 60), 3))[0]
    # Close the outline first so a visor touching the floor (sleep) still counts as enclosed.
    floor = name == "sleep"
    closed = erode(dilate(body, 7), 7)
    if floor:
        closed[-1, :] = closed[-1, :] | dilate(body, 12)[-1, :]
    visor_and_body = fill_holes(closed, floor=floor) | body
    visor = visor_and_body & ~body
    visor = erode(dilate(visor, 3), 3) & visor_and_body
    solid = visor_and_body & (dilate(harsh, 10) | dilate(visor, 4))
    solid = components(solid)[0]

    # Eyes: bright blue islands inside the visor (excluding its rim).
    inner = erode(visor_and_body, 6) & (dilate(visor, 2))
    eye_core = inner & (b > 120) & (b - r > 25) & (lum > 70)
    eye_glow = inner & dilate(eye_core, 5) & (b > 45) & (b - r > 10)
    hole = dilate(eye_core | eye_glow, 2) & inner

    eyes = [c for c in components(eye_core) if c.sum() > 12][:2]
    eyes.sort(key=lambda c: np.nonzero(c)[1].mean())

    rgb = inpaint(card, hole)

    # Alpha: opaque inside the silhouette, un-blended over the background
    # on the soft glow fringe just outside it.
    fringe = dilate(solid, 2) & ~solid
    lifted = np.clip(rgb - bg, 0, None)
    soft = np.clip(lifted.max(axis=2) / 140.0, 0, 1)
    alpha = np.where(solid, 1.0, np.where(fringe, soft, 0.0))
    color = np.where(fringe[..., None], np.clip(lifted / np.maximum(soft[..., None], 1e-3), 0, 255), rgb)
    alpha = np.array(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))) / 255.0
    alpha = np.minimum(alpha, dilate(solid, 2))

    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    bbox = img.getbbox()
    img = img.crop(bbox)
    ox, oy = bbox[0], bbox[1]
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"pose_{name}.png", optimize=True)

    # Geometry in units of output width (pre-scale coordinates / crop width).
    cw = bbox[2] - bbox[0]
    vys, vxs = np.nonzero(visor)
    visor_h = (vys.max() - vys.min()) if len(vys) else 40
    eye_specs = []
    for e in eyes:
        ys, xs = np.nonzero(e)
        eye_specs.append(((xs.mean() - ox) / cw, (ys.mean() - oy) / cw))
    if len(eye_specs) < 2 and len(vxs):
        # Fall back to the visor's thirds.
        cx, cy, vw = vxs.mean(), vys.mean(), vxs.max() - vxs.min()
        eye_specs = [((cx - vw * 0.2 - ox) / cw, (cy - oy) / cw), ((cx + vw * 0.2 - ox) / cw, (cy - oy) / cw)]
    (lx, ly), (rx, ry) = eye_specs[:2]
    # Same eye-length : eye-spacing ratio as the hero art (0.19 / 0.294).
    spacing = float(np.hypot(rx - lx, ry - ly))
    length = max(spacing * 0.62, 0.1)
    tilt = float(np.degrees(np.arctan2(ry - ly, rx - lx)))
    return {
        "name": name, "aspect": img.height / img.width,
        "left": (lx, ly), "right": (rx, ry), "length": length, "width": length * 0.4, "tilt": tilt,
        "eyes_found": len(eyes),
    }


SWIFT_TEMPLATE = """// Generated by scripts/prepare_poses.py. Do not edit by hand.
import SwiftUI

extension NovaPose {{
    var aspect: CGFloat {{
        switch self {{
{aspects}
        }}
    }}

    var eyes: EyeGeometry {{
        switch self {{
{eyes}
        }}
    }}
}}
"""


def main() -> None:
    sheet = np.array(Image.open(SRC).convert("RGBA"))
    results = [process(sheet, *card) for card in CARDS]
    aspects, eyes = [], []
    for r in results:
        aspects.append(f"        case .{r['name']}: {r['aspect']:.4f}")
        eyes.append(
            f"        case .{r['name']}: EyeGeometry(left: CGPoint(x: {r['left'][0]:.4f}, y: {r['left'][1]:.4f}), "
            f"right: CGPoint(x: {r['right'][0]:.4f}, y: {r['right'][1]:.4f}), width: {r['width']:.4f}, "
            f"length: {r['length']:.4f}, tilt: .degrees({r['tilt']:.1f}))"
        )
        print(f"{r['name']:>10}: eyes found {r['eyes_found']}, aspect {r['aspect']:.3f}, tilt {r['tilt']:.1f}")
    SWIFT.write_text(SWIFT_TEMPLATE.format(aspects="\n".join(aspects), eyes="\n".join(eyes)))


if __name__ == "__main__":
    main()
