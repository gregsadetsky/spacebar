#!/bin/bash
# render an svg (1024x1024 viewBox) into App/icon/AppIcon.icns using quick look's
# svg renderer. usage: scripts/svg-to-icns.sh App/icon/drafts/v4.svg
set -euo pipefail
svg="${1:?svg}"; out="${2:-App/icon/AppIcon.icns}"
tmp=$(mktemp -d); set=$tmp/AppIcon.iconset; mkdir -p "$set"
qlmanage -t -s 1024 -o "$tmp" "$svg" >/dev/null 2>&1
src="$tmp/$(basename "$svg").png"
[ -f "$src" ] || { echo "quick look could not render $svg"; exit 1; }
for px in 16 32 128 256 512; do
  sips -z $px $px "$src" --out "$set/icon_${px}x${px}.png" >/dev/null
  d=$((px * 2)); sips -z $d $d "$src" --out "$set/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o "$out" && echo "wrote $out from $svg"
rm -rf "$tmp"
