# Spacebar — plugin-based Quick Look host for macOS

> Working name "Spacebar" (rename freely; bundle ID prefix `io.spacebar` is a placeholder — change to something you own).
> This file is the brief for Claude Code. Read all of it before writing code.

## What we're building

A macOS app that bundles a Quick Look Preview Extension. The extension doesn't know how to render anything itself. It picks a **plugin** — a folder of HTML/JS — that matches the file's type, loads it in an offline `WKWebView`, hands it the file's contents (or a native-parsed summary of them), and shows the result in Finder's spacebar preview.

Goal for v0.1: a convincing demo of the concept with **two plugins, `geojson` and `sqlite`**, buildable from a clean checkout with one command, testable, and installable via a Homebrew tap. Not a product. Minimal docs.

Prior art to be aware of (don't copy, but borrow ideas): `jtbandes/quicklookjs` (the WebView bridge idea, build-time only), `sbarex/SourceCodeSyntaxHighlight` (XPC trick for sandbox, we don't need it), `samuelmeuli/glance` (archived all-in-one).

## Hard constraints (macOS facts, not choices)

1. **Quick Look extensions are sandboxed.** They can read the previewed file and their own container / app-group container. Nothing else. No launching processes. No network unless entitled — and we deliberately won't be.
2. **Supported file types are static.** `QLSupportedContentTypes` in the extension's Info.plist is fixed at build time. Plugins can't add types at runtime. We ship a broad curated list of UTIs and declare custom ones (`UTImportedTypeDeclarations`) for extensions macOS doesn't know (`.geojson`, `.sqlite3`). Adding a brand-new type = a host release. Never claim `public.data` / `public.item`.
3. **Apple reserves some types** on recent macOS (JSON, CSV, XML, plist, …): third-party previews never run for them. So `.geojson` must be its own UTI, not `public.json`.
4. **Third-party Quick Look extensions must be enabled** in System Settings → General → Login Items & Extensions → Quick Look. Launching the app once registers it. `pluginkit -e use -i <ext bundle id>` can enable it from the shell (use this in `make install`; if it stops working on some OS version, fall back to telling the user).
5. **Slow extensions get killed** and leave a blank panel. We enforce our own timeout and show an error instead.
6. **No Xcode GUI needed, but Xcode toolchain is required** — SwiftPM alone cannot build `.appex` bundles. Use **XcodeGen** (`project.yml` checked in, `.xcodeproj` gitignored) + `xcodebuild`. Ad-hoc code signing (`CODE_SIGN_IDENTITY=-`) is enough for local use and for the unsigned Homebrew release.

## Repo layout

```
spacebar/
  project.yml                 # XcodeGen spec: App target + QuickLook extension target
  Makefile                    # the only interface you need: make build/install/test/samples/release
  Packages/SpacebarKit/       # SwiftPM package, all logic, unit-tested with `swift test`
    Sources/SpacebarKit/
      Manifest.swift          # plugin.json model + validation
      PluginIndex.swift       # scans a plugins dir, builds index, picks plugin for a file
      Matcher.swift           # UTI/extension matching + priority
      Input/
        InputProvider.swift   # protocol: (URL, Manifest) -> InputPayload
        TextInput.swift
        BytesInput.swift
        JSONInput.swift
        SQLiteInput.swift     # native sqlite3 summary (see below)
      Bridge.swift            # builds the JS injected into the WebView
      Paths.swift             # container / plugins dir resolution
    Tests/SpacebarKitTests/
  App/                        # main app (SwiftUI, tiny)
    SpacebarApp.swift
    StatusView.swift          # is the extension registered/enabled? buttons.
    PluginsView.swift         # list plugins, install from folder, enable/disable, open plugins dir
    DevWindow.swift           # dev harness: pick plugin + file, render with the real bridge, reload
    Info.plist                # UTImportedTypeDeclarations for geojson, sqlite
    App.entitlements
  Extension/                  # Quick Look preview extension
    PreviewViewController.swift
    PreviewWebView.swift      # WKWebView + bridge + timeout + error view
    Info.plist                # QLSupportedContentTypes (broad list), QLIsDataBasedPreview etc.
    Extension.entitlements
  plugins/                    # the plugins shipped with the app (copied into bundle at build)
    geojson/
    sqlite/
  samples/                    # generated sample files (gitignore the outputs, keep scripts)
    make_samples.sh
    make_sqlite.sql
  harness/                    # browser-only dev harness (no Xcode): index.html loads a plugin + a sample
  scripts/
    validate-plugins.sh       # manifest schema check for every plugin
    smoke.sh                  # builds, installs, runs qlmanage against samples, checks for errors
    release.sh                # builds release zip, writes sha256
  homebrew/
    spacebar.rb               # cask formula template; lives in a separate `homebrew-tap` repo when published
  .github/workflows/ci.yml    # macos runner: swift test + xcodebuild + smoke
  README.md                   # 1 screen
  PLUGINS.md                  # 1 page: how to write a plugin
```

