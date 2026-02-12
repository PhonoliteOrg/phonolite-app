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

mkdir -p "$TARGET_DIR"

TARGETS=()
if [[ "$SDK_NAME" == "iphonesimulator" ]]; then
  TARGETS=(x86_64-apple-ios aarch64-apple-ios-sim)
else
  TARGETS=(aarch64-apple-ios)
fi

ARCH_LIBS=()
for target in "${TARGETS[@]}"; do
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
