# Release builds

The release artifacts are written to `dist/`.

- Android: `flutter build apk --release --no-pub` from `frontend/flutter`.
- Windows: run `scripts/build-windows.ps1` on a Windows machine with Flutter desktop enabled. Windows desktop binaries cannot be produced by Flutter on macOS.
- iOS: run `scripts/build-ios-ipa.sh` on macOS with Xcode. With an Apple signing identity it exports an installable IPA; without one (or with `IOS_SIGNING_MODE=unsigned`) it creates `dist/SyncBox-iOS-unsigned.ipa` for import and re-signing. This package has a replaceable local signature and no provisioning profile. Sign it with your own certificate and profile before installing.