## Plugin contract (the thing that matters most)

A plugin is a directory:

```
geojson/
  plugin.json
  index.html
  index.js
  style.css
  vendor/        # optional, bundle any libs here; no CDN, there is no network
```

`plugin.json`:

```json
{
  "id": "geojson",
  "name": "GeoJSON",
  "version": "0.1.0",
  "matches": {
    "extensions": ["geojson"],
    "utis": ["io.spacebar.geojson"]
  },
  "input": "text",
  "maxFileSize": 52428800,
  "entry": "index.html",
  "requiresHost": "0.1.0"
}
```

- `input` ∈ `text | bytes | json | sqlite`. Host prepares the payload; plugin never touches the filesystem.
- `matches.extensions` are lowercase, no dot. `matches.utis` optional. Matching: exact UTI first, then extension. If two plugins match, the enabled one with highest `priority` (optional int, default 0) wins; ties → first alphabetically by `id`, and log a warning.
- `maxFileSize` in bytes; over it the host shows "file too large for GeoJSON plugin (52 MB limit)" — no plugin runs.

What the plugin receives. Before `index.html`'s scripts run, the host injects (via `WKUserScript` at document start):

```js
window.spacebar = {
  host: { version: "0.1.0" },
  file: { name: "cities.geojson", path: "/…", size: 12345, uti: "io.spacebar.geojson", ext: "geojson" },
  input: "text",
  data: <payload>,          // see per-input shapes below
  theme: "light" | "dark",
  done()  ,                 // call when rendered; host reveals the view
  fail(message)             // call to show the host's error view instead
}
```

Payload shapes:

- `text` → `string`
- `bytes` → base64 `string` (plugin decodes). Keep `maxFileSize` small for this.
- `json` → parsed object (host parses with `JSONSerialization`; parse error → host error view)
- `sqlite` → 
  ```json
  {
    "pageSize": 4096, "encoding": "UTF-8", "userVersion": 0, "fileSize": 123456,
    "tables": [
      { "name": "cities", "type": "table", "sql": "CREATE TABLE …",
        "columns": [{ "name": "id", "type": "INTEGER", "pk": true, "notnull": true }],
        "rowCount": 1200,
        "sample": [[1, "Oslo", 59.9], …]     // first 50 rows, values as JSON (blobs → {"blob": <len>})
      }
    ],
    "views": [{ "name": "…", "sql": "…" }],
    "indexes": [{ "name": "…", "table": "…", "sql": "…" }]
  }
  ```

Rules for plugins: call `spacebar.done()` or `spacebar.fail()`; render within 3 s; if the host hears nothing in 3 s it shows "plugin `geojson` timed out". Respect `theme` (`prefers-color-scheme` also works since WKWebView follows the system). No network, no `fetch` to anything but relative paths inside the plugin folder.

## Host behavior

### Extension (`PreviewViewController.preparePreviewOfFile(at:completionHandler:)`)

