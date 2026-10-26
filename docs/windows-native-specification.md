# Phonolite Windows native C++ specification

This extends the [expected architecture](expected-architecture.md), [coding standards](coding-standards.md), and [iOS specification](ios-swift-specification.md) to Phonolite's Flutter Windows host. Shared owners define common structure and behavior; specialized components supply their differences; assembly connects explicit dependencies. Windows adds C++ resource ownership, header contracts, Win32 callbacks, and CMake integration to those expectations.

The source map below describes the implemented runner organization. Naming and layout use the confirmed choices: `lower_snake_case` files and folders, `snake_case` project-owned functions and methods, and public-contract-first headers. The refactor preserves the existing startup, window, channel and package contracts; separate correctness changes remain explicit work.

## 1. Current Windows responsibilities

The active runner uses Win32 and Flutter's C++ wrappers, with a C++/WinRT adapter for Windows System Media Transport Controls. It has no native application pages, XAML or WinUI.

| Current source | Responsibilities | Ownership |
| --- | --- | --- |
| [main.cpp](../windows/runner/main.cpp) | Console setup, COM initialization, Flutter project arguments, initial window, message loop and shutdown | A small process composition root |
| [Flutter host](../windows/runner/bootstrap/flutter_window.cpp) | Engine/view ownership, plugin registration, child hosting, first-frame display, message forwarding and capability assembly | Bootstrap |
| [Win32 frame](../windows/runner/ui/shell/win32_window.cpp) | Window lifecycle, class registration, HWND callback routing, DPI, sizing, focus and system theme | UI/Shell; [geometry values](../windows/runner/data/models/window/window_geometry.h) live under Data |
| [Directory adapter](../windows/runner/infrastructure/flutter/directories_channel_adapter.cpp) | Channel attachment, typed argument validation, conversion and Flutter replies | Infrastructure/Flutter |
| [Directory launcher](../windows/runner/infrastructure/shell/directory_launcher.cpp) | Native Shell request with a borrowed owner HWND | Infrastructure/Shell; [native status outcome](../windows/runner/data/models/directories/directory_open_result.h) lives under Data |
| [Application identity](../windows/runner/infrastructure/shell/application_identity.cpp) and [identity configuration](../windows/runner/identity.cmake) | Explicit process identity, per-user Shell name/icon metadata and identified shortcuts | Infrastructure/Shell; build-time constants come from the installer configuration |
| [Now Playing channel](../windows/runner/infrastructure/flutter/now_playing_channel_adapter.cpp) and [codec](../windows/runner/infrastructure/flutter/now_playing_codec.cpp) | Shared Dart media protocol, snapshot validation and platform-thread command delivery | Infrastructure/Flutter; independent snapshot/command values live under Data/Models/Media |
| [Windows media transport](../windows/runner/infrastructure/media/windows_media_transport.cpp) and [command queue](../windows/runner/infrastructure/media/media_command_queue.h) | HWND-associated SMTC session, metadata/artwork/timeline updates, WinRT resources and synchronized callback delivery | Infrastructure/Media; the channel borrows a testable MediaTransport capability |
| [Command line](../windows/runner/infrastructure/process/command_line.cpp), [console](../windows/runner/infrastructure/process/console_support.cpp), [encoding](../windows/runner/infrastructure/text/text_encoding.cpp) | Process arguments, diagnostics and boundary conversion | Named Infrastructure capabilities |
| [runner CMake](../windows/runner/CMakeLists.txt), [project CMake](../windows/CMakeLists.txt) | Source registration, compiler settings, linking, Flutter assembly and runtime installation | Build configuration with explicit target ownership |
| [Runner.rc](../windows/runner/Runner.rc), [resource.h](../windows/runner/resource.h), [manifest](../windows/runner/runner.exe.manifest) | Product/version/icon resources, resource IDs, DPI and compatibility declarations | Runner resources at their configured build paths |

