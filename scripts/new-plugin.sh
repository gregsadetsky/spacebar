#!/bin/bash
# scaffold a plugin that works right away:  scripts/new-plugin.sh <id> <ext> [input]
#   id     folder + plugin id, [a-z0-9-]
#   ext    file extension it previews, no dot
#   input  text (default) | bytes | json | plist | sqlite
# the host only previews extensions it was built with; see Extension/Info.plist.
set -euo pipefail
id="${1:?id}"; ext="${2:?extension}"; input="${3:-text}"
dir="plugins/$id"
[ -e "$dir" ] && { echo "$dir exists"; exit 1; }
# the host only previews utis listed in Extension/Info.plist. extensions macos
# doesn't know are declared by the app as io.spacebar.<ext>; system types
# (gpx, geojson, ...) keep their own uti. match on the uti when we know it.
utis=""
if grep -q "<string>io.spacebar.$ext</string>" Extension/Info.plist; then utis=", \"utis\": [\"io.spacebar.$ext\"]"
elif ! grep -q "$ext" Extension/Info.plist App/Info.plist; then
  echo "warning: .$ext is not in Extension/Info.plist (QLSupportedContentTypes); the extension will never be asked to preview it"
fi
mkdir -p "$dir"
cat > "$dir/plugin.json" <<JSON
{
  "id": "$id",
  "name": "$id",
  "version": "0.1.0",
  "matches": { "extensions": ["$ext"]$utis },
  "input": "$input",
  "maxFileSize": 10485760,
  "entry": "index.html"
}
JSON
cat > "$dir/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    :root { --fg: #1d1d1f; --bg: #fff; --muted: #6e6e73; }
    @media (prefers-color-scheme: dark) { :root { --fg: #f2f2f2; --bg: #1e1e1e; --muted: #9a9a9e; } }
    body { margin: 0; padding: 16px; font: 13px/1.5 -apple-system, sans-serif; color: var(--fg); background: var(--bg); }
    h1 { font-size: 15px; margin: 0 0 8px; }
    pre { white-space: pre-wrap; word-break: break-word; font: 12px/1.5 ui-monospace, Menlo, monospace; }
    .muted { color: var(--muted); }
  </style>
</head>
<body>
  <h1 id="title"></h1>
  <p class="muted" id="meta"></p>
  <pre id="out"></pre>
  <script src="index.js"></script>
</body>
</html>
HTML
cat > "$dir/index.js" <<'JS'
// everything the host gives you is on window.spacebar. call done() when rendered.
(function () {
  var sb = window.spacebar;
  try {
    document.getElementById("title").textContent = sb.file.name;
    document.getElementById("meta").textContent = sb.file.size + " bytes · " + sb.input + " · " + sb.theme;
    var data = sb.data;
    if (sb.input === "text") data = data.slice(0, 20000);
    else data = JSON.stringify(data, null, 2).slice(0, 20000);
    document.getElementById("out").textContent = data;
    sb.done();
  } catch (e) {
    sb.fail(String(e));
  }
})();
JS
echo "created $dir"
echo "try it:   build/Spacebar.app/Contents/MacOS/Spacebar --dev some.$ext --plugin $id"
echo "or:       open the app, Window > Dev Harness, pick $id and a file"
echo "ship it:  make install   (opens the app once; that launch copies bundled plugins into place)"
