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
