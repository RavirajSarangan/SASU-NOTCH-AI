#!/bin/zsh
# Renders Nova's real notch screens and puts web-ready copies in
# landing/assets/screens/. Debug build only (the exporter is #if DEBUG).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
swift build >/dev/null
NOVA_TEST_AUTODENY=1 .build/debug/Nova --landing-screens "$OUT" >/dev/null
mkdir -p landing/assets/screens
python3 - "$OUT" landing/assets/screens <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
pick = {
    "home-busy": "home", "home-dance": "dance", "notch-compact": "compact", "session": "session",
    "permission-low": "approval-diff", "permission-high": "approval-risk", "permission-question": "question",
    "voice-listening": "voice-listening", "voice-reply": "voice-reply", "brief": "brief",
}
for name, out in pick.items():
    im = Image.open(f"{src}/{name}.png").convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if box: im = im.crop(box)
    if im.width > 1280:
        im = im.resize((1280, round(im.height * 1280 / im.width)), Image.LANCZOS)
    im.save(f"{dst}/{out}.webp", "WEBP", quality=86, method=6)
    print(f"{out}.webp {im.size[0]}x{im.size[1]}")
PY
