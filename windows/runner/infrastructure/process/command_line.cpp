#include "runner/infrastructure/process/command_line.h"

#include <windows.h>

// Shell declarations require the Windows base types first.
#include <shellapi.h>

#include "runner/infrastructure/text/text_encoding.h"

std::vector<std::string> get_command_line_arguments() {
  int argument_count;
  wchar_t** arguments = ::CommandLineToArgvW(::GetCommandLineW(), &argument_count);

  if (arguments == nullptr) {
    return {};
  }

  std::vector<std::string> command_line_arguments;

  for (int index = 1; index < argument_count; index++) {
    command_line_arguments.push_back(utf8_from_utf16(arguments[index]));
  }

  ::LocalFree(arguments);

  return command_line_arguments;
}
