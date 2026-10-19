#!/bin/bash
# render App/icon/AppIcon.svg (1024x1024 viewBox) into App/icon/AppIcon.icns and
# web/icon.png, keeping transparency outside the rounded rect.
# needs librsvg: brew install librsvg
# usage: scripts/svg-to-icns.sh [App/icon/AppIcon.svg] [App/icon/AppIcon.icns]
set -euo pipefail
svg="${1:-App/icon/AppIcon.svg}"; out="${2:-App/icon/AppIcon.icns}"
command -v rsvg-convert >/dev/null || { echo "rsvg-convert missing: brew install librsvg"; exit 1; }
tmp=$(mktemp -d); set=$tmp/AppIcon.iconset; mkdir -p "$set"
rsvg-convert -w 1024 -h 1024 --background-color=none "$svg" -o "$tmp/1024.png"
for px in 16 32 128 256 512; do
  rsvg-convert -w $px -h $px --background-color=none "$svg" -o "$set/icon_${px}x${px}.png"
  d=$((px * 2)); rsvg-convert -w $d -h $d --background-color=none "$svg" -o "$set/icon_${px}x${px}@2x.png"
done
iconutil -c icns "$set" -o "$out" && echo "wrote $out from $svg"
rsvg-convert -w 256 -h 256 --background-color=none "$svg" -o web/icon.png && echo "wrote web/icon.png"
rm -rf "$tmp"
