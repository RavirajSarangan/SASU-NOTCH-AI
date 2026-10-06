#!/bin/zsh
# Records the landing-page videos from the real app (demo data, Nova's own
# window only) and encodes them for the web.
#   scripts/record_landing.sh            all clips
#   scripts/record_landing.sh hero voice  some clips
# Needs Screen Recording permission for Nova (asked on the first run).
set -euo pipefail
setopt null_glob
cd "$(dirname "$0")/.."

RAW="build/landing-video"
OUT="landing/assets/video"
mkdir -p "$RAW" "$OUT"

# The demo needs a debug build; the normal Nova is quit and relaunched afterwards.
scripts/build_app.sh debug >/dev/null
pkill -x Nova 2>/dev/null || true
sleep 1
rm -f "$RAW"/*.mov
# Launched through LaunchServices so macOS asks for (and remembers) Screen
# Recording for Nova itself, not for the terminal.
open -W -n build/Nova.app --args --record-demo "$PWD/$RAW" "$@" || true

if ! ls "$RAW"/*.mov >/dev/null 2>&1; then
  echo "No clips were recorded. Allow Screen Recording for Nova in System Settings → Privacy & Security → Screen & System Audio Recording, then run this again."
  scripts/build_app.sh >/dev/null && open build/Nova.app
  exit 1
fi

for mov in "$RAW"/*.mov; do
  name="${mov:t:r}"
  ffmpeg -loglevel error -y -i "$mov" -vf "fps=30,scale=1280:-2:flags=lanczos" -c:v libx264 -profile:v high -crf 23 -preset slow \
    -pix_fmt yuv420p -movflags +faststart -an "$OUT/$name.mp4"
  ffmpeg -loglevel error -y -i "$mov" -vf "fps=30,scale=1280:-2:flags=lanczos" -c:v libvpx-vp9 -crf 36 -b:v 0 -row-mt 1 -an "$OUT/$name.webm"
  # Poster: the clip's most telling moment (shown before it plays, and with reduced motion).
  case "$name" in hero) at=7.5;; approval) at=4;; voice) at=2.6;; *) at=4;; esac
  ffmpeg -loglevel error -y -ss "$at" -i "$OUT/$name.mp4" -frames:v 1 "$RAW/$name.png"
  cwebp -quiet -q 82 "$RAW/$name.png" -o "$OUT/$name.webp"
  echo "$name: $(du -h "$OUT/$name.mp4" | cut -f1) mp4, $(du -h "$OUT/$name.webm" | cut -f1) webm"
done

# Back to the normal app.
scripts/build_app.sh >/dev/null
open build/Nova.app