1. Resolve file UTI (`UTType(filenameExtension:)` / resource values) and extension.
2. Load `PluginIndex` from the plugins directory (see Paths). Cache the parsed index in memory per process; cheap anyway.
3. Pick plugin. None → call handler with an `NSError` so macOS falls back to its default preview.
4. Check `maxFileSize`. Over → error view, call handler(nil) (we still "succeed" so the user sees our message).
5. Build payload with the matching `InputProvider`. Errors → error view.
6. Create `WKWebView` with: JS enabled, `WKUserContentController` holding the injected script + a `host` message handler (`done`, `fail`, `log`), `websiteDataStore = .nonPersistent()`. Load with `loadFileURL(entry, allowingReadAccessTo: pluginDir)`.
7. Start a 3 s timer. `done` → cancel timer, call handler(nil). `fail`/timeout → swap to the error view, call handler(nil).
8. Error view is a plain `NSTextField`-based view: plugin name, message, "Open Spacebar to manage plugins". Never leave the panel blank.

Keep the extension process lean: no SwiftUI, no network entitlement. `SpacebarKit` is linked as a static library into both targets.

### Paths / where plugins live

Decision for v0.1 — **App Group container**, `group.io.spacebar`:
- Main app copies plugins into `<group container>/Plugins/<id>/` and writes `<group container>/plugins-index.json` plus `disabled.json`.
- Extension reads only from there.
- Both targets get `com.apple.security.application-groups` = `group.io.spacebar`.

Known wrinkle: on macOS 15+ an app group ID not prefixed by a Team ID, in an ad-hoc-signed app, may trigger a one-time system dialog "Spacebar would like to access data from other apps". Acceptable for a dev build; document it. **If it turns out the extension cannot read the group container at all under ad-hoc signing**, fall back to: main app is *not* sandboxed (fine for non-App-Store) and writes directly into the extension's own container at `~/Library/Containers/io.spacebar.app.QuickLook/Data/Library/Application Support/Spacebar/Plugins/`; extension reads its own container. Implement `Paths.swift` so this is a one-line switch. Try app-group first; verify with `make smoke` before building anything on top of it.

Bundled plugins: the `plugins/` dir is copied into the app bundle's `Resources/Plugins/` at build. On every app launch the app syncs bundled plugins into the container (overwrite if bundled version is newer, never overwrite a user-installed plugin with the same id — user wins).

### Main app (keep it to three views)

- **Status**: extension found? (`pluginkit -m -i io.spacebar.app.QuickLook`-equivalent via `NSExtension`? Simplest: shell out to `pluginkit` from the non-sandboxed app, or just show a button "Open Quick Look extension settings" using `x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview`). Button: "Reset Quick Look" → runs `qlmanage -r` and `qlmanage -r cache`.
- **Plugins**: table of installed plugins (id, name, version, extensions, enabled toggle, source: bundled/user). Buttons: "Install from folder…", "Open plugins folder", "Remove".
- **Dev harness window**: choose plugin folder + file, renders using *the same* `PreviewWebView` class the extension uses, with a Reload button and a console pane fed by the `log` message handler. This is how plugin authors iterate without pressing spacebar in Finder.

That's it. No settings, no menu bar item, no updater.

## The two plugins

### `geojson` (input: `text`)

Zero dependencies — render it ourselves, which also proves plugins don't need vendored libs.

- Parse; if it's not valid GeoJSON (`type` missing) → `spacebar.fail("Not valid GeoJSON")`.
- Header: feature count, geometry type histogram (Point 120 · Polygon 3 …), bbox, CRS note if non-default.
- Map: an `<svg>` that draws all geometries with an equirectangular projection fitted to the bbox (pad 5%). Points as circles, lines as polylines, polygons as paths with fill-opacity 0.25. Cap at 20k vertices — beyond that, decimate (every nth vertex) and say so in the header.
- Hover a feature → show its `properties` in a side panel. Click → pin it.
- Below the map: properties table, first 100 features, columns = union of property keys.
- Dark mode via CSS variables.

### `sqlite` (input: `sqlite`)

- Host side (`SQLiteInput.swift`): open with `sqlite3_open_v2` using URI `file:<path>?immutable=1&mode=ro` and `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI` — `immutable=1` matters: the sandbox can't create `-wal`/`-shm` next to the file, and read-only without it can still fail on WAL databases. `PRAGMA query_only=1`. Enumerate `sqlite_master`; `PRAGMA table_info(x)`; row counts via `SELECT COUNT(*)` with a per-table budget — if a count takes > 200 ms, report `rowCount: null, approx: true` and skip (big tables). Sample `SELECT * FROM "x" LIMIT 50`. Blobs → `{"blob": n}`. Hard cap total payload at ~2 MB (truncate samples). Reject if the first 16 bytes aren't `SQLite format 3\0`.
- Plugin side: left column = table list with row counts; main = selected table's columns (name, type, PK/NOT NULL badges) + sample rows in a table; "Schema" tab shows the `CREATE` SQL. Views and indexes listed under tables. Keyboard: ↑/↓ switches tables (Quick Look passes keys through).
- Stretch (not v0.1): `spacebar.query(sql)` roundtrip over the message handler for paging. Leave a TODO; don't build it.

