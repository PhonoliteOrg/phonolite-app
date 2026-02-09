#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OPUS_ROOT="$ROOT_DIR/packages/phonolite_opus/third_party/opus"
SRC_ROOT="$ROOT_DIR/packages/phonolite_opus/src"
OUT_DIR="$ROOT_DIR/macos/Runner/opus_build"
OBJ_DIR="$OUT_DIR/obj"
LIB_OUT="$ROOT_DIR/macos/Runner/libphonolite_opus.a"

rm -rf "$OUT_DIR"
mkdir -p "$OBJ_DIR"

CFLAGS=(
  -O2
  -fPIC
  -std=c99
  -DOPUS_BUILD
  -DHAVE_LRINTF
  -DHAVE_LRINT
  -DUSE_ALLOCA
  -I"$OPUS_ROOT/include"
  -I"$OPUS_ROOT/celt"
  -I"$OPUS_ROOT/silk"
  -I"$OPUS_ROOT/silk/float"
  -I"$SRC_ROOT"
)

EXCLUDE_SEGMENTS=(
  "/arm/"
  "/mips/"
  "/x86/"
  "/dnn/"
  "/doc/"
  "/docs/"
  "/test/"
  "/tests/"
  "/examples/"
  "/apps/"
  "/tools/"
  "/dump_modes/"
  "/cmake/"
  "/training/"
  "/silk/fixed/"
)

EXCLUDE_FILES=(
  "opus_demo.c"
  "opus_compare.c"
  "opus_custom_demo.c"
  "repacketizer_demo.c"
  "qext_compare.c"
)

SOURCES=()
while IFS= read -r src; do
  skip=0
  for seg in "${EXCLUDE_SEGMENTS[@]}"; do
    if [[ "$src" == *"$seg"* ]]; then
      skip=1
      break
    fi
  done
  if [[ $skip -eq 0 ]]; then
    base="$(basename "$src")"
    for fname in "${EXCLUDE_FILES[@]}"; do
      if [[ "$base" == "$fname" ]]; then
        skip=1
        break
      fi
    done
  fi
  if [[ $skip -eq 0 ]]; then
    SOURCES+=("$src")
  fi
 done < <(
  find "$SRC_ROOT" -name '*.c' -print
  find "$OPUS_ROOT/celt" -name '*.c' -print
  find "$OPUS_ROOT/silk" -name '*.c' -print
  find "$OPUS_ROOT/src" -name '*.c' -print
 )

for src in "${SOURCES[@]}"; do
  obj="$OBJ_DIR/$(basename "$src").o"
  clang "${CFLAGS[@]}" -c "$src" -o "$obj"
 done

xcrun libtool -static -o "$LIB_OUT" "$OBJ_DIR"/*.o

echo "Built $LIB_OUT"
