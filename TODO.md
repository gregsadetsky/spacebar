# todo

- **no update path**: a brew-installed copy only changes through a new
  release + cask bump (tag vX.Y.Z, ci attaches the zip, copy the sha256 into
  homebrew-tap/Casks/spacebar.rb). even a plugin-only fix needs that, since
  bundled plugins live inside the app bundle. the dev loop (`make install`)
  must not run next to the brew copy: two apps register the same extension.
  options: a `make bump VERSION=` that tags + updates the cask; the app
  checking github releases and offering the update; or shipping plugins
  separately from the app so they update on their own.
- app self-update: Sparkle (what non app store mac apps use). needs an
  appcast xml served somewhere (github pages or the web/ site), the zip
  signed with sparkle's EdDSA key, and the app bundling the framework. works
  with an ad-hoc signed app but pairs naturally with the developer id step.
  brew users would keep getting updates through brew; sparkle covers the
  people who downloaded the zip.
- status tab: the "press space on a .geojson or .sqlite3 file" line is the
  one sentence that says what the app does, and it's rendered as a grey
  caption under a status row. make it the obvious thing: bigger, first,
  phrased as what the software does. also: it is hardcoded.
  it should list what is actually previewable right now, computed from the
  enabled plugins' extensions (cap at 5 to 10, then "…"). check how it reads
  after installing or disabling a plugin.
- universal (arm64 + x86_64) release zip; intel macs can't open the current one
- developer id signing + notarization (release.sh only), see readme note
- sqlite: `spacebar.query(sql)` so sort/paging works on the whole table, not the 50 sampled rows
- `requiresHost` in plugin.json is parsed but never enforced; a plugin needing
  a newer host should get a clear error view instead of breaking
- the 3 s plugin timeout vs `maxFileSize`: big.geojson (5.7 MB) renders in
  ~0.7 s, so a 50 MB geojson will time out before it parses. either lower the
  geojson cap or let plugins ask for more time
- bundle id prefix `io.spacebar` is the placeholder from the brief and is now
  baked into a release; changing it later means users re-enable the extension
- `.db` is claimed by the sqlite plugin; non-sqlite .db files now get our
  "not a SQLite database" view instead of apple's generic one. keep or drop
- never clicked through by hand: plugins tab (install from folder, remove,
  toggles), dev harness window, dark mode and arrow keys in the real finder
  panel. all verified through code paths and `--dev`, not the ui
- web/: not deployed (disco.json is there); og:image url assumes
  spacebar.greg.technology; no favicon yet
- finder and the dock may keep the old icon until their cache refreshes

## plugin ideas

- task: survey which extensions actually matter. count extensions on this
  mac (find ~ -type f, group by extension, ignore caches and node_modules),
  and read the issue trackers / supported lists of the open source quick
  look apps (glance, quicklookjs, SourceCodeSyntaxHighlight, QLMarkdown,
  OnePreview, Parkour) for what people ask for. Plist and ipynb now implemented.

- `.tar.gz` / `.tar` / `.zip`: list the entries (name, size, date) like a
  file browser. the host can do the listing natively with libarchive
  (ships with macos, /usr/lib/libarchive.dylib) as a new `archive` input, so
  plugins never touch the bytes. "click an entry to get just that file" (the
  winrar move) needs the host to extract and hand the file somewhere: a
  sandboxed extension can't write to ~/Downloads on its own, so this would
  be a host action (save panel? reveal via the app?). research. note that
  macos already handles .zip with its own preview; whether a third-party
  extension can take `public.zip-archive` over apple's is untested.
- `.dmg`: no obvious way. hdiutil can't run in the sandbox and libarchive
  doesn't read dmg. maybe show the embedded metadata only. low priority.
- `.json` / `.md` / `.csv` / `.yaml`: obvious, but apple previews these
  itself and may not let third parties override them (the brief says json,
  csv, xml, plist are reserved; `public.geojson` conforms to `public.json`
  and still reached us, so test before assuming). a nicer json tree, a
  rendered markdown, a csv with real columns would all be popular.
- the gap others fill, for a feel of demand: OnePreview (json, jsonl, yaml,
  xml, csv, tsv, toml), Parkour (parquet, csv, json, arrow), the VS Code
  data preview extension (parquet, arrow, avro, json, yaml, csv, excel).
  parquet keeps coming up as the one nothing on the mac previews.
