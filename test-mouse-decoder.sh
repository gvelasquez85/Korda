#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/staged
swiftc -vfsoverlay build/toolchain-overlay/overlay.json Sources/MouseReportDecoder.swift Tests/MouseReportDecoderTests.swift -o build/staged/mouse-decoder-tests
build/staged/mouse-decoder-tests
