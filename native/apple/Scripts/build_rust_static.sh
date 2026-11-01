#!/bin/bash
set -euo pipefail

manifest_path="$1"
library_name="$2"
library_output="$3"

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: Install Rust and add the x86_64-apple-darwin and aarch64-apple-darwin targets." >&2
  exit 127
fi

source "$(dirname "$0")/macos_build_environment.sh"

build_directory="${DERIVED_FILE_DIR:-$(dirname "$library_output")}/rust/$library_name"
requested_architectures="${ARCHS:-arm64 x86_64}"
architecture_libraries=()

for architecture in $requested_architectures; do
  case "$architecture" in
    arm64) rust_target=aarch64-apple-darwin ;;
    x86_64) rust_target=x86_64-apple-darwin ;;
    *) echo "error: Unsupported macOS architecture: $architecture" >&2; exit 1 ;;
  esac

  cargo build --locked --release --manifest-path "$manifest_path" \
    --target "$rust_target" --target-dir "$build_directory"
  architecture_libraries+=("$build_directory/$rust_target/release/lib$library_name.a")
done

mkdir -p "$(dirname "$library_output")"
xcrun lipo -create "${architecture_libraries[@]}" -output "$library_output"
xcrun lipo "$library_output" -verify_arch $requested_architectures
