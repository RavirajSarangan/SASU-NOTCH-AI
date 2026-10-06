#!/usr/bin/env python3
"""One-off asset prep for Nova.

Takes the character sheet in Assets/source/nova_sheet.png, isolates the large
hero pose, erases the painted eyes from the visor (so the app can draw live
eyes), and writes:

  Sources/Nova/Resources/Mascot/nova_body.png   full hero, eyes removed
  Sources/Nova/Resources/Mascot/nova_head.png   head-only crop, eyes removed

Eye positions in the output images were measured once from the sheet and are
hard-coded in Character/NovaCharacterRenderer.swift (EyeGeometry).

Usage: python3 scripts/prepare_mascot.py
"""
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Assets/source/nova_sheet.png"
OUT = ROOT / "Sources/Nova/Resources/Mascot"

HERO_BOX = (0, 0, 600, 870)       # generous region containing the hero
SEED = (300, 400)                 # a point inside the hero (x, y), relative to HERO_BOX
VISOR_BOX = (110, 225, 490, 545)  # x0, y0, x1, y1 search area for eyes


def keep_connected(alpha: np.ndarray, seed: tuple[int, int], thresh: int = 8) -> np.ndarray:
    """Flood-fill from seed over alpha>thresh; returns a bool mask of the hero only."""
    h, w = alpha.shape
    solid = alpha > thresh
    seen = np.zeros_like(solid)
    q = deque([seed[::-1]])
    seen[seed[1], seed[0]] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
    img = Image.fromarray((mask * 255).astype(np.uint8))
    img = img.filter(ImageFilter.MaxFilter(2 * r + 1))
    return np.array(img) > 127


def erode(mask: np.ndarray, r: int) -> np.ndarray:
    return ~dilate(~mask, r)


def inpaint(rgb: np.ndarray, hole: np.ndarray, iters: int = 900) -> np.ndarray:
    """Diffusion inpainting: repeatedly replace hole pixels by neighbour mean."""
    out = rgb.copy()
    # seed holes with the darkest visor tone so convergence is quick
    known = ~hole
    out[hole] = np.median(out[dilate(hole, 6) & known], axis=0)
    for _ in range(iters):
        avg = (
            np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)
        ) / 4.0
        out[hole] = avg[hole]
    return out


def main() -> None:
    sheet = Image.open(SRC).convert("RGBA")
    hero = np.array(sheet.crop(HERO_BOX)).astype(np.float64)
    alpha = hero[:, :, 3].astype(np.uint8)

    hero_mask = keep_connected(alpha, SEED)
    hero[~hero_mask] = 0

    r, g, b = hero[:, :, 0], hero[:, :, 1], hero[:, :, 2]
    x0, y0, x1, y1 = VISOR_BOX
    region = np.zeros(alpha.shape, bool)
    region[y0:y1, x0:x1] = True

    # Visor interior: dark pixels, closed so the eye holes are filled in.
    dark = region & (r + g + b < 150) & hero_mask
    visor = erode(dilate(dark, 30), 30) & region
    inner = erode(visor, 8)

    # Core of the eyes: bright, blue-dominant pixels inside the visor.
    core = inner & (b > 150) & (b > r + 40)
    # Hole = eye cores plus the glow halo (blue-tinted pixels around them).
    glow = inner & (b > 30) & (b > r + 8) & dilate(core, 30)
    hole = dilate(core | glow, 4) & inner
    rgb = inpaint(hero[:, :, :3], hole)
    hero[:, :, :3] = rgb

    # Trim to the hero's bounding box.
    ys, xs = np.nonzero(hero_mask)
    bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    body = Image.fromarray(np.clip(hero, 0, 255).astype(np.uint8), "RGBA").crop((bx0, by0, bx1, by1))

    OUT.mkdir(parents=True, exist_ok=True)
    body.save(OUT / "nova_body.png", optimize=True)

    # Head: from top down to just under the collar gem.
    head_bottom = 560 - by0
    head = body.crop((0, 0, body.width, head_bottom))
    hb = head.getbbox()
    head = head.crop(hb)
    head.save(OUT / "nova_head.png", optimize=True)

    print(f"body {body.size} origin {(bx0, by0)}; head {head.size}")


if __name__ == "__main__":
    main()
