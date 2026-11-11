#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../frontend/flutter"
flutter pub get
flutter analyze
flutter test
