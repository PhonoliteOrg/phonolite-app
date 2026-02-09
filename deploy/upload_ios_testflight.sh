#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: TestFlight uploads require macOS with Xcode." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: xcrun is not available. Install Xcode command line tools." >&2
  exit 1
fi

echo "Building iOS release IPA..."
flutter build ipa --release

IPA_PATH=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)
if [[ -z "$IPA_PATH" ]]; then
  echo "Error: No IPA found at build/ios/ipa/*.ipa" >&2
  exit 1
fi

echo "Uploading $IPA_PATH to TestFlight..."
if [[ -n "${APPSTORE_API_KEY_ID:-}" && -n "${APPSTORE_API_ISSUER_ID:-}" ]]; then
  xcrun altool --upload-app -f "$IPA_PATH" -t ios \
    --apiKey "$APPSTORE_API_KEY_ID" \
    --apiIssuer "$APPSTORE_API_ISSUER_ID"
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun altool --upload-app -f "$IPA_PATH" -t ios \
    -u "$APPLE_ID" -p "$APP_SPECIFIC_PASSWORD"
else
  cat >&2 <<'EOM'
Error: Missing credentials.
Set either:
  APPSTORE_API_KEY_ID and APPSTORE_API_ISSUER_ID
or:
  APPLE_ID and APP_SPECIFIC_PASSWORD
EOM
  exit 1
fi

echo "Upload complete. Check App Store Connect -> TestFlight for processing status."
