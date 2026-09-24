#!/bin/zsh
# Builds mdmdmd.app next to this script and installs it into /Applications.
# A real signing identity keeps the app's identity stable across rebuilds.
set -euo pipefail
cd "${0:A:h}"
swift build -c release 2>&1 | tail -3
app=mdmdmd.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/mdmdmd "$app/Contents/MacOS/mdmdmd"
cp Info.plist "$app/Contents/Info.plist"

identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${identity:--}" "$app"
rm -rf "/Applications/$app"
cp -R "$app" /Applications/
echo "installed /Applications/$app (signed as: ${identity:-ad hoc})"
