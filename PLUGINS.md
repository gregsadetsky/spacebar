# writing a plugin

## the short loop

```
# first argument: the plugin id (folder name, what the app lists). second: the
# file extension it previews. often the same word, not always (notebook ipynb)
scripts/new-plugin.sh toml toml        # plugins/toml/ with a working plugin.json + index.html + index.js

# make build compiles into build/Spacebar.app and touches nothing else
# (build/ is gitignored; a fresh clone compiles in about 10 s with swiftc).
# make install also copies the app to ~/Applications, registers the quick
# look extension and opens the app once: that launch is what copies the
# bundled plugins into the extension's container, so space in finder works.
make build
build/Spacebar.app/Contents/MacOS/Spacebar --dev some.toml --plugin toml --snapshot out.png
build/Spacebar.app/Contents/MacOS/Spacebar --dev some.toml --plugin toml --snapshot dark.png --theme dark
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
quick look extension. to check your own file through the real extension:

```
make install
qlmanage -p some.toml &            # the real extension renders it; close the window after
/usr/bin/log show --info --last 1m --predicate 'subsystem == "io.spacebar"' | grep rendered
scripts/ql-shot.sh some.toml out.png   # same, plus a screenshot of the panel
```

the log line says `rendered plugin=toml ... outcome=done` (or `failed: …`,
`timed out`, `host error: …`).

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
- `input`: `text` | `bytes` | `json` | `plist` | `sqlite` | `archive` | `epub`, see below
- `maxFileSize`: bytes, default 50 MB. bigger files get an error view,
  the plugin never runs
- `entry`: default `index.html`

the host can only preview file types it was built with:
`Extension/Info.plist` → `QLSupportedContentTypes` lists utis, not extensions.
extensions macos doesn't know (toml, parquet, ipynb, …) are declared by the
app in `App/Info.plist` as `io.spacebar.<ext>`; types macos already has keep
their own uti (`public.geojson`, `com.topografix.gpx`). `scripts/new-plugin.sh`
fills in `matches.utis` for you and warns when an extension isn't supported.
a new extension needs a host release first.

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

- `text`: the file as a string (UTF-8, or UTF-16 when marked with a byte-order
  mark; invalid UTF-8 bytes become U+FFFD)
- `bytes`: base64 string. keep `maxFileSize` small
- `json`: parsed object (parse errors become a host error view)
- `plist` (host 0.2.0+): the root value parsed natively from a binary, XML or
  OpenStep property list. Dictionaries, arrays, strings, booleans and numbers
  keep their shape; root scalars and empty containers work too. JSON conversions:
  - dates → UTC ISO 8601 strings with milliseconds
  - data → `{"data": "<base64>", "bytes": n}`
  - integers outside JavaScript's safe range (±9,007,199,254,740,991) → decimal
    strings, preserving every digit
  - non-finite reals → `"NaN"`, `"Infinity"`, `"-Infinity"`
  - keyed-archive UID references → `{"CF$UID": n}`; archived objects are never
    instantiated or unarchived

  This is a JSON representation, not a lossless plist round trip (for example,
  dates become strings). No archive/Shortcuts container unpacking is performed.
  Malformed plists get a host error. In addition to `maxFileSize`, conversion is
  capped at 128 nesting levels, 100,000 values and 32 MB of expanded strings/data.
  The bundled viewer caps input at 10 MB and pages large branches in the tree.
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

### archive (host 0.2.0+)

The host lists ZIP, TAR, gzip/bzip2/xz-compressed TAR, 7z and RAR using macOS's
system libarchive. It never extracts files to disk or follows archive links.

```json
{
  "format": "ZIP 2.0 (deflation)",
  "entries": [{
    "path": "project/readme.md", "kind": "file", "size": 1024,
    "modified": "2026-10-19T12:00:00Z", "encrypted": false, "unsafePath": false
  }],
  "truncated": false,
  "warnings": []
}
```

`kind` is `file`, `directory`, `link` or `special`. `modified` is optional;
links can also have a `target`. Sizes outside JavaScript's safe integer range
are decimal strings. Unusual paths (absolute paths or `..`, for example) are
flagged and remain literal names. Encryption may prevent even a listing.

Limits: 10,000 entries, 2 MiB of path text and 4,096 characters per displayed
path. A two-second budget is checked between libarchive reads; a single native
read can take longer. Compressed sequential listings stop before skipping an
entry larger than 64 MiB. Partial listings carry warnings. The bundled plugin
accepts files up to 512 MiB and displays 200 rows at a time.

### epub (host 0.2.0+)

The host reads EPUB 2/3 package metadata and a bounded excerpt from the ZIP
container. Chapters are untrusted HTML: a plugin must sanitize them before
inserting them into the DOM. The bundled viewer uses DOMPurify.

```json
{
  "title": "Field Notebook", "authors": ["A. Reader"], "language": "en",
  "cover": "data:image/png;base64,…",
  "toc": [{ "title": "Introduction", "path": "OEBPS/intro.xhtml" }],
  "chapters": [{ "title": "Introduction", "path": "OEBPS/intro.xhtml", "html": "…" }],
  "resources": { "OEBPS/cover.png": "data:image/png;base64,…" },
  "totalChapters": 30, "truncated": true
}
```

`cover` is an empty string if unavailable. Paths are relative to the container;
resources are embedded PNG/JPEG/GIF/WebP images. No external resources or
publisher stylesheets are loaded. DRM-protected books are unsupported.

Limits: the first 12 linear HTML sections, 1 MiB per document and 6 MiB of
documents total; up to 64 images, 2 MiB each and 8 MiB total. Metadata XML has
depth/node caps and entity declarations are rejected. Archive reads share a
four-second budget checked between reads. `truncated` means sections or images
were omitted; the viewer labels the excerpt. The bundled plugin accepts EPUBs
up to 256 MiB.

## rules

- call `done()` or `fail()` within 3 seconds or the host shows "timed out"
- `fail(message)` when the file isn't what the plugin expects (the geojson
  plugin fails on json without a `type`); the host shows the message in its
  own error view. `done()` with your own error markup also works if you want
  it styled; either is fine
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

for `sqlite`, `plist`, `archive` and `epub` plugins the harness loads
`samples/<file>.json`, written by
`make samples` with the real host-side payload. to dump a file yourself
(`make cli` builds the tool first):

```
make cli
Packages/SpacebarKit/.build/debug/spacebar-cli dump my.sqlite3 > my.sqlite3.json
Packages/SpacebarKit/.build/debug/spacebar-cli dump preferences.plist > preferences.plist.json
```

Try the property list viewer with
`http://localhost:8000/harness/?plugin=plist&sample=preferences-binary.plist`.
`make samples` also generates XML, OpenStep and keyed-archive examples, plus
an invalid plist for the native host's error view.

Try the notebook viewer with
`http://localhost:8000/harness/?plugin=notebook&sample=analysis.ipynb`.
`make samples` generates rich, legacy, empty, invalid, large and untrusted
notebooks. Its checked-in JupyterLab-based bundle requires no downloads at
runtime or during a normal app build. To change it, see
[tools/notebook/README.md](tools/notebook/README.md).

The same build tooling produces the Markdown, archive, EPUB and subtitle
bundles. Their browser harness examples are:

```
http://localhost:8000/harness/?plugin=markdown&sample=guide.md
http://localhost:8000/harness/?plugin=archive&sample=project.zip
http://localhost:8000/harness/?plugin=epub&sample=field-notebook.epub
http://localhost:8000/harness/?plugin=subtitles&sample=dialogue.srt
```

`make samples` also generates TAR, compressed TAR, 7z, RAR, WebVTT, UTF-16
subtitles, large cue lists and malformed/untrusted documents. UTF-16 fixtures
are tested through the native host; the browser harness fetches text as UTF-8.

`scripts/validate-plugins.sh` checks every plugin in `plugins/` (manifest
keys, entry exists, no http URLs in first-party code). The generated vendor code
contains inert upstream URL constants and is covered by bundle tests and the
host's runtime network block.