- ableton live sets (`.als`, people ask for this): gzipped xml. a plugin
  with `bytes` input + a vendored gunzip (pako) + the browser's DOMParser
  can show tempo, tracks, clip names, devices and plugins used, maybe a
  timeline sketch. sets can be tens of MB gzipped, so watch the 3 s budget
  or add a native `gzip` input kind so the host inflates it first. needs
  a host release to claim the extension (`com.ableton.live-set` or
  whatever uti live registers on that mac; check with spacebar-cli match).
- other candidates already in QLSupportedContentTypes with no plugin yet:
  parquet, arrow/feather, toml, kml, mbtiles
  / pmtiles (map), har, jsonl, wasm (exports/imports), npy/npz, h5, fit/tcx
  (track on the map, reusing the geojson renderer).

## plugin distribution (the obsidian model)

- install a plugin from github: user pastes `owner/repo` (or picks from the
  list below); the app reads the repo's latest github release, downloads
  the asset zip (or the tag tarball), validates plugin.json, installs it as
  a user plugin, remembers the repo + version. "check for plugin updates"
  compares against the latest tag; auto-update optional per plugin.
- a plugin registry / marketplace: obsidian keeps a single json file
  (community-plugins.json) in a central repo; plugin authors open a pull
  request that adds one entry (id, name, author, description, repo), a
  maintainer reviews and merges, the app fetches that json to show the
  list. the plugin's own repo publishes github releases whose assets are
  the plugin files. same shape would work here: a `plugins.json` in this
  repo or in a spacebar-plugins repo, pr to add yourself, the app lists it.
- thumbnails: a marketplace thing, but the plugin can declare it in its
  manifest (`"screenshot": "screenshot.png"`, `"icon": "icon.png"`, both
  relative, both optional). the registry entry could also carry a url so
  the list renders without downloading the plugin. decide which when the
  marketplace exists.
- sandbox note: the app (not the extension) does all downloading, so no
  entitlement changes. plugins stay offline at runtime either way.

## plugin survey (2026-10-19)

counts on greg's mac (home folder, skipping caches, node_modules, .git,
site-packages, build dirs): plist 3367, sqlite 1689, csv 1280, stl 1074,
srt 757, lock 1218, env 449, vtt 286, pickle/pkl 264, ipynb 102, sqlite3 99,
pcap 48, step 44, safetensors 40, onnx 32, geojson 28, npz 23, h5 15, npy 13,
kml 12, parquet 3. generic ones for scale: json 228k, md 31k, yaml 26k,
log 15k, xml 9k, toml 2.6k, jsonl 3k. online: glance's readme names plist,
ts and xml as types macos doesn't handle; its faq collects requests as
issues. parkour exists only for parquet/arrow/csv/json. nobody previews
ableton sets.

### next plugins, in order

