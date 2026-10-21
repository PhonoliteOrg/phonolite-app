#include "runner/infrastructure/process/console_support.h"

#include <cstdio>
#include <iostream>

#include <io.h>
#include <windows.h>

#include <flutter_windows.h>

void create_and_attach_console() {
  if (!::AllocConsole()) {
    return;
  }

  FILE* unused;

  if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
    _dup2(_fileno(stdout), 1);
  }

  if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
    _dup2(_fileno(stdout), 2);
  }

  std::ios::sync_with_stdio();
  FlutterDesktopResyncOutputStreams();
}
