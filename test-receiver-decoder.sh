#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/proprietary
swiftc -vfsoverlay build/toolchain-overlay/overlay.json Sources/MouseReportDecoder.swift Sources/ReceiverReportDecoder.swift Tests/ReceiverReportDecoderTests.swift -o build/proprietary/receiver-decoder-tests
build/proprietary/receiver-decoder-tests
