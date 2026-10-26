#include "runner/infrastructure/shell/application_identity.h"

#include <memory>
#include <type_traits>

#include <windows.h>

#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include "phonolite_app_identity.h"

namespace {

using Microsoft::WRL::ComPtr;
using RegistryKey = std::unique_ptr<std::remove_pointer_t<HKEY>, decltype(&::RegCloseKey)>;
using TaskString = std::unique_ptr<wchar_t, decltype(&::CoTaskMemFree)>;

std::wstring executable_path() {
  std::wstring buffer(32768, L'\0');
  const DWORD length = ::GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));

  if (length == 0 || length >= buffer.size()) {
    return {};
  }

  buffer.resize(length);

  return buffer;
}

bool write_string(HKEY key, const wchar_t* name, const std::wstring& value) {
  const auto bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));

  return ::RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()), bytes) == ERROR_SUCCESS;
}

bool register_display_metadata(const std::wstring& executable) {
  const std::wstring path = std::wstring(L"Software\\Classes\\AppUserModelId\\") + phonolite_identity::app_id;
  HKEY handle = nullptr;
  const LSTATUS status = ::RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0,
                                           KEY_SET_VALUE | KEY_WOW64_64KEY, nullptr, &handle, nullptr);

  if (status != ERROR_SUCCESS) {
    return false;
  }

  const RegistryKey key(handle, ::RegCloseKey);
  const auto directory = executable.substr(0, executable.find_last_of(L"\\/"));
  const auto icon = directory + L"\\data\\flutter_assets\\assets\\images\\phonolite-logo.png";

  return write_string(key.get(), L"DisplayName", phonolite_identity::display_name) &&
         write_string(key.get(), L"IconUri", icon);
}

bool register_shortcut(const std::wstring& executable) {
  PWSTR path = nullptr;
  const HRESULT status = ::SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE, nullptr, &path);
  const TaskString programs(path, ::CoTaskMemFree);

  if (FAILED(status)) {
    return false;
  }

  const auto directory = std::wstring(programs.get()) + L"\\" + phonolite_identity::shortcut_directory;

  if (!::CreateDirectoryW(directory.c_str(), nullptr) && ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return false;
  }

  const auto shortcut = directory + L"\\" + phonolite_identity::shortcut_filename;

  return ensure_application_shortcut(shortcut, executable, phonolite_identity::app_id,
                                     phonolite_identity::display_name);
}

} // namespace

bool configure_application_identity() {
  // All builds set their identity before Shell heuristics or SMTC can cache one.
  const HRESULT process = ::SetCurrentProcessExplicitAppUserModelID(phonolite_identity::app_id);
  const auto executable = executable_path();

  if (FAILED(process) || executable.empty()) {
    return false;
  }

  const bool metadata = register_display_metadata(executable);
  const bool shortcut = register_shortcut(executable);

  return metadata && shortcut;
}

bool ensure_application_shortcut(const std::wstring& shortcut_path, const std::wstring& executable_path,
                                 const std::wstring& app_id, const std::wstring& display_name) {
  ComPtr<IShellLinkW> link;
  HRESULT status = ::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));

  if (FAILED(status)) {
    return false;
  }

  ComPtr<IPersistFile> file;
  status = link.As(&file);

  if (FAILED(status)) {
    return false;
  }

  const bool existing = ::GetFileAttributesW(shortcut_path.c_str()) != INVALID_FILE_ATTRIBUTES;

  if (existing) {
    if (FAILED(file->Load(shortcut_path.c_str(), STGM_READWRITE))) {
      return false;
    }
  } else {
    const auto directory = executable_path.substr(0, executable_path.find_last_of(L"\\/"));

    if (FAILED(link->SetPath(executable_path.c_str())) || FAILED(link->SetWorkingDirectory(directory.c_str())) ||
        FAILED(link->SetDescription(display_name.c_str())) ||
        FAILED(link->SetIconLocation(executable_path.c_str(), 0))) {
      return false;
    }
  }

  ComPtr<IPropertyStore> properties;
  status = link.As(&properties);

  if (FAILED(status)) {
    return false;
  }

  PROPVARIANT previous{};
  status = properties->GetValue(PKEY_AppUserModel_ID, &previous);
  const bool matching = SUCCEEDED(status) && previous.vt == VT_LPWSTR && previous.pwszVal && app_id == previous.pwszVal;
  ::PropVariantClear(&previous);

  if (existing && matching) {
    return true;
  }

  PROPVARIANT value{};
  status = ::InitPropVariantFromString(app_id.c_str(), &value);

  if (FAILED(status)) {
    return false;
  }

  status = properties->SetValue(PKEY_AppUserModel_ID, value);
  ::PropVariantClear(&value);

  return SUCCEEDED(status) && SUCCEEDED(properties->Commit()) && SUCCEEDED(file->Save(shortcut_path.c_str(), TRUE));
}
