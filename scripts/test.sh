#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build/tests
for korda_localization in Resources/*.lproj(N); do ditto "$korda_localization" "build/tests/${korda_localization:t}"; done
korda_swift_options=(-target x86_64-apple-macos14.0)
if [[ -f build/toolchain-overlay/overlay.json ]]; then korda_swift_options+=(-vfsoverlay build/toolchain-overlay/overlay.json); fi
check_swift() {
 local korda_test_name="$1"
 shift
 swiftc "${korda_swift_options[@]}" Sources/Localization.swift "$@" -o "build/tests/$korda_test_name"
 if [[ "$korda_test_name" == localization ]]; then "build/tests/$korda_test_name"; else KORDA_LANGUAGE=es "build/tests/$korda_test_name"; fi
}
clang -target x86_64-apple-macos14.0 -std=c11 -O2 Sources/DigitalAudioAtomics.c Tests/DigitalAudioDSPTests.c -framework CoreAudio -framework AudioToolbox -o build/tests/audio-dsp
build/tests/audio-dsp
print 'Digital audio DSP checks passed'
clang -target x86_64-apple-macos14.0 -std=c11 -O2 -c Sources/DigitalAudioAtomics.c -o build/tests/audio-dsp.o
check_swift localization Tests/LocalizationTests.swift
check_swift audio Sources/DigitalAudio.swift Tests/DigitalAudioTests.swift build/tests/audio-dsp.o -framework CoreAudio -framework AudioToolbox
check_swift mappings Sources/Mapping.swift Tests/MappingTests.swift
check_swift receiver-mappings Sources/Mapping.swift Tests/ReceiverMappingTests.swift
check_swift identity Sources/HIDIdentity.swift Tests/HIDIdentityTests.swift
check_swift features Sources/HIDFeatureDiscovery.swift Tests/HIDFeatureDiscoveryTests.swift
check_swift diversion Sources/KeyboardDiversion.swift Tests/KeyboardDiversionTests.swift
check_swift diversion-controller Sources/HIDFeatureDiscovery.swift Sources/KeyboardDiversion.swift Sources/KeyboardDiversionController.swift Tests/KeyboardDiversionControllerTests.swift
check_swift receiver-management Sources/ReceiverManagement.swift Tests/ReceiverManagementTests.swift
check_swift receiver-decoder Sources/MouseReportDecoder.swift Sources/ReceiverReportDecoder.swift Tests/ReceiverReportDecoderTests.swift
check_swift mouse-decoder Sources/MouseReportDecoder.swift Tests/MouseReportDecoderTests.swift
check_swift usb-inventory Sources/USBInventory.swift Tests/USBInventoryTests.swift -framework IOKit
print 'All Korda checks passed. No audio capture or HID firmware writes were started.'
