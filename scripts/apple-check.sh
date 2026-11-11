#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
APPLE_BUILD_DIR="${APPLE_BUILD_DIR:-${TMPDIR:-/tmp}/syncbox-apple-check}"
swift test --package-path "$ROOT/frontend/apple" --scratch-path "$APPLE_BUILD_DIR/tests"
xcodebuild -quiet -project "$ROOT/frontend/apple/SyncBox.xcodeproj" -scheme SyncBox \
  -destination 'platform=macOS' -derivedDataPath "$APPLE_BUILD_DIR/mac" CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project "$ROOT/frontend/apple/SyncBox.xcodeproj" -scheme SyncBox \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$APPLE_BUILD_DIR/ios" CODE_SIGNING_ALLOWED=NO build
