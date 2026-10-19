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
