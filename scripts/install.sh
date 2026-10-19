#!/bin/bash
# installs build/Spacebar.app into ~/Applications (or $INSTALL_DIR) and makes
# sure the quick look extension is registered + enabled. verifies, retries once.
set -euo pipefail

APP_NAME=Spacebar
EXT_NAME=SpacebarQuickLook
EXT_ID=io.spacebar.app.QuickLook
SRC="${1:-build/$APP_NAME.app}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST="$INSTALL_DIR/$APP_NAME.app"
APPEX="$DEST/Contents/PlugIns/$EXT_NAME.appex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$SRC" ] || { echo "no build at $SRC, run make build"; exit 1; }
mkdir -p "$INSTALL_DIR"

# quit the running app and forget the old extension before touching files;
# pkd otherwise notices the deletion later and drops our fresh registration.
pkill -x "$APP_NAME" 2>/dev/null || true
if [ -d "$APPEX" ]; then pluginkit -r "$APPEX" 2>/dev/null || true; fi
sleep 1
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

"$LSREGISTER" -f "$DEST"
for attempt in 1 2 3; do
  pluginkit -a "$APPEX" || true
  sleep 1
  if pluginkit -m -i "$EXT_ID" 2>/dev/null | grep -q "$EXT_ID"; then break; fi
  echo "extension not registered yet (attempt $attempt)"; sleep 2
done
pluginkit -e use -i "$EXT_ID" 2>/dev/null \
  || echo "could not enable via pluginkit; enable in System Settings > General > Login Items & Extensions > Quick Look"

state=$(pluginkit -m -i "$EXT_ID" 2>/dev/null | head -1)
case "$state" in
  "+"*) echo "extension registered and enabled" ;;
  "-"*) echo "extension registered but DISABLED; enable it in System Settings > General > Login Items & Extensions > Quick Look"; exit 1 ;;
  *)    echo "extension NOT registered: '$state'"; exit 1 ;;
esac

open "$DEST"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
echo "installed to $DEST"
