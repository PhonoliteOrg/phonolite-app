#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
if [[ "${1:-}" == "--help" || $# -eq 0 ]]; then
  cat <<'HELP'
Usage: bash tools/ui_tests/run_player_controls.sh DEVICE_ID [flutter drive options...]

Tests the visible compact/expanded playbar on a signed-in physical phone in profile mode.
Plays audio, changes HQ/MQ/LQ, taps transport, seek, volume, shuffle, repeat, Like,
playlist-add, output picker and artwork navigation. Likes/preferences are restored;
an isolated temporary playlist is deleted. Existing playback/queue is replaced.
Checks native progress plus independent real encoded-stream samples at 160/96/48 kbps.
An alternate physical output route requires suitable hardware and is not fabricated.
Reports: build/player-controls/latest.txt. The app stays installed after testing.
Restore the normal app afterward: flutter run --profile --no-dds -t lib/main.dart -d DEVICE_ID
HELP
  exit 0
fi
device_id="$1"
shift
export UI_REPORT_DIR="${UI_REPORT_DIR:-build/player-controls}"
exec "${FLUTTER_BIN:-flutter}" drive --profile --no-dds --keep-app-running \
  --driver=test_driver/player_controls_driver.dart \
  --target=integration_test/player_controls_profile_test.dart \
  --dart-define=UI_CAPTURE_TIMELINE=false -d "$device_id" "$@"
