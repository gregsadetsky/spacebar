#!/bin/bash
# end to end: build, install, generate samples, preview every sample through
# the real quick look extension and check the log line each one produces.
# also proves the offline rule with a probe plugin, in both directions.
set -uo pipefail
cd "$(dirname "$0")/.."
BLOCKING="${SMOKE_BLOCKING:-1}"   # ci sets 0: extension registration is flaky on runners
LOG=/usr/bin/log
CLI=Packages/SpacebarKit/.build/debug/spacebar-cli
APP="${INSTALL_DIR:-$HOME/Applications}/Spacebar.app"
PLUGINS="$HOME/Library/Containers/io.spacebar.app.QuickLook/Data/Library/Application Support/Spacebar/Plugins"
fail=0
pass() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

make build >/dev/null || { echo "build failed"; exit 1; }
make install >/dev/null || { echo "install failed"; exit 1; }
make samples >/dev/null || { echo "samples failed"; exit 1; }
[ -x "$CLI" ] || { echo "missing $CLI (make cli)"; exit 1; }
sleep 2

# the probe: outranks geojson for public.geojson files while installed
rm -rf "$PLUGINS/smoke-probe"
cp -R scripts/smoke-probe "$PLUGINS/smoke-probe"

preview() {  # <file> -> prints the "rendered ..." log line
  local start; start=$(date "+%Y-%m-%d %H:%M:%S")
  qlmanage -p "$1" >/dev/null 2>&1 & local pid=$!
  sleep "${SMOKE_WAIT:-4}"; kill $pid 2>/dev/null; wait $pid 2>/dev/null
  sleep 0.5
  $LOG show --info --start "$start" --predicate 'subsystem == "io.spacebar"' --style compact 2>/dev/null | grep -E "rendered|network check" | sed 's/.*extension\] //'
}
expect() {  # <file> <regex>
  local out; out=$(preview "$1")
  if echo "$out" | grep -Eq "$2"; then pass "$1: $(echo "$out" | grep -E "$2" | head -1)"; else bad "$1: wanted /$2/, got: ${out:-<nothing logged>}"; fi
}

echo "== offline probe (extension)"
expect samples/cities.geojson 'network check: blocked'
rm -rf "$PLUGINS/smoke-probe"

echo "== offline probe (app dev host, both directions)"
cp -R scripts/smoke-probe "$PLUGINS/smoke-probe"
on=$("$APP/Contents/MacOS/Spacebar" --dev samples/cities.geojson --plugin smoke-probe --snapshot /dev/null 2>&1 | grep -o "network check: [A-Za-z]*")
off=$(SPACEBAR_DEV_ALLOW_NETWORK=1 "$APP/Contents/MacOS/Spacebar" --dev samples/cities.geojson --plugin smoke-probe --snapshot /dev/null 2>&1 | grep -o "network check: [A-Za-z]*")
rm -rf "$PLUGINS/smoke-probe"
[ "$on" = "network check: blocked" ] && pass "rules on: $on" || bad "rules on: got '$on'"
[ "$off" = "network check: REACHABLE" ] && pass "rules off: $off (debug env, proves the block is ours)" || bad "rules off: got '$off' (no network on this machine?)"

echo "== fresh container: the extension copies bundled plugins itself"
rm -rf "$PLUGINS"
expect samples/cities.geojson  'plugin=geojson .* outcome=done'
[ -d "$PLUGINS/sqlite" ] && pass "plugins restored into the container by the extension" || bad "container has no plugins after a preview"

echo "== samples through the extension"
expect samples/cities.geojson  'plugin=geojson .* outcome=done'
expect samples/shapes.geojson  'plugin=geojson .* outcome=done'
expect samples/big.geojson     'plugin=geojson .* outcome=done'
expect samples/invalid.geojson 'plugin=geojson .* outcome=failed: Not valid GeoJSON'
expect samples/library.sqlite3 'plugin=sqlite .* outcome=done'
expect samples/wal.sqlite3     'plugin=sqlite .* outcome=done'
expect samples/notadb.sqlite3  'plugin=sqlite .* outcome=host error: not a SQLite database'
expect samples/preferences-xml.plist 'plugin=plist .* outcome=done'
expect samples/preferences-binary.plist 'plugin=plist .* outcome=done'
expect samples/preferences-openstep.plist 'plugin=plist .* outcome=done'
expect samples/archive.plist 'plugin=plist .* outcome=done'
expect samples/invalid.plist 'plugin=plist .* outcome=host error: could not preview property list'
expect samples/analysis.ipynb 'plugin=notebook .* outcome=done'
expect samples/large-notebook.ipynb 'plugin=notebook .* outcome=done'
expect samples/legacy-notebook.ipynb 'plugin=notebook .* outcome=done'
expect samples/empty.ipynb 'plugin=notebook .* outcome=done'
expect samples/untrusted-notebook.ipynb 'plugin=notebook .* outcome=done'
expect samples/invalid-notebook.ipynb 'plugin=notebook .* outcome=failed: Invalid notebook cell'
expect samples/guide.md 'plugin=markdown .* outcome=done'
expect samples/project.zip 'plugin=archive .* outcome=done'
expect samples/project.tar 'plugin=archive .* outcome=done'
expect samples/project.tar.gz 'plugin=archive .* outcome=done'
expect samples/project.7z 'plugin=archive .* outcome=done'
expect samples/project.rar 'plugin=archive .* outcome=done'
expect samples/invalid.zip 'plugin=archive .* outcome=host error:'
expect samples/field-notebook.epub 'plugin=epub .* outcome=done'
expect samples/invalid.epub 'plugin=epub .* outcome=host error:'
expect samples/dialogue.srt 'plugin=subtitles .* outcome=done'
expect samples/captions.vtt 'plugin=subtitles .* outcome=done'
expect samples/unicode.srt 'plugin=subtitles .* outcome=done'
expect samples/invalid.srt 'plugin=subtitles .* outcome=failed:'
expect samples/notadb.db       'plugin=sqlite ext=db .* outcome=host error: not a SQLite database'

echo "== matcher via cli"
if $CLI match samples/cities.geojson | grep -q "^geojson"; then pass "cli match geojson"; else bad "cli match geojson"; fi
if $CLI match samples/library.sqlite3 | grep -q "^sqlite"; then pass "cli match sqlite"; else bad "cli match sqlite"; fi
out=$($CLI match Makefile 2>&1); st=$?
if [ $st -eq 1 ] && echo "$out" | grep -q "^no plugin"; then pass "cli match Makefile: no plugin"; else bad "cli match Makefile: status $st, '$out'"; fi

if [ $fail = 0 ]; then echo "smoke: all good"; exit 0; fi
if [ "$BLOCKING" = "1" ]; then echo "smoke: failures"; exit 1; fi
echo "smoke: failures (non-blocking)"; exit 0
