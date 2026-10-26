#ifndef RUNNER_INFRASTRUCTURE_SHELL_APPLICATION_IDENTITY_H_
#define RUNNER_INFRASTRUCTURE_SHELL_APPLICATION_IDENTITY_H_

#include <string>

/// Called after COM initialization, before constructing a window or engine.
/// Registers the current process, friendly metadata and its Shell shortcut.
/// Failure is nonfatal and never launches an application or a shortcut.
bool configure_application_identity();

/// Stamps a matching AUMID into an existing link without changing its target.
/// Creates a link to executable_path only when the shortcut does not exist.
/// Exposed separately so verification uses temporary files, never Start Menu.
bool ensure_application_shortcut(const std::wstring& shortcut_path, const std::wstring& executable_path,
                                 const std::wstring& app_id, const std::wstring& display_name);

#endif // RUNNER_INFRASTRUCTURE_SHELL_APPLICATION_IDENTITY_H_
