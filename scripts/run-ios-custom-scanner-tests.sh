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
