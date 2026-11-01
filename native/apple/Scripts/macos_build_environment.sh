#!/bin/bash

# Xcode supplies the SDK and minimum; standalone native checks use these defaults.
if [[ -z "${SDKROOT:-}" || ! -d "$SDKROOT" ]]; then
  SDKROOT="$(xcrun --sdk "${SDKROOT:-macosx}" --show-sdk-path)"
fi
export SDKROOT
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export CMAKE_OSX_SYSROOT="$SDKROOT"
export CMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
