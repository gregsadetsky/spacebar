# Spacebar

Spacebar lets you preview lots of different kinds of files in the macOS Finder, like .sqlite3 and .geojson

It also lets developers write plugins to support more kinds of files - just by writing html and javascript!

![Quick Look in Finder showing a GeoJSON map, then a SQLite database](web/preview.gif)

## Install

```
brew tap gregsadetsky/tap && brew install --cask spacebar
```

> Note: the app is not currently signed with an Apple developer id (I'll do it after I get 10ish stars on GitHub!).
>
> For now, either go to System Settings → Privacy & Security → (find the app at the bottom of the window, then click) Open Anyway
>
> ... or, run  
> `xattr -dr com.apple.quarantine ~/Applications/Spacebar.app`

If previews don't show, go to: *System Settings → General → Login Items & Extensions → Quick Look* and make sure that Spacebar is enabled

## Notes

- a plugin is a folder with: plugin.json, index.html, your js - see [PLUGINS.md](https://github.com/gregsadetsky/spacebar/blob/main/PLUGINS.md)
- Spacebar ships with .geojson and .sqlite3 out of the box
- to write your own plugin, run `scripts/new-plugin.sh`

## How to develop

(you don't need to do this to write plugins)

`make install`, `make test`, `make smoke`, `make release`

MIT
