#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swiftc \
  "$ROOT_DIR/ios/CustomScanner/DocumentAutoCaptureGate.swift" \
  "$ROOT_DIR/scripts/auto-capture-gate-tests.swift" \
  -o /tmp/react-native-document-scanner-auto-capture-gate-tests

/tmp/react-native-document-scanner-auto-capture-gate-tests
node "$ROOT_DIR/scripts/verify-ios-custom-scanner-invariants.js"
