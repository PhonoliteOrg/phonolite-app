#include "runner/infrastructure/text/text_encoding.h"

#include <cwchar>

#include <windows.h>

std::string utf8_from_utf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }

  // Remove the trailing null character from the required output length.
  const unsigned int target_length =
      ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, -1, nullptr, 0, nullptr, nullptr) - 1;
  const int input_length = static_cast<int>(std::wcslen(utf16_string));
  std::string utf8_string;

  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }

  utf8_string.resize(target_length);

  const int converted_length =
      ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, input_length, utf8_string.data(),
                            static_cast<int>(target_length), nullptr, nullptr);

  if (converted_length == 0) {
    return std::string();
  }

  return utf8_string;
}

std::optional<std::wstring> utf16_from_utf8(const std::string& utf8_string) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
                                         static_cast<int>(utf8_string.length()), nullptr, 0);

  if (length == 0) {
    return std::nullopt;
  }

  std::wstring utf16_string(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(), static_cast<int>(utf8_string.length()),
                      utf16_string.data(), length);

  return utf16_string;
}
