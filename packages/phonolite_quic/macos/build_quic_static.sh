#!/bin/bash
set -euo pipefail

package_directory="$(cd "$(dirname "$0")/.." && pwd -P)"
bash "$package_directory/../../native/apple/Scripts/build_rust_static.sh" \
  "$package_directory/native/quic_client/Cargo.toml" \
  "phonolite_quic" "$package_directory/macos/libphonolite_quic.a"
