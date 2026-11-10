#include "runner/infrastructure/updates/windows_update_service.h"

#include <filesystem>
#include <string>
#include <vector>

#include "phonolite_app_identity.h"
#include "phonolite_updates.h"

WindowsUpdateService::~WindowsUpdateService() {
  cleanup();
}

bool WindowsUpdateService::initialize() {
#ifdef _DEBUG
  return false;
#else
  if (initialized_) {
    return true;
  }

  std::wstring executable(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
  if (length == 0 || length >= executable.size()) {
    return false;
  }
  executable.resize(length);

  const std::wstring registry_path = std::wstring(L"Software\\") + phonolite_identity::app_id;
  std::wstring installed(32768, L'\0');
  DWORD size = static_cast<DWORD>(installed.size() * sizeof(wchar_t));
  const auto status = RegGetValueW(HKEY_CURRENT_USER, registry_path.c_str(), L"InstallLocation",
                                   RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, installed.data(), &size);
  if (status != ERROR_SUCCESS || size < sizeof(wchar_t)) {
    return false;
  }
  installed.resize(size / sizeof(wchar_t) - 1);
  const auto directory = std::filesystem::path(executable).parent_path().wstring();
  // An unpacked release build must not silently install over its build directory.
  if (_wcsicmp(directory.c_str(), installed.c_str()) != 0) {
    return false;
  }

  install_directory_ = directory;
  initialized_ = true;
  return true;
#endif
}

std::string WindowsUpdateService::feed_url() const {
  return phonolite_updates::feed_url;
}

std::string WindowsUpdateService::current_version() const {
  return std::to_string(FLUTTER_VERSION_MAJOR) + "." + std::to_string(FLUTTER_VERSION_MINOR) + "." +
         std::to_string(FLUTTER_VERSION_PATCH) + "." + std::to_string(FLUTTER_VERSION_BUILD);
}

std::string WindowsUpdateService::public_key() const {
  return phonolite_updates::public_key;
}

unsigned long WindowsUpdateService::stage_update(const std::wstring& path, const std::string& version) {
  if (!initialized_) {
    return ERROR_INVALID_STATE;
  }
  release_update();
  if (path.empty() || path.find(L'"') != std::wstring::npos || path.find(L'\0') != std::wstring::npos ||
      !std::filesystem::path(path).is_absolute() || std::filesystem::path(path).extension() != L".exe") {
    return ERROR_INVALID_PARAMETER;
  }

  candidate_file_ =
      CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (candidate_file_ == INVALID_HANDLE_VALUE) {
    return GetLastError();
  }

  // Keep the file read-locked across Dart signature verification and process creation.
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), nullptr);
  if (size == 0 || size > 1024 * 1024) {
    release_update();
    return ERROR_BAD_EXE_FORMAT;
  }
  std::vector<BYTE> resource(size);
  VS_FIXEDFILEINFO* info = nullptr;
  UINT info_size = 0;
  if (!GetFileVersionInfoW(path.c_str(), 0, size, resource.data()) ||
      !VerQueryValueW(resource.data(), L"\\", reinterpret_cast<void**>(&info), &info_size) ||
      info_size < sizeof(VS_FIXEDFILEINFO) || info == nullptr || info->dwSignature != 0xfeef04bd) {
    release_update();
    return ERROR_BAD_EXE_FORMAT;
  }
  const std::string embedded_version =
      std::to_string(HIWORD(info->dwFileVersionMS)) + "." + std::to_string(LOWORD(info->dwFileVersionMS)) + "." +
      std::to_string(HIWORD(info->dwFileVersionLS)) + "." + std::to_string(LOWORD(info->dwFileVersionLS));
  const DWORD current_ms = (static_cast<DWORD>(FLUTTER_VERSION_MAJOR) << 16) | FLUTTER_VERSION_MINOR;
  const DWORD current_ls = (static_cast<DWORD>(FLUTTER_VERSION_PATCH) << 16) | FLUTTER_VERSION_BUILD;
  if (embedded_version != version || info->dwFileVersionMS < current_ms ||
      (info->dwFileVersionMS == current_ms && info->dwFileVersionLS <= current_ls)) {
    release_update();
    return ERROR_REVISION_MISMATCH;
  }

  candidate_path_ = path;
  return ERROR_SUCCESS;
}

unsigned long WindowsUpdateService::install_update() {
  if (!initialized_ || candidate_file_ == INVALID_HANDLE_VALUE) {
    return ERROR_INVALID_STATE;
  }

  // NSIS requires /D last and unquoted, including when the directory has spaces.
  // Never use appcast-supplied command-line arguments or a shell to execute it.
  std::wstring command = L"\"" + candidate_path_ + L"\" /S /UPDATE /D=" + install_directory_;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(candidate_path_.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                      install_directory_.c_str(), &startup, &process)) {
    return GetLastError();
  }

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return ERROR_SUCCESS;
}

void WindowsUpdateService::release_update() {
  if (candidate_file_ != INVALID_HANDLE_VALUE) {
    CloseHandle(candidate_file_);
  }
  candidate_file_ = INVALID_HANDLE_VALUE;
  candidate_path_.clear();
}

void WindowsUpdateService::cleanup() {
  release_update();
  initialized_ = false;
  install_directory_.clear();
}
