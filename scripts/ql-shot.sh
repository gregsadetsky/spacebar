#!/bin/bash
# usage: scripts/ql-shot.sh <file> <out.png> [wait-seconds]
# opens <file> in qlmanage -p, screenshots just that window, closes it.
set -euo pipefail
FILE="$1"; OUT="$2"; WAIT="${3:-3}"
qlmanage -p "$FILE" >/dev/null 2>&1 &
QL=$!
sleep "$WAIT"
WID=$(swift - <<'SWIFT' 2>/dev/null
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "qlmanage" {
    let b = w["kCGWindowBounds"] as! [String: Any]
    if (b["Width"] as! Double) > 200 { print(w["kCGWindowNumber"] as! Int); break }
}
SWIFT
)
if [ -z "$WID" ]; then echo "no qlmanage window found"; kill $QL 2>/dev/null || true; exit 1; fi
screencapture -x -o -l "$WID" "$OUT"
kill $QL 2>/dev/null || true
echo "wrote $OUT (window $WID)"
