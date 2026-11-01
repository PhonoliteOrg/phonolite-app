#!/bin/bash
set -euo pipefail

package_directory="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$package_directory/../../native/apple/Scripts/macos_build_environment.sh"

build_directory="${DERIVED_FILE_DIR:-$package_directory/macos/target}/opus"
requested_architectures="${ARCHS:-arm64 x86_64}"
architecture_libraries=()

for architecture in $requested_architectures; do
  case "$architecture" in
    arm64) processor=aarch64 ;;
    x86_64) processor=x86_64 ;;
    *) echo "error: Unsupported macOS architecture: $architecture" >&2; exit 1 ;;
  esac

  output="$build_directory/$architecture"
  cmake -S "$package_directory/macos" -B "$output" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_SYSTEM_PROCESSOR="$processor" -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_OSX_SYSROOT="$SDKROOT" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
  cmake --build "$output" --config Release --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"
  xcrun libtool -static -o "$output/libphonolite_opus.a" \
    "$output/lib/libphonolite_opus.a" "$output/lib/libopus.a"
  architecture_libraries+=("$output/libphonolite_opus.a")
done

library_output="$package_directory/macos/libphonolite_opus.a"
xcrun lipo -create "${architecture_libraries[@]}" -output "$library_output"
xcrun lipo "$library_output" -verify_arch $requested_architectures
