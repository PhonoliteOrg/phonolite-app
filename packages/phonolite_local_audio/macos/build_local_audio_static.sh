#!/bin/bash
set -euo pipefail

package_directory="$(cd "$(dirname "$0")/.." && pwd -P)"
bash "$package_directory/../../native/apple/Scripts/build_rust_static.sh" \
  "$package_directory/native/local_audio/Cargo.toml" \
  "phonolite_local_audio" "$package_directory/macos/libphonolite_local_audio.a"
