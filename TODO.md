# todo

- **no update path**: a brew-installed copy only changes through a new
  release + cask bump (tag vX.Y.Z, ci attaches the zip, copy the sha256 into
  homebrew-tap/Casks/spacebar.rb). even a plugin-only fix needs that, since
  bundled plugins live inside the app bundle. the dev loop (`make install`)
  must not run next to the brew copy: two apps register the same extension.
  options: a `make bump VERSION=` that tags + updates the cask; the app
  checking github releases and offering the update; or shipping plugins
  separately from the app so they update on their own.
- status tab says "press space on a .geojson or .sqlite3 file": hardcoded.
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
  OnePreview, Parkour) for what people ask for. ipynb first candidate.

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
- other candidates already in QLSupportedContentTypes with no plugin yet:
  parquet, arrow/feather, ipynb (render cells + outputs), toml, kml, mbtiles
  / pmtiles (map), har, jsonl, wasm (exports/imports), npy/npz, h5, fit/tcx
  (track on the map, reusing the geojson renderer).