Flutter continues to own application pages, navigation and domain workflows. Windows PCM output currently uses [WaveOutPlayer](../lib/infrastructure/platform/audio/windows/wave_out_output.dart), selected by the [Dart output factory](../lib/infrastructure/audio/output/audio_output_factory.dart). Shared decoder, transport and authentication implementations remain in their native packages.

The retained [just_audio_windows package](../packages/just_audio_windows/pubspec.yaml) is not an active app dependency. The shared [Now Playing service](../lib/infrastructure/platform/media/now_playing_platform_service.dart) supports iOS, Android and Windows. Windows uses the existing audio engine and its Dart playback commands; SMTC supplies system presentation and input without creating a second media player.

The Windows media transport initializes WinRT lazily on first track publication and balances its apartment reference on the same thread. It binds SMTC to the existing top-level HWND through `ISystemMediaTransportControlsInterop`. Title, artist, album, cached PNG artwork and a bounded timeline are published with play/pause status. Play, pause, previous, next and seek events return through `phonolite/now_playing`; the Stop key pauses the selected track. System media-key routing remains with Windows. No global hotkeys are registered.

SMTC events arrive off the Flutter platform thread. A synchronized, bounded queue posts a registered window message, and the host drains it into the channel on the platform thread before plugin message handling. Track/epoch changes and clear discard old pending commands. Teardown disables the queue, unregisters events and releases SMTC before destroying the Flutter messenger/window. Clear disables the system session and removes metadata. Artwork uses an in-memory COM stream with no native HTTP requests or credential handling, and no asynchronous wait blocks the STA. WinRT errors are caught at the capability boundary and become channel errors; integration failure does not stop ordinary playback.

`windows/tests/media_contract_test.cpp` injects a transport and messenger to verify the native codec, callback ordering, bounded queue, cancellation and channel lifetime without creating a window or registering a real media session. The production transport is compiled in both the runner build and native compile-check target. Interactive hardware/media-panel checks remain user-controlled.

Windows app identity is set by `configure_application_identity()` after COM initialization and before constructing the Flutter project/window. `identity.cmake` generates its constants from `distribution_tools/windows/scripts/package_config.json`, shared with NSIS packaging. Normal builds use the configured identity; `_DEBUG` builds append `.Debug` and use a separate shortcut, keeping development and installed Shell registrations independent. The SMTC display updater sets that same AppMediaId after clearing metadata.

The Shell capability registers `DisplayName` and `IconUri` beneath the current user's `Software\\Classes\\AppUserModelId` key and ensures a matching `System.AppUserModel.ID` on the per-user Start Menu link. It creates a missing link or adds the identity to an older one without changing the target of an existing link. Registration failure is nonfatal and writes a native debug diagnostic. The NSIS installer stamps its shortcut's property using bundled COM helpers, registers release display metadata and removes that release registration on uninstall. No app process is launched during installation to perform this work.

`windows/tests/identity_contract_test.cpp` verifies the process ID and real `.lnk` property round trips in both debug and release. Its files stay in an isolated test directory; it never writes the real identity registry key or Start Menu. The production startup registration itself is compiled, while live Shell/SMTC display verification remains user-controlled. Rebuild and fully restart the native app when changing identity; hot reload does not run `wWinMain` again.

## 2. Source organization

Use physical responsibility folders beneath the existing `windows/runner` build target. Create only owners with meaningful work; a short entry point does not require an additional application wrapper.

```text
windows/
  .clang-format
  CMakeLists.txt
  runner/
    main.cpp
    bootstrap/
      flutter_window.h
      flutter_window.cpp
    data/
      models/
        window/window_geometry.h
        directories/directory_open_result.h
    infrastructure/
      flutter/
        directories_channel_adapter.h
        directories_channel_adapter.cpp
      shell/
        directory_launcher.h
        directory_launcher.cpp
      process/
        command_line.h
        command_line.cpp
        console_support.h
        console_support.cpp
      text/
        text_encoding.h
        text_encoding.cpp
    ui/
      shell/
        win32_window.h
        win32_window.cpp
    CMakeLists.txt
    Runner.rc
    resource.h
    runner.exe.manifest
    resources/
  flutter/                       # Flutter-managed integration and output
  tests/
    CMakeLists.txt
    native_contract_test.cpp
```

