#!/bin/zsh
set -eu
cd "${0:A:h}"
KORDA_BUILD_MODE=release KORDA_APP_OUTPUT=build/release/Korda.app ./build.sh
./scripts/test.sh
codesign --verify --deep --strict build/release/Korda.app
plutil -lint build/release/Korda.app/Contents/Info.plist
korda_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/release/Korda.app/Contents/Info.plist)
ditto -c -k --sequesterRsrc --keepParent build/release/Korda.app "build/release/Korda-${korda_version}-macOS-Intel.zip"
