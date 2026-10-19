# spacebar

quick look previews from plugins. a plugin is a folder of html/js; press
space on a file in finder, the plugin renders it. ships with geojson and
sqlite.

## install

```
brew tap gregsadetsky/tap && brew install --cask spacebar
```

the app is not signed with an apple developer id, so macos will refuse to
open it once. then: system settings → privacy & security → open anyway.
or `xattr -dr com.apple.quarantine ~/Applications/Spacebar.app`.

if previews don't appear: system settings → general → login items &
extensions → quick look → spacebar.

## plugins

```
scripts/new-plugin.sh myformat ext   # a working plugin folder
make install                          # it's live, press space
```

[PLUGINS.md](PLUGINS.md) has the contract. file types are fixed at build
time (`Extension/Info.plist`); new ones need a release.

## build

command line tools or xcode. `make install`, `make test`, `make smoke`,
`make release`. [NOTES.md](NOTES.md) is the list of macos surprises.

mit.
