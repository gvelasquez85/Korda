#!/bin/zsh
set -eu
cd "${0:A:h}"
korda_output="${KORDA_APP_OUTPUT:-build/Korda.app}"
korda_mode="${KORDA_BUILD_MODE:-debug}"
if [[ "$korda_mode" == release ]]; then korda_optimization=(-O -whole-module-optimization); else korda_optimization=(-Onone); fi
mkdir -p "$korda_output/Contents/MacOS" build/toolchain-overlay
: > build/toolchain-overlay/empty.modulemap
python3 - <<'PYOVERLAY'
import json, os
json.dump({'version': 0, 'roots': [{'type': 'file', 'name': '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap', 'external-contents': os.path.abspath('build/toolchain-overlay/empty.modulemap')}]}, open('build/toolchain-overlay/overlay.json', 'w'))
PYOVERLAY
clang -target x86_64-apple-macos14.0 -std=c11 -O2 -c Sources/DigitalAudioAtomics.c -o build/digital-audio-atomics.o
swiftc -vfsoverlay build/toolchain-overlay/overlay.json -parse-as-library "${korda_optimization[@]}" -Xfrontend -warn-long-expression-type-checking=200 -target x86_64-apple-macos14.0 Sources/DigitalAudio.swift Sources/DigitalAudioView.swift build/digital-audio-atomics.o Sources/Mapping.swift Sources/HIDIdentity.swift Sources/USBInventory.swift Sources/HIDFeatureDiscovery.swift Sources/KeyboardDiversion.swift Sources/KeyboardDiversionController.swift Sources/ReceiverManagement.swift Sources/MouseReportDecoder.swift Sources/ReceiverReportDecoder.swift Sources/Main.swift -o "$korda_output/Contents/MacOS/Korda" -framework AudioToolbox -framework CoreAudio -framework SwiftUI -framework AppKit -framework IOKit -framework AVFoundation -framework ApplicationServices
cat > "$korda_output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Korda</string><key>CFBundleIdentifier</key><string>local.german.korda</string><key>CFBundleName</key><string>Korda</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.9.1</string><key>CFBundleVersion</key><string>20261102.2</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSAudioCaptureUsageDescription</key><string>Korda procesa localmente el audio de la salida elegida para ajustar su volumen. No graba ni envía audio.</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
mkdir -p "$korda_output/Contents/Resources"
cp Resources/Korda.icns "$korda_output/Contents/Resources/Korda.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Korda.icns" "$korda_output/Contents/Info.plist"
codesign --force --sign - "$korda_output"
swiftc -vfsoverlay build/toolchain-overlay/overlay.json Sources/Mapping.swift Tests/MappingTests.swift -o build/mapping-tests
build/mapping-tests
