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