WindowPoint and WindowSize retain the frame's unsigned coordinates and dimensions. DirectoryOpenResult preserves the native Shell status and its acceptance rule without Flutter codec or SDK ownership. These are short header-only value contracts; ordinary parameters do not require wrappers.

| Area | Owns | Boundary |
| --- | --- | --- |
| Bootstrap | Process/window/engine composition, registration and lifecycle connections | Constructs services and passes capabilities; deep code does not discover the host globally |
| Data | Named values, configuration, outcomes and their natural operations | No Flutter codec objects, OS actions or resource-owning HWND/COM/channel wrappers |
| Infrastructure | Channels, Shell actions, text conversion, process services and native resource mechanisms | Typed inputs/results; no concrete app page selection or Dart business rules |
| UI | Common native window frames, presentation and visual interaction | Receives values/actions; does not decode channels or own library/playback algorithms |
| Application when needed | Functional state and policies for an actual native workflow | No HWND rendering, page construction or copies of existing Dart controllers |
| Pages when needed | Assembly of an actual native view | Reuses shared UI and binds native controllers; Flutter pages stay in `lib/pages` |

The present directory-opening feature needs a channel adapter and a Shell capability. It does not require a native controller or native page. Keep Application and Pages absent until those responsibilities exist.

## 3. Shared structures and assembly

[Win32Window](../windows/runner/ui/shell/win32_window.h) defines the shared native frame, and [FlutterWindow](../windows/runner/bootstrap/flutter_window.h) specializes creation, cleanup and message handling. Common DPI, child resizing, focus, theme and close behavior have one owner.

Feature integrations compose services around that frame. Opening a folder belongs to a Shell capability; it should not become another virtual feature hook on the window superclass. Keep small registrar and message-routing details beside the frame while they share its lifetime. Extract them when they become independently meaningful resources or capabilities.

The directory flow is:

```text
Dart DesktopDirectoryService
  → DirectoriesChannelAdapter validates and decodes the message
  → text conversion produces the Windows path representation
  → DirectoryLauncher requests the Shell action
  → typed outcome returns to the adapter
  → the adapter sends the existing Flutter reply
```

Compose concrete owners and narrow callbacks first. Introduce an abstract interface when multiple implementations, a shared family or a useful testing boundary needs one. An interface defines a contract; shared execution rules still need a common implementation owner. A single directory channel does not yet justify a general channel framework.

As more channels appear, inspect their shared registration, dispatch, result and teardown sequence. Extract that mechanism when it contains common decisions, rather than copying it into every adapter. Do the same for repeated native action groups and UI arrangements. Keep final assembly readable through named operations, as with the Dart page frames and iOS CarPlay structures.

## 4. Naming and source boundaries

Use the confirmed naming conventions for new or materially refactored handwritten code:

| Item | Convention | Example |
| --- | --- | --- |
| Files and directories | `lower_snake_case` | `infrastructure/shell/directory_launcher.cpp` |
| Types and type aliases | `PascalCase` | `DirectoryLauncher`, `DirectoryOpenResult` |
| Functions, methods, parameters and local variables | `snake_case` | `open_directory`, `folder_path` |
| Namespaces and scoped enum values | `snake_case` | `phonolite`, `DirectoryOpenStatus::accepted` |
| Private instance members | `snake_case_` | `owner_window_`, `directory_channel_` |
| Project constants | Descriptive `snake_case` with `constexpr` where appropriate | `default_window_width` |

Keep external API names, exported C symbols, generated entry points and wire keys intact: `ShellExecuteW`, `SetMethodCallHandler`, `RegisterPlugins`, `phonolite_quic_close` and `openDirectory` describe different external contracts. The native method can be `open_directory` while its channel method remains `openDirectory`.

