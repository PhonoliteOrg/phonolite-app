#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OPUS_ROOT="$ROOT_DIR/packages/phonolite_opus/third_party/opus"
SRC_ROOT="$ROOT_DIR/packages/phonolite_opus/src"
OUT_DIR="$ROOT_DIR/ios/Runner/opus_build"
OBJ_DIR="$OUT_DIR/obj"
LIB_OUT="$ROOT_DIR/ios/Runner/libphonolite_opus.a"

PLATFORM_NAME="${PLATFORM_NAME:-iphoneos}"
SDK_NAME="iphoneos"
if [[ "$PLATFORM_NAME" == *"simulator"* ]]; then
  SDK_NAME="iphonesimulator"
fi
SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"

MIN_IOS_VERSION="12.0"

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
  -isysroot "$SDK_PATH"
  -mios-version-min="$MIN_IOS_VERSION"
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

ARCHS_LIST=()
if [[ -n "${ARCHS:-}" ]]; then
  ARCHS_LIST=( $ARCHS )
else
  if [[ "$SDK_NAME" == "iphonesimulator" ]]; then
    ARCHS_LIST=(x86_64 arm64)
  else
    ARCHS_LIST=(arm64)
  fi
fi

OBJ_PER_ARCH=()
for arch in "${ARCHS_LIST[@]}"; do
  ARCH_OBJ_DIR="$OBJ_DIR/$arch"
  mkdir -p "$ARCH_OBJ_DIR"
  for src in "${SOURCES[@]}"; do
    obj="$ARCH_OBJ_DIR/$(basename "$src").o"
    clang "${CFLAGS[@]}" -arch "$arch" -c "$src" -o "$obj"
  done
  ARCH_LIB="$OUT_DIR/libphonolite_opus_$arch.a"
  xcrun libtool -static -o "$ARCH_LIB" "$ARCH_OBJ_DIR"/*.o
  OBJ_PER_ARCH+=("$ARCH_LIB")
 done

if [[ ${#OBJ_PER_ARCH[@]} -eq 1 ]]; then
  cp "${OBJ_PER_ARCH[0]}" "$LIB_OUT"
else
  lipo -create "${OBJ_PER_ARCH[@]}" -output "$LIB_OUT"
fi

echo "Built $LIB_OUT"
