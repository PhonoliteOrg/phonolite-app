#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUST_ROOT="$ROOT_DIR/native/local_audio"

OUT_DIR="$ROOT_DIR/macos"
TARGET_DIR="$OUT_DIR/target"
LIB_OUT="$OUT_DIR/libphonolite_local_audio.a"

mkdir -p "$TARGET_DIR"

TARGETS=(x86_64-apple-darwin aarch64-apple-darwin)
ARCH_LIBS=()
for target in "${TARGETS[@]}"; do
  cargo build \
    --manifest-path "$RUST_ROOT/Cargo.toml" \
    --release \
    --target "$target" \
    --target-dir "$TARGET_DIR"
  ARCH_LIBS+=("$TARGET_DIR/$target/release/libphonolite_local_audio.a")
done

lipo -create "${ARCH_LIBS[@]}" -output "$LIB_OUT"
echo "Built $LIB_OUT"
