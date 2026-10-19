# writing a plugin

## the short loop

```
scripts/new-plugin.sh toml toml        # plugins/toml/ with a working plugin.json + index.html + index.js
make build                              # or make install
build/Spacebar.app/Contents/MacOS/Spacebar --dev some.toml --plugin toml --snapshot out.png
```

edit `plugins/toml/index.js`, rerun. or open the app, window → dev harness
(⇧⌘D), pick the plugin and a file, ⌘R reloads, the console on the right
shows `spacebar.log()` and `console.log()` output and the outcome
(done / fail / timed out). `make install` copies bundled plugins into place;
after that, space in finder uses the new code (no restart needed).

no mac tooling at all: `make samples && python3 -m http.server 8000`, then
`http://localhost:8000/harness/?plugin=toml&sample=some.toml` runs the plugin
in an iframe with a fake `window.spacebar`.

`make test` validates every plugin folder (manifest keys, entry exists, no
http urls in code). `make smoke` runs the bundled samples through the real
quick look extension.

## the folder

a plugin is a folder:

```
myplugin/
  plugin.json
  index.html
  index.js        # optional, whatever index.html loads
  style.css
  vendor/         # optional libs, bundled; there is no network
```

install it with "install from folder…" in the app, or drop it into the
plugins folder ("open plugins folder" in the app). folder name = `id`.

## plugin.json

```json
{
  "id": "geojson",
  "name": "GeoJSON",
  "version": "0.1.0",
  "matches": { "extensions": ["geojson"], "utis": ["public.geojson"] },
  "input": "text",
  "maxFileSize": 52428800,
  "entry": "index.html",
  "requiresHost": "0.1.0",
  "priority": 0
}
```

- `id`: `[a-z0-9-]`, must match the folder name
- `version`, `requiresHost`: `x.y.z`
- `matches.extensions`: lowercase, no dot. `matches.utis` optional.
  an exact uti match beats an extension match; within a tier the enabled
  plugin with the highest `priority` wins, ties go alphabetically by id
- `input`: `text` | `bytes` | `json` | `sqlite`, see below
- `maxFileSize`: bytes, default 50 MB. bigger files get an error view,
  the plugin never runs
- `entry`: default `index.html`

the host can only preview file types it was built with
(`Extension/Info.plist` → `QLSupportedContentTypes`). if your extension is
not in that list, it needs a host release first.

## what the plugin gets

injected before your scripts run:

```js
window.spacebar = {
  host:   { version: "0.1.0" },
  plugin: { id, name, version },
  file:   { name: "cities.geojson", path: "/…", size: 12345, uti: "public.geojson", ext: "geojson" },
  input:  "text",
  data:   <payload>,
  theme:  "light" | "dark",
  done(),          // call when rendered; the host reveals the view
  fail(message),   // call to show the host's error view instead
  log(message)     // shows up in the dev harness console and the system log
}
```

`console.log/warn/error` are forwarded too. uncaught errors and unhandled
rejections turn into `fail()`.

payload shapes by `input`:

- `text`: the file as a string (utf-8, invalid bytes become U+FFFD)
- `bytes`: base64 string. keep `maxFileSize` small
- `json`: parsed object (parse errors become a host error view)
- `sqlite`: the host opens the db read-only and hands you:

```json
{
  "pageSize": 4096, "encoding": "UTF-8", "userVersion": 0, "fileSize": 123456,
  "tables": [{
    "name": "cities", "type": "table", "sql": "CREATE TABLE …",
    "columns": [{ "name": "id", "type": "INTEGER", "pk": true, "notnull": true, "default": null }],
    "rowCount": 1200, "approx": false,
    "sample": [[1, "Oslo", 59.9], …]
  }],
  "views":   [{ "name": "…", "sql": "…" }],
  "indexes": [{ "name": "…", "table": "…", "sql": "…" }],
  "truncated": false
}
```

`sample` is the first 50 rows; blobs are `{"blob": <bytes>}`. a count
that takes over 200 ms is skipped (`rowCount: null, approx: true`). samples
stop past ~2 MB total (`truncated: true`).

## rules

- call `done()` or `fail()` within 3 seconds or the host shows "timed out"
- no network: every http/https/ws load is blocked. relative paths inside
  the plugin folder are fine. no filesystem either
- follow `theme` (or `prefers-color-scheme`, the webview follows the system)
- keys pass through: arrow keys, etc. work. the panel can be any size

## iterate

in the app: window → dev harness (⇧⌘D). pick a plugin and a file, reload
with ⌘R, read your `log()` output on the right. it uses the exact same
webview and bridge as the extension.

without the app, in a browser:

```
make samples
python3 -m http.server 8000
open "http://localhost:8000/harness/?plugin=geojson&sample=cities.geojson"
```

for `sqlite` plugins the harness loads `samples/<file>.json`, written by
`make samples` with the real host-side summary. to dump any db yourself:

```
Packages/SpacebarKit/.build/debug/spacebar-cli dump my.sqlite3 > my.sqlite3.json
```

`scripts/validate-plugins.sh` checks every plugin in `plugins/` (manifest
keys, entry exists, no http urls in code).
