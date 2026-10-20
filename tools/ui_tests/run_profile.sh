#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
if [[ "${1:-}" == "--help" || $# -eq 0 ]]; then
  cat <<'HELP'
Usage: bash tools/ui_tests/run_profile.sh DEVICE_ID [FEATURES_OR_JOURNEYS] [flutter drive options...]

Examples:
  bash tools/ui_tests/run_profile.sh DEVICE_ID
  bash tools/ui_tests/run_profile.sh DEVICE_ID player
  bash tools/ui_tests/run_profile.sh DEVICE_ID library,playlists
  bash tools/ui_tests/run_profile.sh DEVICE_ID player.tray_transition --dart-define=UI_REPEATS=5

Features: navigation, library, playlists, liked, settings, stats, player
Use a physical iPhone/Android device for profile measurements. Find its ID with flutter devices.
This launches a test entry point and replaces the running app process. Saved app data is reused.
The app is kept installed/running after the test so Flutter does not uninstall its data.
Normal builds keep lib/main.dart. Existing session restoration runs normally.
HELP
  exit 0
fi
device_id="$1"
features="${2:-all}"
shift
if [[ $# -gt 0 ]]; then shift; fi
flutter_executable="${FLUTTER_BIN:-flutter}"
exec "$flutter_executable" drive --profile --no-dds --keep-app-running \
  --driver=test_driver/ui_profile_driver.dart \
  --target=integration_test/ui_profile_test.dart \
  -d "$device_id" \
  "--dart-define=UI_FEATURES=$features" "$@"
