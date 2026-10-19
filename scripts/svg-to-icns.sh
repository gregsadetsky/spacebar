#!/bin/bash
# App/icon/AppIcon.svg -> App/icon/AppIcon.icns + web/icon.png, transparent
# outside the rounded rect. WebKit renders the svg (quick look and librsvg
# both get it wrong), twice: over black and over white. the difference gives
# the alpha channel exactly. needs imagemagick (brew install imagemagick).
# usage: scripts/svg-to-icns.sh [App/icon/AppIcon.svg] [App/icon/AppIcon.icns]
set -euo pipefail
svg="${1:-App/icon/AppIcon.svg}"; out="${2:-App/icon/AppIcon.icns}"
command -v magick >/dev/null || { echo "magick missing: brew install imagemagick"; exit 1; }
mkdir -p build
[ -x build/svg-render ] && [ build/svg-render -nt scripts/svg-render.swift ] || swiftc -O scripts/svg-render.swift -o build/svg-render 2>&1 | grep -v warning || true
tmp=$(mktemp -d); set=$tmp/AppIcon.iconset; mkdir -p "$set"
cp "$svg" "$tmp/icon.svg"
build/svg-render "$tmp/icon.svg" black "$tmp/black.png" >/dev/null
build/svg-render "$tmp/icon.svg" white "$tmp/white.png" >/dev/null
magick "$tmp/white.png" "$tmp/black.png" -alpha off -compose difference -composite -colorspace gray -negate "$tmp/alpha.png"
magick "$tmp/black.png" -alpha off "$tmp/alpha.png" -compose CopyOpacity -composite -resize 1024x1024 "$tmp/1024.png"
for px in 16 32 128 256 512; do
  magick "$tmp/1024.png" -resize ${px}x${px} "$set/icon_${px}x${px}.png"
  d=$((px * 2)); magick "$tmp/1024.png" -resize ${d}x${d} "$set/icon_${px}x${px}@2x.png"
done
iconutil -c icns "$set" -o "$out" && echo "wrote $out from $svg"
magick "$tmp/1024.png" -resize 256x256 web/icon.png && echo "wrote web/icon.png"
rm -rf "$tmp"