The local `Win32Window::on_create`, `on_destroy` and `message_handler` methods are project-owned hooks shared with FlutterWindow. Keep exact override names when the declaration belongs to an external library. Preserve required callback signatures and calling conventions even when a project-owned callback function is renamed.

Prefer one primary responsibility per `.h`/`.cpp` pair. Keep small private helpers in an unnamed namespace inside the implementation file. Independently reusable helpers get a named owner and normal header. Do not recreate a broad `utils` collection or simulate shared private implementation by including `.cpp` files.

### Includes and headers

Headers must be self-contained, guarded, and include what their declarations need. Prefer forward declarations where an incomplete type is sufficient. Put substantial operations in `.cpp`; keep short value operations and obvious accessors inline when useful. Templates require visible definitions where instantiated.

When a header holds `std::unique_ptr<ForwardDeclaredType>`, define its owning class's destructor out of line where the complete pointee type is available. An inline defaulted destructor can require that complete type in every including file. Keep constructor definitions out of line too when their cleanup paths require it.

For implementation files, include their own header first, then separate standard-library, Windows/SDK, Flutter/third-party, and app include groups. Alphabetize within each group unless an SDK dependency requires an explicit order. Document consequential ordering requirements. Avoid `using namespace` directives in headers and keep implementation aliases local.

Use a configured project include root for app headers, for example `#include "runner/data/models/window/window_geometry.h"`. C++ has no Dart `package:` URI equivalent. Avoid absolute machine paths and chains of `../../` includes. Keep Flutter headers under their published `<flutter/...>` names. Preserve the existing Unicode and `NOMINMAX` build definitions.

## 5. Public contracts and member order

Headers present public contracts first. Within the public section, group related types/constants, construction and special-member declarations, observation/configuration, lifecycle operations, and commands. Put protected specialization hooks next when a real base family needs them. Keep private dependencies and state together in declaration order, followed by private operations. Omit unused sections and comment banners.

The Shell owner's public contract follows this pattern:

```cpp
class DirectoryLauncher final {
 public:
  explicit DirectoryLauncher(HWND owner_window);

  DirectoryOpenResult open_directory(const std::wstring& folder_path) const;

 private:
  HWND owner_window_;  // Borrowed; the owning window outlives this launcher.
};
```

Use `final` for concrete owners unless subclassing is an intentional contract. Keep shared base extension points narrow. Prefer private state and explicit operations over protected mutable fields. Getters expose deliberate observations; setters remain available for simple supported changes. Coordinated work should have a named command rather than a chain of setters.

Implementation files place construction/destruction and lifecycle first, then public operations, private helpers and final host/view assembly. Use the header to understand the contract and the implementation to follow the workflow. A fluent builder is optional when a real configuration family benefits; retain individual setters and one configuration call per line.

