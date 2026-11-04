# Apple Silicon always has NEON. Keep the intrinsic definitions used by Opus,
# while avoiding its unsupported Darwin runtime-CPU-detection configuration.
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin" AND
   (CMAKE_OSX_ARCHITECTURES STREQUAL "arm64" OR
    (NOT CMAKE_OSX_ARCHITECTURES AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")))
  set(PHONOLITE_OPUS_APPLE_ARM64 ON)
  set(OPUS_MAY_HAVE_NEON OFF CACHE BOOL "Use runtime NEON detection" FORCE)
  set(OPUS_PRESUME_NEON ON CACHE BOOL "Apple Silicon always supports NEON" FORCE)
endif()

function(phonolite_opus_enable_apple_arm64 target)
  if(PHONOLITE_OPUS_APPLE_ARM64)
    target_compile_definitions(${target} PRIVATE
      OPUS_ARM_MAY_HAVE_NEON
      OPUS_ARM_MAY_HAVE_NEON_INTR
    )
  endif()
endfunction()
