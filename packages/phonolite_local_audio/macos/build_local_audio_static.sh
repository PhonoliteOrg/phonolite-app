#!/bin/bash
set -euo pipefail

if [[ -f "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
else
  export PATH="$HOME/.cargo/bin:$PATH"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust from https://rustup.rs/ or ensure cargo is on PATH." >&2
  exit 127
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
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
