#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>

#include <windows.h>

#include <propkey.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include "phonolite_app_identity.h"
#include "runner/infrastructure/shell/application_identity.h"

namespace {

using Microsoft::WRL::ComPtr;

void require(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAILED: " << message << '\n';
    std::exit(EXIT_FAILURE);
  }
}

ComPtr<IShellLinkW> read_shortcut(const std::wstring& path) {
  ComPtr<IShellLinkW> link;
  require(SUCCEEDED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))),
          "Create an in-process Shell link for readback");
  ComPtr<IPersistFile> file;
  require(SUCCEEDED(link.As(&file)) && SUCCEEDED(file->Load(path.c_str(), STGM_READ)), "Load the saved link");

  return link;
}

void verify_shortcut(const std::wstring& path, const std::wstring& executable) {
  const auto link = read_shortcut(path);
  wchar_t target[32768]{};
  require(SUCCEEDED(link->GetPath(target, 32768, nullptr, SLGP_RAWPATH)) && executable == target,
          "Identity registration preserves the shortcut executable path");
  ComPtr<IPropertyStore> properties;
  require(SUCCEEDED(link.As(&properties)), "Shell links expose their property store");
  PROPVARIANT value{};
  const HRESULT status = properties->GetValue(PKEY_AppUserModel_ID, &value);
  const bool matched = SUCCEEDED(status) && value.vt == VT_LPWSTR && value.pwszVal &&
                       std::wstring(phonolite_identity::app_id) == value.pwszVal;
  ::PropVariantClear(&value);
  require(matched, "The link stores the explicit process/media AppUserModelID");
}

void verify_identity(const std::wstring& directory) {
  require(SUCCEEDED(::SetCurrentProcessExplicitAppUserModelID(phonolite_identity::app_id)),
          "Set an identity on this headless test process only");
  PWSTR current = nullptr;
  const HRESULT status = ::GetCurrentProcessExplicitAppUserModelID(&current);
  const bool matched = SUCCEEDED(status) && current && std::wstring(phonolite_identity::app_id) == current;
  ::CoTaskMemFree(current);
  require(matched, "Windows returns the same process identity");
#ifdef _DEBUG
  require(std::wstring(phonolite_identity::app_id).find(L".Debug") != std::wstring::npos,
          "Debug metadata has a separate identity from installed releases");
#else
  require(std::wstring(phonolite_identity::app_id).find(L".Debug") == std::wstring::npos,
          "Release metadata uses the installer identity without a debug suffix");
#endif

  wchar_t executable[32768]{};
  require(::GetModuleFileNameW(nullptr, executable, 32768) > 0, "Locate this test executable without launching it");
  const auto shortcut = directory + L"\\Phonolite \u00e9.lnk";
  require(
      ensure_application_shortcut(shortcut, executable, phonolite_identity::app_id, phonolite_identity::display_name),
      "Create an identified shortcut in a temporary verification directory");
  verify_shortcut(shortcut, executable);

  require(ensure_application_shortcut(shortcut, L"C:\\different\\Phonolite.exe", phonolite_identity::app_id,
                                      phonolite_identity::display_name),
          "Repeated registration does not redirect an existing installed shortcut to a build folder");
  verify_shortcut(shortcut, executable);

  // Simulate an older installer's otherwise valid link without an AppUserModelID.
  const auto legacy_path = directory + L"\\legacy.lnk";
  ComPtr<IShellLinkW> legacy;
  require(SUCCEEDED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&legacy))),
          "Create a legacy shortcut for migration");
  ComPtr<IPersistFile> legacy_file;
  require(SUCCEEDED(legacy.As(&legacy_file)) && SUCCEEDED(legacy->SetPath(executable)) &&
              SUCCEEDED(legacy_file->Save(legacy_path.c_str(), TRUE)),
          "Save an unmarked legacy shortcut");
  legacy_file.Reset();
  legacy.Reset();
  require(ensure_application_shortcut(legacy_path, L"C:\\different\\Phonolite.exe", phonolite_identity::app_id,
                                      phonolite_identity::display_name),
          "Upgrade a legacy link's identity without replacing its target");
  verify_shortcut(legacy_path, executable);

  const auto malformed = directory + L"\\malformed.lnk";
  {
    std::ofstream invalid(malformed, std::ios::binary);
    invalid << "keep";
  }
  require(
      !ensure_application_shortcut(malformed, executable, phonolite_identity::app_id, phonolite_identity::display_name),
      "An unreadable existing link is left intact");

  require(::DeleteFileW(shortcut.c_str()) && ::DeleteFileW(legacy_path.c_str()) && ::DeleteFileW(malformed.c_str()),
          "Remove only the three temporary links created by this verification");
}

} // namespace

int main() {
  require(SUCCEEDED(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "Initialize the test COM apartment");
  wchar_t root[32768]{};
  require(::GetCurrentDirectoryW(32768, root) > 0, "Locate the test build directory");
  const auto directory = std::wstring(root) + L"\\identity-fixture-" + std::to_wstring(::GetCurrentProcessId());
  require(::CreateDirectoryW(directory.c_str(), nullptr), "Create one isolated verification directory");
  verify_identity(directory);
  require(::RemoveDirectoryW(directory.c_str()), "Remove the empty verification directory");
  ::CoUninitialize();
  std::cout << "Windows process identity and shortcut registration checks passed.\n";

  return EXIT_SUCCESS;
}
