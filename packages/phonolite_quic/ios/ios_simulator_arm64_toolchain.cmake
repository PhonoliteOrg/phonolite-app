# quiche 0.20.x treats arm64 iOS as a device build while Rust can target
# aarch64-apple-ios-sim. Force BoringSSL's nested CMake build back to the
# simulator SDK so its assembly objects match the final simulator link.
if(DEFINED ENV{SDKROOT})
  set(CMAKE_OSX_SYSROOT "$ENV{SDKROOT}" CACHE PATH "iOS simulator SDK" FORCE)
endif()
