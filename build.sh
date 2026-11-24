#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
project="$PWD"
stage="$(mktemp -d "$project/.paste-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Paste++.app"

iconset="$stage/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" Assets/AppIcon.png \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" Assets/AppIcon.png \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cp Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null
xcrun swiftc -swift-version 6 -O -target "$(uname -m)-apple-macosx14.0" \
    Sources/*.swift -o "$app/Contents/MacOS/PastePlusPlus"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

if [[ -e "$project/Paste++.app" ]]; then
    mv "$project/Paste++.app" "$stage/previous.app"
fi
if ! mv "$app" "$project/Paste++.app"; then
    if [[ -e "$stage/previous.app" ]]; then
        mv "$stage/previous.app" "$project/Paste++.app"
    fi
    exit 1
fi
printf '%s\n' "$project/Paste++.app"