1. **plist: implemented for host 0.2.0, release + cask bump pending.**
   Native binary/XML/OpenStep input, lazy collapsible tree, JSON view and
   copy as JSON. Dates, data, large integers and keyed-archive UIDs are
   normalized for JSON (see PLUGINS.md). Claims the base, XML and binary
   property-list UTIs. Tests and samples cover the formats and error paths.
   Verified locally through the real Quick Look extension on 2026-10-19:
   binary, XML, OpenStep and keyed archives rendered in 146–249 ms; malformed
   XML showed the host error. Apple did not take over these plist previews.
   Reference: [i-just-want-to-see-the-plist](https://github.com/gregsadetsky/i-just-want-to-see-the-plist)
   still lists XML support as TODO; its current parser fixes the old emoji
   issue and also unwraps Shortcuts/archive containers. Container unpacking
   is outside this first plist plugin's scope.
2. **ipynb: implemented locally, release + cask bump pending.** JSON input,
   JupyterLab 4.6.4 rendering functions, Markdown, highlighted code, math,
   saved tables/images/SVG, streams and error tracebacks. Supports notebook
   formats 3/4, paging, code visibility, output limits and both themes.
   Sanitized and offline; interactive output needs a saved static fallback.
   `io.spacebar.ipynb` was already claimed. Build/test instructions and
   dependency licenses are in tools/notebook/README.md.
   Verified 2026-10-19 through the real extension: rich, legacy, empty,
   untrusted and 1,000-cell notebooks finished in 186–1,763 ms; invalid cells
   showed the expected error. Native WebKit checks covered decoded PNG/SVG
   and attachments, math/fonts, code visibility, scrolling and paging.
3. **ableton `.als`**: gzipped xml (see plugin ideas above). the friend
   gift. needs a host release to claim the uti; check what uti live
   registers with `spacebar-cli match set.als` on a mac that has live.
4. **ai model files** (safe, header-only, never executes anything):
   - `.safetensors`: 8-byte little-endian header length, then utf-8 json
     with tensor names, dtypes, shapes, offsets, plus `__metadata__`. show
     the table and the total parameter count. bytes input is fine for the
     header but the files are GBs: needs a host-side "first N bytes" input
     (e.g. `"input": "head", "headBytes": 1048576`) or a native parser.
   - `.gguf`: magic + version + key/value metadata (architecture, context
     length, tokenizer…) + tensor infos, all in the header. same "head"
     input.
   - `.onnx`: protobuf; graph nodes, inputs/outputs, opset. needs a small
     vendored protobuf decoder; initializers can be huge, head input again.
   - `.pt`/`.pth`/`.ckpt`: zip archives containing pickles. list the zip
     entries and run a pickle *disassembler* (opcode walk, like python's
     pickletools) to show which classes/modules it references. never
     unpickle, say so in the panel.
   - `.pkl`/`.pickle`: same disassembler, standalone. 264 of them here.
   - `.npy`/`.npz`: tiny header (dtype, shape, fortran order), npz is a zip
     of npy. easy and safe.
   - `.h5`: hdf5 group/dataset tree; needs a vendored hdf5 reader (jsfive
     exists) or a native one. medium.
5. **srt/vtt** subtitles (1000+ here): timestamps + text, trivial, text
   input. show cue number, start → end, text; maybe total duration and cue
   count at the top. both utis exist on macos? check with spacebar-cli
   match; claim them in a host release if needed.
6. **tsv**: finder shows nothing useful for .tsv today (checked 2026-10-19),
   so this is a clear win: real columns, sortable like the sqlite viewer,
   `public.tab-separated-values-text` to claim. vendor papaparse or
   hand-roll a tab splitter. **csv**: finder does preview it (as plain
   text, not great). plist proved apple yields to a third-party extension
   on 15.7, so a csv plugin with real columns is probably possible too;
   same plugin, second uti (`public.comma-separated-values-text`), test
   first.
7. **stl** (1074, apple already previews 3d), **step/dxf**: skip for now.
8. **.env / .lock / .log**: text with light highlighting; cheap, but
   .env is a dotfile with no extension in finder's eyes (uti lookup by
   extension fails), so probably not reachable.

a fresh agent doing one of these: read PLUGINS.md, then
`scripts/new-plugin.sh <id> <ext>`, and check whether the uti is already
in Extension/Info.plist (plist is now claimed; csv, tsv and Ableton still
need host changes and a release before Homebrew users can preview them).

## plugins with a build step (typescript, vite)

- today a plugin is whatever is in the folder; the host loads `entry` and
  nothing else. that already works with a build step as long as the built
  output lands in the plugin folder (vite `build.outDir` = the plugin dir,
  relative asset paths via `base: "./"`). nothing in the host needs to
  change for that.
- what's missing is the recipe and a template: a `templates/vite-ts/`
  plugin with `plugin.json` at the root, `src/` in typescript, a vite config
  that builds into `dist/` and `"entry": "dist/index.html"`, plus `.d.ts`
  typings for `window.spacebar` (host, plugin, file, input, data per input
  kind, theme, done/fail/log). `scripts/new-plugin.sh --vite` could copy it.
- decide what gets shipped/installed: the whole folder with `src/` and
  `node_modules/` excluded (a `.spacebarignore`? or only ship `dist/` +
  `plugin.json`), and what the validator checks for built plugins (no
  absolute urls in dist, entry exists).
- hot reload in the dev harness: vite's dev server would need network
  (blocked by design); instead watch the plugin folder and reload the
  webview on change, which works with `vite build --watch`.