## Samples (`make samples`)

Generated, deterministic, no downloads:

- `samples/cities.geojson` — ~60 world cities as Points with `name`, `country`, `population` properties (hardcode the list in the script).
- `samples/shapes.geojson` — FeatureCollection with a Polygon, a MultiPolygon with a hole, a LineString, mixed.
- `samples/big.geojson` — 50k random points (tests decimation + the size cap path).
- `samples/invalid.geojson` — plain JSON that isn't GeoJSON (tests `fail`).
- `samples/library.sqlite3` — built by `sqlite3 samples/library.sqlite3 < samples/make_sqlite.sql`: `authors`, `books`, `loans` with FKs, an index, a view, ~500 rows, one BLOB column, and a `notes` table with 100k short rows to exercise the count budget.
- `samples/wal.sqlite3` — same DB with `PRAGMA journal_mode=WAL` (tests `immutable=1`).
- `samples/notadb.sqlite3` — text file with the wrong extension.
- `samples/huge.sqlite3` — optional, created only with `make samples-huge`: 200 MB of junk rows to prove the size cap.

## Build / test / install (`Makefile`)

```
make gen        # xcodegen generate
make build      # xcodebuild -scheme Spacebar -configuration Debug CODE_SIGN_IDENTITY=- build  → build/Spacebar.app
make test       # swift test in Packages/SpacebarKit + scripts/validate-plugins.sh
make samples    # generate samples/
make install    # copy build/Spacebar.app to /Applications (or ~/Applications), open it once,
                # pluginkit -e use -i io.spacebar.app.QuickLook, qlmanage -r
make smoke      # scripts/smoke.sh: for each sample, `qlmanage -p` in headless mode (qlmanage -t -s 800 -o /tmp/… renders thumbnails;
                # for previews use `qlmanage -p` and check Console/log for our extension's "rendered <plugin>" / "error" lines
                # via `log show --predicate 'subsystem == "io.spacebar"' --last 2m`). Fail the script on any "error" line.
make release    # scripts/release.sh: Release build, ad-hoc sign, zip to dist/Spacebar-<version>.zip, print sha256
make clean
```

Logging: use `os.Logger(subsystem: "io.spacebar", category: "extension")` everywhere in the extension. One line per preview: plugin id, file ext, payload size, elapsed ms, outcome. This is what `smoke.sh` greps and what you tell users to run when "nothing shows".

Unit tests (SpacebarKit, must pass with `swift test` on the CI mac runner):
- Manifest decoding: valid, missing fields, bad `input` value, non-semver version.
- Matcher: exact UTI beats extension; priority; disabled plugin skipped; unknown file → nil.
- SQLiteInput against a fixture DB built in the test (`sqlite3_open` in-memory → write to temp): tables/columns/rowCount/sample shapes; WAL file; non-DB file rejected; blob encoding.
- JSONInput: invalid JSON → typed error.
- Bridge: injected script is valid JS and embeds the payload safely (escape `</script>`, U+2028/2029).

Plugin validation (`scripts/validate-plugins.sh`): every `plugins/*/plugin.json` parses, required keys present, `entry` exists, no absolute URLs or `http(s)://` strings in html/js (grep — crude but catches CDN usage).

Harness (`harness/index.html`): pure browser page: `?plugin=geojson&sample=cities.geojson`, loads the plugin in an iframe, injects a fake `window.spacebar` with the sample's contents (for `sqlite` input, the harness loads a pre-generated `samples/library.sqlite3.json` payload that `make samples` writes using the real `SQLiteInput` via a tiny `spacebar-cli dump <file>` executable target in the package). Serve with `python3 -m http.server`. This lets someone write a plugin with no Xcode at all.

