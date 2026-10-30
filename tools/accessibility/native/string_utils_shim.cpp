// Test-only formatting shim: the SDK checkout omits double-conversion.
// The accessibility tree implementation is compiled unchanged.
#include "base/string_utils.h"
#include <algorithm>
#include <cctype>
#include <codecvt>
#include <locale>
#include <sstream>

namespace base {
std::u16string ASCIIToUTF16(std::string value) { return {value.begin(), value.end()}; }
std::u16string UTF8ToUTF16(std::string value) {
  return std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>{}.from_bytes(value);
}
std::string UTF16ToUTF8(std::u16string value) {
  return std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>{}.to_bytes(value);
}
std::string NumberToString(unsigned int value) { return std::to_string(value); }
std::string NumberToString(int32_t value) { return std::to_string(value); }
std::string NumberToString(float value) { return std::to_string(value); }
std::string NumberToString(double value) { return std::to_string(value); }
std::u16string NumberToString16(unsigned int value) { return ASCIIToUTF16(NumberToString(value)); }
std::u16string NumberToString16(int32_t value) { return ASCIIToUTF16(NumberToString(value)); }
std::u16string NumberToString16(float value) { return ASCIIToUTF16(NumberToString(value)); }
std::u16string NumberToString16(double value) { return ASCIIToUTF16(NumberToString(value)); }
std::string ToUpperASCII(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return std::toupper(c); });
  return value;
}
std::string ToLowerASCII(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return std::tolower(c); });
  return value;
}
template<typename T> T join(std::vector<T> values, T delimiter) {
  T result;
  for (size_t i = 0; i < values.size(); i++) {
    if (i) result += delimiter;
    result += values[i];
  }
  return result;
}
std::string JoinString(std::vector<std::string> values, std::string delimiter) { return join(values, delimiter); }
std::u16string JoinString(std::vector<std::u16string> values, std::u16string delimiter) { return join(values, delimiter); }
template<typename T> void replace(T value, T from, T to, T* out) {
  size_t offset = 0;
  while (!from.empty() && (offset = value.find(from, offset)) != T::npos) {
    value.replace(offset, from.size(), to);
    offset += to.size();
  }
  *out = value;
}
void ReplaceChars(std::string value, std::string from, std::string to, std::string* out) { replace(value, from, to, out); }
void ReplaceChars(std::u16string value, std::u16string from, std::u16string to, std::u16string* out) { replace(value, from, to, out); }
bool LowerCaseEqualsASCII(std::string first, std::string second) { return ToLowerASCII(first) == ToLowerASCII(second); }
bool ContainsOnlyChars(std::u16string value, char16_t c) { return value.find_first_not_of(c) == std::u16string::npos; }
const std::string& EmptyString() { static const std::string value; return value; }
}
