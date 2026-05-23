#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swiftc \
  "$ROOT_DIR/ios/CustomScanner/DocumentAutoCaptureGate.swift" \
  "$ROOT_DIR/scripts/auto-capture-gate-tests.swift" \
  -o /tmp/react-native-document-scanner-auto-capture-gate-tests

/tmp/react-native-document-scanner-auto-capture-gate-tests

swiftc \
  "$ROOT_DIR/ios/CustomScanner/DocumentCornerCalibrator.swift" \
  "$ROOT_DIR/scripts/document-corner-calibrator-tests.swift" \
  -o /tmp/react-native-document-scanner-corner-calibrator-tests

/tmp/react-native-document-scanner-corner-calibrator-tests

swiftc \
  "$ROOT_DIR/scripts/coordinate-mapping-tests.swift" \
  -o /tmp/react-native-document-scanner-coordinate-mapping-tests

/tmp/react-native-document-scanner-coordinate-mapping-tests

node "$ROOT_DIR/scripts/verify-ios-custom-scanner-invariants.js"

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SIM_RUNTIME="$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/ { print $2; exit }')"

if [[ -n "$SIM_RUNTIME" ]]; then
  xcrun --sdk iphonesimulator swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-ios15.1-simulator \
    "$ROOT_DIR/ios/DocScanner/Errors.swift" \
    "$ROOT_DIR/ios/DocScanner/FileUtil.swift" \
    "$ROOT_DIR/ios/DocScanner/ResponseType.swift" \
    "$ROOT_DIR/ios/CustomScanner/DocumentCornerCalibrator.swift" \
    "$ROOT_DIR/ios/CustomScanner/ImageProcessor.swift" \
    "$ROOT_DIR/scripts/image-processor-photo-tests.swift" \
    -o /tmp/react-native-document-scanner-image-processor-photo-tests

  xcrun simctl spawn booted /tmp/react-native-document-scanner-image-processor-photo-tests
else
  echo "Skipping ImageProcessor photo tests because no iOS simulator is booted"
fi
