#!/bin/bash
# records the finder quick look demo (web/preview.gif + .mp4). needs: a folder
# ~/Desktop/Spacebar samples with the sample files open in finder, accessibility
# permission for the terminal, and 12 s hands off. frames land in the scratch
# dir named in S=; see the python in git history (commit "finder demo") for the
# compositing step.
# records the finder window plus every other Finder-owned window (any layer)
# wider than 500 pt, 4 fps, with the window list per frame for sorting out later.
S=/private/tmp/claude-501/-Users-g-Desktop-ARTS-spacebar/92eac314-e736-4b1a-9d1a-e162c69bf5e7/scratchpad
DIR="/Users/g/Desktop/Spacebar samples"
rm -rf $S/rec2 && mkdir -p $S/rec2/raw
osascript -e 'tell application "Finder"' -e 'activate' -e 'set w to (first Finder window whose name is "Spacebar samples")' -e 'set current view of w to list view' -e 'set bounds of w to {114, 84, 1614, 1034}' -e "select file \"cities.geojson\" of (POSIX file \"$DIR\" as alias)" -e 'end tell'
sleep 0.5
FW=$($S/winlist | awk -F'\t' '$2=="Finder" && $4=="Spacebar samples" {print $1; exit}')
KNOWN=$($S/winlist | awk -F'\t' '$2=="Finder" {print $1}' | tr '\n' ' ')
echo "finder window $FW, known finder windows: $KNOWN"
(
  for i in $(seq -w 1 44); do
    screencapture -x -o -l "$FW" $S/rec2/raw/f$i.png
    $S/winlist > $S/rec2/raw/w$i.txt
    for P in $($S/winlist | awk -F'\t' -v known=" $KNOWN " '$2=="Finder" && $7 > 500 && index(known, " "$1" ")==0 {print $1}'); do
      screencapture -x -o -l "$P" $S/rec2/raw/p$i-$P.png
    done
    sleep 0.25
  done
) & CAP=$!
osascript <<'AS'
delay 1.0
tell application "Finder" to activate
tell application "System Events" to key code 49
delay 2.5
tell application "System Events" to key code 49
delay 0.8
tell application "Finder" to select file "library.sqlite3" of (POSIX file "/Users/g/Desktop/Spacebar samples" as alias)
delay 0.8
tell application "System Events" to key code 49
delay 2.5
tell application "System Events" to key code 49
delay 1.0
AS
wait $CAP
echo "frames: $(ls $S/rec2/raw/f*.png | wc -l) finder, $(ls $S/rec2/raw/p*.png 2>/dev/null | wc -l) panel"
