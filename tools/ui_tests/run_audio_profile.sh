#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
if [[ "${1:-}" == "--help" || $# -eq 0 ]]; then
  cat <<'HELP'
Usage: bash tools/ui_tests/run_audio_profile.sh DEVICE_ID [flutter drive options...]

Starts audible playback on the current output and stops it after the suite.
Uses the stored server session and existing downloads. Does not download tracks.
Run on an unlocked physical phone in the foreground; keep its network stable.

Examples:
  bash tools/ui_tests/run_audio_profile.sh DEVICE_ID
  bash tools/ui_tests/run_audio_profile.sh DEVICE_ID --dart-define=AUDIO_MODE=stream
  bash tools/ui_tests/run_audio_profile.sh DEVICE_ID --dart-define=AUDIO_SECONDS=120

Options: AUDIO_MODE=all|stream|local (default all), AUDIO_SECONDS=8..300 (default 30),
AUDIO_ALBUM_ID, AUDIO_LATENCY_BUDGET_MS (default 3000), AUDIO_STALL_MS (default 750).
UI_CAPTURE_TIMELINE=false disables host tracing for a lower-overhead repeat.
Reports: build/audio-profile/latest.txt (override with UI_REPORT_DIR).
The app stays installed to preserve data and Local Network permission.
Restore the ordinary app afterward with flutter run --profile --target lib/main.dart.
HELP
  exit 0
fi
device_id="$1"
shift
export UI_REPORT_DIR="${UI_REPORT_DIR:-build/audio-profile}"
flutter_executable="${FLUTTER_BIN:-flutter}"
exec "$flutter_executable" drive --profile --no-dds --keep-app-running \
  --driver=test_driver/audio_profile_driver.dart \
  --target=integration_test/audio_profile_test.dart \
  -d "$device_id" "$@"
