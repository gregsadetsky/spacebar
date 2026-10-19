#!/bin/bash
# checks every plugins/*/plugin.json: parses, required keys, entry exists,
# extensions lowercase without dots, no http(s):// strings in first-party code.
# Vendored libraries contain inert URL constants; runtime network blocking is
# enforced by the host. See tools/notebook for bundle tests and provenance.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."
fail=0
for dir in plugins/*/; do
  id=$(basename "$dir")
  m="$dir/plugin.json"
  if [ ! -f "$m" ]; then echo "FAIL $id: no plugin.json"; fail=1; continue; fi
  if ! jq -e . "$m" >/dev/null 2>&1; then echo "FAIL $id: plugin.json is not valid json"; fail=1; continue; fi
  for key in id name version matches input; do
    if [ "$(jq -r "has(\"$key\")" "$m")" != "true" ]; then echo "FAIL $id: missing \"$key\""; fail=1; fi
  done
  if [ "$(jq -r .id "$m")" != "$id" ]; then echo "FAIL $id: id \"$(jq -r .id "$m")\" does not match folder name"; fail=1; fi
  if ! jq -r .version "$m" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then echo "FAIL $id: version is not x.y.z"; fail=1; fi
  if ! jq -r .input "$m" | grep -Eq '^(text|bytes|json|plist|sqlite|archive|epub)$'; then echo "FAIL $id: input must be text|bytes|json|plist|sqlite|archive|epub"; fail=1; fi
  entry=$(jq -r '.entry // "index.html"' "$m")
  if [ ! -f "$dir/$entry" ]; then echo "FAIL $id: entry \"$entry\" does not exist"; fail=1; fi
  if jq -r '.matches.extensions // [] | .[]' "$m" | grep -Eqv '^[a-z0-9]+$'; then echo "FAIL $id: extensions must be lowercase, no dot"; fail=1; fi
  if [ "$(jq -r '(.matches.extensions // [] | length) + (.matches.utis // [] | length)' "$m")" = "0" ]; then echo "FAIL $id: matches is empty"; fail=1; fi
  # urls in code are a bug (plugins are offline); urls in // or /* comments are fine
  hits=$(find "$dir" \( -path 'plugins/notebook/vendor' -o -path 'plugins/markdown/vendor' -o -path 'plugins/archive/vendor' -o -path 'plugins/epub/vendor' -o -path 'plugins/subtitles/vendor' \) -prune -o -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' \) -exec grep -HnE 'https?://' {} + 2>/dev/null \
         | grep -vE '^[^:]+:[0-9]+:\s*(//|/\*|\*|<!--)' | grep -vE 'https?://www\.w3\.org/' || true)
  if [ -n "$hits" ]; then
    echo "$hits"; echo "FAIL $id: http(s):// url found in code above (plugins are offline)"; fail=1
  fi
  [ $fail = 0 ] && echo "ok   $id"
done
exit $fail
