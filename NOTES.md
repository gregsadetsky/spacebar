# notes

running log of surprises and deviations from SPACEBAR_PLAN.md. newest first.

## 2026-10-18 no xcode on this machine, build with swiftc

only command line tools are installed (no Xcode.app), so xcodegen + xcodebuild
isn't an option. the CLT sdk has QuickLookUI, WebKit, Foundation's
`_NSExtensionMain` and libsqlite3, so the Makefile assembles the .app and
.appex bundles by hand: swiftc per target, plists copied in, codesign ad-hoc.
no project.yml. if this ever breaks on a newer os, xcodegen is the fallback.

## 2026-10-18 `.geojson` is already `public.geojson` on macos 15

CoreTypes (system) exports `public.geojson`, conforming to `public.json`,
tags `.geojson` and `application/geo+json`. an imported `io.spacebar.geojson`
declaration can't win against a system type, so the extension lists
`public.geojson` in QLSupportedContentTypes instead. whether apple's
"reserved json" rule also swallows `public.geojson` is unknown until tested.

`.sqlite` / `.sqlite3` resolve to dynamic utis, so `io.spacebar.sqlite` is
declared (imported) by the app.

## 2026-10-18 app group container: first read costs 1.0 to 1.5 s per extension process

measured with os_log timestamps on macos 15.7.7, ad-hoc signed: in a fresh
SpacebarQuickLook process the first read of any file under
`~/Library/Group Containers/group.io.spacebar/` takes 1020 to 2100 ms, the
second read 0 to 7 ms. `containerURL(forSecurityApplicationGroupIdentifier:)`
itself is instant. reading from the extension's own container
(`~/Library/Containers/io.spacebar.app.QuickLook/Data/...`) takes 0 ms.
quick look spawns a new extension process for most previews, so the group
container would eat half the 3 s plugin budget every time.

decision: `Paths.strategy = .extensionContainer`. the non-sandboxed app
writes into the extension's container directly. app-group entitlements
dropped from both targets. `.appGroup` stays as the one-line switch.

## 2026-10-18 reinstalling under a running app drops the extension registration

`rm -rf` + `cp -R` of the app while pkd still had the old appex registered:
`pluginkit -a` right after the copy succeeded, then pkd processed the
deletion and the extension vanished (`pluginkit -m -i` → no matches, quick
look fell back to the generic icon preview). scripts/install.sh now quits the
app, `pluginkit -r`s the old path, sleeps, copies, re-adds, and verifies.

## 2026-10-18 `log` is a zsh builtin

`log show ...` in zsh silently runs the shell builtin and prints nothing
useful. always `/usr/bin/log`. cost me 15 minutes of false negatives.
