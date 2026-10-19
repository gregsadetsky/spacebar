# spacebar

plugin-based quick look previews for macos. press space on a `.geojson` or
`.sqlite3` file in finder and get a map or a table browser. a plugin is a
folder of html/js; the host feeds it the file and shows the result.

ships with two plugins: `geojson` (zero deps, inline world outline) and
`sqlite` (host parses the db natively, plugin renders tables, rows, schema).

## install

```
brew tap <you>/tap && brew install --cask spacebar   # soon
```

or from source (command line tools are enough, no xcode needed):

```
git clone … spacebar && cd spacebar
make install        # builds, copies to ~/Applications, registers the extension
make samples        # writes samples/*.geojson and samples/*.sqlite3 to try
```

if nothing shows up, turn the extension on: system settings → general →
login items & extensions → quick look → spacebar. the app's status tab
tells you whether it is enabled.

## use

press space on a file. the app window lists plugins, lets you turn them
on/off, install a folder as a plugin, and has a dev harness
(window → dev harness) that renders any file with any plugin and shows the
plugin's console output.

every preview logs one line; when something looks wrong:

```
/usr/bin/log show --info --predicate 'subsystem == "io.spacebar"' --last 5m
```

## write a plugin

see [PLUGINS.md](PLUGINS.md). short version: a folder with `plugin.json`
and `index.html`, read `window.spacebar.data`, call `spacebar.done()`.
no network, no filesystem, no build step required.

## develop

```
make build     # build/Spacebar.app (ad-hoc signed)
make test      # unit tests (xctest, or a tiny shim when xcode is missing) + plugin validation
make smoke     # end to end through the real extension, with samples
make release   # dist/Spacebar-<version>.zip + sha256
```

supported file types are fixed at build time (`Extension/Info.plist`);
adding a type means a new release. files of a listed type with no plugin
get a plain text view (text types) or a short note. [NOTES.md](NOTES.md)
has the macos surprises met along the way.
