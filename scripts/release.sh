#!/bin/bash
# release build, ad-hoc signed, zipped with a sha256 next to it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
make clean >/dev/null
make build CONFIG=release VERSION="$VERSION" >/dev/null
mkdir -p dist
rm -f "dist/Spacebar-$VERSION.zip"
ditto -c -k --keepParent build/Spacebar.app "dist/Spacebar-$VERSION.zip"
shasum -a 256 "dist/Spacebar-$VERSION.zip" | tee "dist/Spacebar-$VERSION.zip.sha256"
codesign --verify --deep --strict build/Spacebar.app && echo "signature ok (ad-hoc)"
ls -la dist/
