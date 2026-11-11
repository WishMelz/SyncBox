#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLE="$ROOT/frontend/apple"
OUT="${IOS_OUTPUT_DIR:-$ROOT/dist}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/syncbox-ios-package.XXXXXX")"
ARCHIVE="$WORK/SyncBox.xcarchive"
BUILD_ARGS=()
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  BUILD_ARGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi
SIGNING_MODE="${IOS_SIGNING_MODE:-auto}"
case "$SIGNING_MODE" in
  auto)
    if security find-identity -v -p codesigning 2>/dev/null | grep -Eq '^[[:space:]]*[1-9][0-9]* valid identities found'; then
      SIGNING_MODE=signed
    else
      SIGNING_MODE=unsigned
    fi
    ;;
  signed|unsigned) ;;
  *) echo 'IOS_SIGNING_MODE must be auto, signed, or unsigned.' >&2; exit 2 ;;
esac
if [[ "$SIGNING_MODE" == signed ]]; then
  "$XCODEBUILD" archive -project "$APPLE/SyncBox.xcodeproj" -scheme SyncBox -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" "${BUILD_ARGS[@]}"
  EXPORT_PLIST="$WORK/ExportOptions.plist"
  cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>debugging</string>
<key>signingStyle</key><string>automatic</string>
<key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST
  "$XCODEBUILD" -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" -exportOptionsPlist "$EXPORT_PLIST"
  cp "$WORK/export/SyncBox.ipa" "$OUT/SyncBox-iOS.ipa"
  echo "Signed IPA: $OUT/SyncBox-iOS.ipa"
else
  "$XCODEBUILD" archive -project "$APPLE/SyncBox.xcodeproj" -scheme SyncBox -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "${BUILD_ARGS[@]}"
  APP="$ARCHIVE/Products/Applications/SyncBox.app"
  test -d "$APP"
  mkdir -p "$WORK/package/Payload"
  ditto "$APP" "$WORK/package/Payload/SyncBox.app"
  (cd "$WORK/package" && COPYFILE_DISABLE=1 zip -qry "$WORK/SyncBox-iOS-unsigned.ipa" Payload)
  unzip -tq "$WORK/SyncBox-iOS-unsigned.ipa"
  cp "$WORK/SyncBox-iOS-unsigned.ipa" "$OUT/SyncBox-iOS-unsigned.ipa"
  echo "Unsigned IPA (requires signing before installation): $OUT/SyncBox-iOS-unsigned.ipa"
fi
# Keep the archive and diagnostics for inspecting this build without touching older outputs.
echo "Build archive: $ARCHIVE"
