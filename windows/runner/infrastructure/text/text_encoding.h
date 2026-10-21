#ifndef RUNNER_INFRASTRUCTURE_TEXT_TEXT_ENCODING_H_
#define RUNNER_INFRASTRUCTURE_TEXT_TEXT_ENCODING_H_

#include <optional>
#include <string>

// Converts a null-terminated UTF-16 string, returning an empty string on failure.
std::string utf8_from_utf16(const wchar_t* utf16_string);

// Preserves the path's spelling and rejects invalid UTF-8.
std::optional<std::wstring> utf16_from_utf8(const std::string& utf8_string);

#endif // RUNNER_INFRASTRUCTURE_TEXT_TEXT_ENCODING_H_
