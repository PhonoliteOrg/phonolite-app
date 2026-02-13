#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUST_ROOT="$ROOT_DIR/native/quic_client"

OUT_DIR="$ROOT_DIR/ios"
TARGET_DIR="$OUT_DIR/target"
LIB_OUT="$OUT_DIR/libphonolite_quic.a"

PLATFORM_NAME="${PLATFORM_NAME:-iphoneos}"
SDK_NAME="iphoneos"
if [[ "$PLATFORM_NAME" == *"simulator"* ]]; then
  SDK_NAME="iphonesimulator"
fi

export SDKROOT="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
export IPHONEOS_DEPLOYMENT_TARGET="12.0"
export CMAKE_OSX_SYSROOT="$SDKROOT"
export CMAKE_OSX_DEPLOYMENT_TARGET="$IPHONEOS_DEPLOYMENT_TARGET"

mkdir -p "$TARGET_DIR"

TARGETS=()
if [[ "$SDK_NAME" == "iphonesimulator" ]]; then
  TARGETS=(x86_64-apple-ios aarch64-apple-ios-sim)
else
  TARGETS=(aarch64-apple-ios)
fi

ARCH_LIBS=()
for target in "${TARGETS[@]}"; do
  case "$target" in
    aarch64-apple-ios)
      SDK_NAME="iphoneos"
      ARCH="arm64"
      TARGET_TRIPLE="arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}"
      ;;
    aarch64-apple-ios-sim)
      SDK_NAME="iphonesimulator"
      ARCH="arm64"
      TARGET_TRIPLE="arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator"
      ;;
    x86_64-apple-ios)
      SDK_NAME="iphonesimulator"
      ARCH="x86_64"
      TARGET_TRIPLE="x86_64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator"
      ;;
  esac

  export SDKROOT="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
  export CMAKE_OSX_SYSROOT="$SDKROOT"
  export CMAKE_OSX_ARCHITECTURES="$ARCH"
  export CC="$(xcrun --sdk "$SDK_NAME" --find clang)"
  export CXX="$(xcrun --sdk "$SDK_NAME" --find clang++)"
  export AR="$(xcrun --sdk "$SDK_NAME" --find ar)"
  export RANLIB="$(xcrun --sdk "$SDK_NAME" --find ranlib)"
  export CFLAGS="-isysroot $SDKROOT -target $TARGET_TRIPLE"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-isysroot $SDKROOT"

  cargo build \
    --manifest-path "$RUST_ROOT/Cargo.toml" \
    --release \
    --target "$target" \
    --target-dir "$TARGET_DIR"
  ARCH_LIBS+=("$TARGET_DIR/$target/release/libphonolite_quic.a")
done

if [[ ${#ARCH_LIBS[@]} -eq 1 ]]; then
  cp "${ARCH_LIBS[0]}" "$LIB_OUT"
else
  lipo -create "${ARCH_LIBS[@]}" -output "$LIB_OUT"
fi

echo "Built $LIB_OUT"