## Distribution

- GitHub Actions (`macos-latest`): `make test`, `make build`, `make samples`, `make smoke` (smoke may be flaky on CI runners because of extension registration — make it non-blocking there, blocking locally), `make release` on tag, upload the zip + sha256 as a release asset.
- Homebrew: separate repo `homebrew-tap`, cask `spacebar.rb`:
  ```ruby
  cask "spacebar" do
    version "0.1.0"
    sha256 "…"
    url "https://github.com/<you>/spacebar/releases/download/v#{version}/Spacebar-#{version}.zip"
    name "Spacebar"
    desc "Plugin-based Quick Look previews (GeoJSON, SQLite, …)"
    homepage "https://github.com/<you>/spacebar"
    app "Spacebar.app"
    postflight do
      system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Spacebar.app"]
      system_command "/usr/bin/open", args: ["-a", "#{appdir}/Spacebar.app"]
    end
    caveats <<~EOS
      Unsigned build. Enable the extension:
        System Settings → General → Login Items & Extensions → Quick Look → Spacebar
      Then press space on a .geojson or .sqlite3 file.
    EOS
  end
  ```
  Users run `brew tap <you>/tap && brew install --cask spacebar`. Signing/notarization ($99/yr Developer ID) comes later and only changes `release.sh`; nothing else in the design depends on it.

## Build order (do these in sequence; each ends with a verification)

1. **Scaffold**: `project.yml`, Makefile, empty targets, entitlements, Info.plists with UTI declarations and a *small* `QLSupportedContentTypes` (just geojson + sqlite for now; broaden later). `make build` produces an app whose extension registers. Verify: `pluginkit -m -p com.apple.quicklook.preview | grep spacebar`.
2. **Container plumbing**: `Paths.swift`, app writes a marker file into the group container, extension logs whether it can read it. `make install && make smoke` on any `.geojson` → log line proves the read path works. **Stop and switch to the fallback path if it doesn't.**
3. **SpacebarKit**: Manifest, PluginIndex, Matcher, Text/JSON/Bytes inputs, Bridge. `swift test` green.
4. **Extension WebView path**: PreviewWebView with bridge, timeout, error view. Hardcode a trivial `plugins/hello/` (shows file name) to test end-to-end. Spacebar on a `.geojson` shows "hello cities.geojson". Delete `hello` after.
5. **geojson plugin** + samples. Verify in Finder on all four geojson samples, light and dark.
6. **SQLiteInput** + tests + **sqlite plugin** + samples. Verify incl. WAL and not-a-db.
7. **Main app views** (status, plugins list with install/enable/disable, dev harness). Verify: install a copy of `geojson` from a folder under a new id, disable the bundled one, preview picks the user's.
8. **Harness, validate script, smoke script, CI, release script, cask**. Tag `v0.1.0`, confirm `brew install --cask` from the tap works on a second machine/user account.
9. **Broaden `QLSupportedContentTypes`** to the curated list (gpx, kml, parquet, arrow, ipynb, epub, toml, env, log, diff, patch, org, rst, adoc, wasm, msgpack, …) — only now, so the earlier steps aren't debugging type-registration issues.
10. README + PLUGINS.md.

## Working rules for Claude Code

- Verify every step on the actual machine (build, install, press space / `qlmanage -p`). Don't claim a step works from reading code.
- When something about Quick Look behaves unexpectedly, check `log show --predicate 'subsystem == "io.spacebar"' --last 5m` and `qlmanage -r` before changing code.
- Keep the extension free of SwiftUI and any dependency beyond Foundation, AppKit, WebKit, SQLite3, SpacebarKit.
- No third-party Swift packages in v0.1. No JS build step for the bundled plugins (plain ES modules). A plugin author may use React/bundlers; we just load whatever is in `entry`.
- Prefer deleting scope over adding it. If a step is taking more than ~2× the expected effort, write the problem down in `NOTES.md` and move on.
- Docs: README under 60 lines (what, install, enable, try samples, write a plugin → PLUGINS.md). PLUGINS.md = the contract section above, trimmed, plus the harness instructions.
- Commit after each build-order step with a message naming the step.