**Resource declaration order is part of correctness.** C++ initializes members in declaration order and destroys them in reverse order. Declare a dependency before an object that borrows it; mirror that order in constructor initializer lists. Public-first layout does not override this lifetime rule. [Microsoft resource lifetime guidance](https://learn.microsoft.com/en-us/cpp/cpp/object-lifetime-and-resource-management-modern-cpp?view=msvc-170)

## 6. Readability and C++ operations

Use two-space indentation, attached braces, a 120-column target and one blank line between logical paragraphs. Separate input preparation, guards, OS calls, state changes, notification and the result. Keep related configuration assignments contiguous. Keep compact signatures when they fit; do not compress independent operations onto one line.

Prefer early exits and explicit checks:

```cpp
std::optional<std::wstring> decode_folder_path(const std::string& path) {
  if (path.empty()) {
    return std::nullopt;
  }

  auto folder = utf16_from_utf8(path);

  if (!folder) {
    return std::nullopt;
  }

  return folder;
}
```

This illustrates operation layout, not a replacement for the channel's distinct empty-path and invalid-UTF-8 errors. Named helpers must preserve those distinctions.

Use `const` for stable local bindings and `const` methods for observations. Use `auto` when the type is obvious or long without useful information; keep explicit types where units, signedness, status family or ownership matter. Use references for required borrowed dependencies, nullable pointers for optional borrowed objects, and value parameters where copying or moving expresses ownership clearly.

Use `nullptr`, scoped enums and typed constants. Prefer `static_cast` for ordinary conversions; reserve `reinterpret_cast` for actual API/ABI conversions and explain them when consequential. Keep checked narrowing and UTF-8/UTF-16 conversion explicit. A `std::string_view` or `std::wstring_view` is borrowed and need not be null-terminated; do not retain it across a callback or pass its `data()` to a null-terminated API without establishing those guarantees.

Keep useful loops and collection transforms readable. Extract substantial callback bodies into named operations. Do not add a wrapper around every constructor or force unrelated operations into one generic function. Comments should explain ownership, units, callback obligations and non-obvious decisions.

## 7. Data and failure contracts

Put named native values in Data, including geometry, configuration and results shared between owners. Small validation, comparison and copying operations can live on those values. Ordinary values may be `struct`s with direct fields; use a class when invariants require controlled mutation. A pure value should not own an HWND, COM interface, messenger, worker or opaque FFI resource requiring independent release. Owned `std::string` and `std::vector` contents are ordinary value data.

Use content comparisons deliberately for value objects. Keep resource owners noncopyable unless copying has an explicit ownership meaning. C++17 does not provide the same automatic model equality pattern as Dart/Swift; define only the comparisons the concept needs. Named shared models take priority over tuples spanning multiple files; tuples remain useful for small local results.

Use named result structures, `std::optional`, `std::variant` or an appropriate error type to distinguish meaningful outcomes. Preserve native error values where callers need them. The directory adapter should translate a typed Shell result into the existing Flutter envelope; the launcher should not construct a `flutter::EncodableValue` or `MethodResult`.

Keep Windows status families distinct. An `HRESULT`, a `GetLastError` value and a Shell status have different interpretation rules. `ShellExecuteW` succeeds above 32; its return is a compatibility value cast to `INT_PTR`, not a resource to close or a result for `SUCCEEDED`. [ShellExecuteW contract](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shellexecutew)

Keep the current C++17 baseline and existing exception configuration while organizing code. Avoid blanket exception swallowing or adding throwing workflows across Win32 callbacks, Flutter boundaries or the exported C ABI. Changes to language mode or exception policy need their own build and failure-path review.

## 8. Resource ownership and lifecycle

Prefer value members and `std::unique_ptr` for sole ownership. Use `std::make_unique` when dynamic ownership is needed. Introduce `std::shared_ptr` only for actual shared lifetime; do not use it merely to make asynchronous captures convenient. Follow the rule of zero when members already implement correct ownership, and define/delete copy and move operations deliberately for resource owners.

RAII should pair an owned resource with its matching release operation and scope. The wrapper's invalid value, acquisition failure, thread and transfer rules must be explicit. A generic raw handle value does not establish ownership.

| Resource | Ownership rule |
| --- | --- |
| Top-level window | The native frame owns its HWND lifecycle; routing must not outlive the associated C++ object |
| Flutter child HWND | Borrow it from the Flutter view; hosting it does not transfer independent destruction ownership |
| Flutter controller/engine/messenger | The host owns the controller; dependent adapters stop before its messenger disappears |
| Channel handler | Explicitly unregister it while its messenger is valid, before destroying the captured owner |
| `LoadLibrary` result | An owned module reference needs matching `FreeLibrary`; a borrowed `GetModuleHandle` result has different ownership |
| Command-line buffer | A successful `CommandLineToArgvW` allocation uses `LocalFree` |
| Native FFI handle or returned string | Use the package's matching close/free function, never an unrelated allocator |
| Worker request | Its creator owns completion, cancellation and payload lifetime until ownership transfers |

Destroying Flutter's `MethodChannel` does not unregister its handler. The installed wrapper and [Flutter's C++ channel contract](https://api.flutter.dev/windows-embedder/method__channel_8h_source.html) require explicit removal when a captured owner stops being valid before the engine. Clearing a handler is a lifecycle operation, not optional destructor tidying.

COM initialization belongs to a thread and an apartment. Balance successful initialization, including `S_FALSE`, with `CoUninitialize` on that thread; a failed incompatible-apartment initialization is not owned success. Keep COM-dependent objects inside that lifetime. [CoInitializeEx rules](https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-coinitializeex)

The current `main.cpp` does not inspect the COM result, returns early on window-creation failure, and calls `CoUninitialize` before the local window's C++ destructor. A future scoped COM owner should address those paths explicitly. That changes shutdown/error behavior and needs deliberate verification rather than being silently included in a file move.

## 9. Channel boundaries and threading

Channel adapters own names, `EncodableValue` parsing, codec types, Flutter replies and unknown-method handling. Decode at that boundary and call typed native capabilities. Keep every incoming call's completion obligation explicit: exactly one `Success`, `Error` or `NotImplemented`, including failure and shutdown paths. [Flutter channel handler contract](https://api.flutter.dev/windows-embedder/method__channel_8h_source.html)

Preserve the current directory contract during extraction:

| Case | Existing behavior |
| --- | --- |
| Request | Channel `phonolite/directories`, method `openDirectory`, one scalar UTF-8 string |
| Missing, wrong-type or empty path | `invalid_path`, message `A folder path is required.` |
| Invalid UTF-8 | `invalid_path`, message `The folder path is not valid UTF-8.` |
| Shell request | Owner HWND, verb `open`, converted folder path, `SW_SHOWNORMAL` |
| Shell failure | Status `<= 32`; `open_failed`, message `Could not open the folder.`, integer native status details |
| Success | Null success reply acknowledges that the Shell accepted the request |
| Unknown method | `NotImplemented` |

Keep the existing path spelling and conversion policy. Trimming, canonicalizing, checking existence or changing the verb adds behavior. The [Dart directory service](../lib/infrastructure/platform/files/desktop_directory_service.dart) already creates the absolute storage directory before invoking the native channel.

Window mutation and outbound Flutter invocation belong to the platform thread. Move expensive work off that thread when needed, then marshal presentation/invocation back through an explicit dispatcher. Preserve the selected wrapper's result-threading contract; do not infer permission to mutate an HWND or invoke Flutter from an arbitrary native callback. [Flutter platform threading](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading)

Use explicit lambda captures. Capturing `this` does not extend its lifetime; checking a request generation does not make a destroyed object safe to access. An asynchronous operation needs owner lifetime, cancellation/relevance and completion rules. Copy borrowed buffers or views when the callback contract does not keep them alive. For new runner C++ work, avoid detached threads, broad `[&]` captures and unowned work that outlives the engine. Cross-platform package workers retain their separate ownership contracts.

If C++/WinRT is introduced later, define apartment, event-token, cancellation and coroutine ownership in that adapter. A future platform dispatcher should share actual thread-delivery policy; it should not be added to the current synchronous directory operation without need.

## 10. Build and package ownership

The [current runner build](../windows/runner/CMakeLists.txt) explicitly lists sources, resources and the generated registrant. Moves must update those paths and the include roots. Keep Flutter-first message forwarding, registration, child mounting and first-frame display/`ForceRedraw` ordering intact. Teardown unregisters the channel before releasing the controller.

Preserve the existing `Phonolite` title, `(10, 10)` initial origin, `1280` by `720` initial size, `DartProject(L"data")` asset location, UTF-8 command-line arguments excluding the executable, and `COINIT_APARTMENTTHREADED` initialization. Keep console/debugger behavior and DPI scaling at their existing owners.

The project currently selects C++17, Unicode, `NOMINMAX`, `/W4 /WX /wd4100`, `/EHsc` and `_HAS_EXCEPTIONS=0`. The compiler exception switch and the STL configuration macro are different settings; preserve both until a deliberate policy change. The CMake minimum is 3.14, with policy range 3.14 through 3.25. No exact MSVC, Windows SDK or CMake executable version is pinned in these files.

Keep changes target-scoped. `apply_standard_settings` is also used by plugins, so changing it for runner style can affect package builds. Preserve `flutter`, `flutter_wrapper_app`, `dwmapi.lib`, `shell32.lib`, generated plugin integration, `flutter_assemble`, runtime installation, native assets, icon/version resources and the DPI manifest.

Flutter-managed files under `windows/flutter`, generated plugin lists and ephemeral output retain tool ownership. Runner window sources were derived from a template but are editable application sources; that does not make them generated. Keep documentation in `docs`, without adding READMEs to source responsibility directories.

The three active native packages retain their own Windows build integration:

| Package | Runtime DLL | Responsibility |
| --- | --- | --- |
| [phonolite_opus](../packages/phonolite_opus/windows/CMakeLists.txt) | `phonolite_opus.dll` | Opus decoder C ABI and native implementation |
| [phonolite_local_audio](../packages/phonolite_local_audio/windows/CMakeLists.txt) | `phonolite_local_audio.dll` | Local decoder, opaque handles, PCM output data and seek metadata |
| [phonolite_quic](../packages/phonolite_quic/windows/CMakeLists.txt) | `phonolite_quic.dll` | Transport, authentication, certificate identity and security exports |

Preserve exported symbol names, calling conventions, fixed-width arguments, string encodings, opaque handles, buffer/sample/frame units, millisecond positions and matching release functions. Keep shared Rust/C implementation in the package's source tree. Do not replace FFI with runner channels to make the directory maps symmetrical.

Keep vendored Opus sources under their upstream layout/style. Rust implementations retain Rust-specific language and formatting rules. This C++ naming and formatting specification applies to handwritten runner C++ and owned C++ being intentionally refactored, rather than automatically covering every dependency tree.

Preserve the existing audio buffer/epoch ordering and authenticated pin checks before application data. A package close operation must document what it completes; the current QUIC close is not a promise of a synchronous worker join. Do not log credentials, proofs or tokens.

## 11. Formatter

Use clang-format **19.1.5** for handwritten runner C++. The installed [windows/.clang-format](../windows/.clang-format) configuration is:

```yaml
BasedOnStyle: LLVM
IndentWidth: 2
AccessModifierOffset: -1
ColumnLimit: 120
BreakBeforeBraces: Attach
DerivePointerAlignment: false
PointerAlignment: Left
MaxEmptyLinesToKeep: 1
AllowShortFunctionsOnASingleLine: Empty
```

The 120-column target allows more signatures to remain compact. The formatter limits repeated blank lines; developers still supply meaningful paragraph breaks and responsibility boundaries. Validate configuration and layout when upgrading the pinned formatter. [LLVM formatter configuration](https://clang.llvm.org/docs/ClangFormatStyleOptions.html)

Run the pinned executable with `--style=file` against an explicit list of handwritten runner `.h`/`.cpp` files, using `-i` to apply or `--dry-run --Werror` to check. Exclude Flutter-managed, generated, vendored and unrelated package code. Preserve the documented Windows-before-Shell include dependency in command_line.cpp.

## 12. Implementation ideas and verification

The runner composes its directory adapter and Shell launcher, retains the shared frame family, and uses named process/text capabilities. Future work should preserve these seams and keep `main.cpp` readable without adding a parallel application framework.

| Idea | Introduce it when | Keep the shared responsibility clear |
| --- | --- | --- |
| Scoped native-resource owner | A real resource has repeated or error-prone acquire/release paths | Match the actual allocator, thread, invalid state and release operation |
| Shared channel base/collaborator | Multiple adapters share attachment, dispatch or teardown decisions | Family adapters retain their own wire contracts and typed operations |
| Native controller | A real native feature owns loading, validation, selection or request policy | Windows API access by itself stays in Infrastructure |
| Native page/frame family | An actual Windows-native view is added | Pages assemble it; UI owns common design and layout |
| Platform dispatcher | Worker/event callbacks need a common delivery and lifetime policy | Preserve ordering, cancellation, engine lifetime and result obligations |
| Reusable plugin | Another app or host actually needs the capability | Keep app-specific window assembly outside the package |
| Windows media controls | The feature is intentionally added | Define a typed media capability; reuse Dart playback workflows and existing trust owners |

Keep correctness changes visible. COM balance/destruction order, negative `GetMessage` results, text-conversion length/status handling and native package multi-config build behavior deserve focused review when changed. Source organization alone does not establish that these paths are correct.

Use the existing [Windows and FFI source contracts](../test/requirements/platform_windows_and_ffi_contract_test.dart) and [Dart directory tests](../test/platform/desktop_directory_service_test.dart) as verification anchors. Update source checks to follow extracted owners while retaining their original contract coverage. Add focused pure native tests for decoding, text conversion and outcomes where extraction creates a useful seam.

[Windows architecture checks](../test/architecture/windows_architecture_test.dart) verify CMake membership, layer boundaries and host/channel contracts. The standalone [native checks](../windows/tests/CMakeLists.txt) compile the production runner's registered translation units and run in-memory channel, encoding and value tests. They do not create a native window or launch Explorer. They compile runner code without linking or packaging the complete Flutter application.

From the app root, configure and run these checks with the selected SDK and compiler:

```powershell
cmake -S windows/tests -B .dart_tool/windows_native_checks -G "Visual Studio 17 2022" -A x64 `
  -DPHONOLITE_FLUTTER_ENGINE_DIR=C:/path/to/flutter/bin/cache/artifacts/engine/windows-x64

$env:MSBUILDDISABLENODEREUSE = '1'
cmake --build .dart_tool/windows_native_checks --config Debug --parallel 1 -- /nodeReuse:false
ctest --test-dir .dart_tool/windows_native_checks -C Debug --output-on-failure
```

Repeat with `Profile` and `Release` for changes affecting compilation or configuration. Worker reuse is disabled so compiler workers do not remain in the background. The Flutter SDK cache and current generated plugin headers must be available; these checks do not download them.

Verify explicit CMake source membership, resources, generated registration, DLL installation and Debug/Profile/Release builds appropriate to the change. Source checks and a successful build do not establish rendered window behavior. During agent work, compilation and headless verification are allowed; launching the app, a server, or a background service remains the user's responsibility.

## 13. Windows application updates

`infrastructure/updates/windows_update_service` owns WinSparkle configuration and
lifetime; `infrastructure/flutter/updates_channel_adapter` transports explicit
initialize/configuration/show calls. The Flutter window assembles them and forwards
a registered shutdown message to the channel on the platform thread. WinSparkle's
worker callback only posts that message and never touches a Flutter messenger.
Teardown clears the borrowed HWND and callbacks and joins updater work before
destroying the messenger. Debug builds do not initialize the updater.

The Dart `AppUpdatesController` owns settings actions and hands installation
shutdown to the existing `DesktopSettingsController.quit` workflow so tray mode
cannot intercept it. Shared updater settings remain independent of music-server
authentication and local library resets. A separate HTTPS feed probe checks
at startup and every two hours without WinSparkle UI, and the controller enables the single
Miscellaneous tile only when a newer Windows version is known. WinSparkle's own
automatic checks are disabled so its dialog opens only from that tile. WinSparkle
verifies every installer against the compiled Ed25519 key.
The controller owns the polling timer, skips overlapping checks and cancels it
on shutdown. The tile and updater are Windows-only; mobile platforms neither
show the tile nor initialize or schedule the desktop updater.

`updates.cmake` generates the feed URL and public key from the distribution
configuration, prepares the checksum-pinned SDK and installs its DLL and license.
The private signing key remains outside the app repository. See
[Windows packaging](../distribution_tools/windows/README.md#windows-updates-and-manual-github-releases)
for the manual build/sign/upload sequence and the explicit NSIS `/UPDATE` mode.
The native updater contract test injects a fake service and never starts
WinSparkle, contacts GitHub or executes an installer.
