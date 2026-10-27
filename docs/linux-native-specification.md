# Phonolite Linux native C++ specification

This extends the [expected architecture](expected-architecture.md), [coding standards](coding-standards.md) and [Windows C++ specification](windows-native-specification.md) to the Flutter Linux host. Shared owners define common structure, design and behavior; specializations provide meaningful differences; assembly connects explicit dependencies. Linux adapts those principles to GTK 3, GObject, GLib/GIO, Flutter's C embedding API and CMake.

Use the established C++ preferences: snake_case operations, lower_snake_case files and folders, PascalCase types, public-contract-first headers, controlled state and logical spacing. Retain Linux's `.cc` implementation extension and the current C++14 baseline. The source map below describes the implemented host organization. Linux playback support remains separate feature work.

## Current responsibilities and support

Flutter owns application pages, navigation, library state and playback workflows. The current Linux runner supplies the desktop host and folder opening:

| Current source | Responsibility | Owner |
| --- | --- | --- |
| [main.cc](../linux/runner/main.cc) | Create the application, run GApplication and release the owned application reference | Small process composition root |
| [MyApplication](../linux/runner/bootstrap/my_application.cc) | GObject application type, argument ownership, registration and activation | Bootstrap |
| [FlutterHost](../linux/runner/bootstrap/flutter_host.cc) | Per-window Flutter view/engine, plugin registration, capability assembly and teardown | Bootstrap |
| [ApplicationWindow](../linux/runner/ui/shell/application_window.cc) | GTK frame, title/header selection, initial geometry and presentation | UI/Shell |
| [Directory outcome](../linux/runner/data/models/directories/directory_open_result.h), [channel adapter](../linux/runner/infrastructure/flutter/directories_channel_adapter.cc) and [launcher](../linux/runner/infrastructure/shell/directory_launcher.cc) | Independent result values, Flutter wire handling and GIO opening | Data and separate Infrastructure capabilities |
| [Window constraints adapter](../linux/runner/infrastructure/flutter/window_constraints_channel_adapter.cc) | Validate the `phonolite/window` content-size request and invoke the shell capability bound by FlutterHost | Infrastructure transport and UI/Shell sizing |
| [runner CMake](../linux/runner/CMakeLists.txt) | Explicit runner sources, generated registrant, compiler settings and target linkage | Runner build integration |
| [project CMake](../linux/CMakeLists.txt) | Application identity, Flutter/plugin integration, bundle installation and library lookup | Project build integration |
| [generated registrant](../linux/flutter/generated_plugin_registrant.cc), [generated plugin CMake](../linux/flutter/generated_plugins.cmake) and [Flutter CMake](../linux/flutter/CMakeLists.txt) | Managed embedding/plugin integration and ephemeral build output | Flutter-managed files |
| Package-specific Linux CMake and shared C/Rust sources | Decoder and transport libraries with stable FFI exports | Owning native packages |

Linux is not currently a complete playback platform. The [output factory](../lib/infrastructure/audio/output/audio_output_factory.dart) has no Linux PCM adapter, and the [playback session](../lib/infrastructure/audio/engine/session/playback_session.dart) explicitly rejects unsupported platforms. [Device discovery](../lib/infrastructure/platform/audio/audio_device_discovery.dart) returns only System Default on Linux. The [Opus package loader](../packages/phonolite_opus/lib/phonolite_opus.dart) lacks a Linux branch even though its Linux build produces a shared library. The local decoder and QUIC loaders already recognize their Linux `.so` files.

The [Now Playing service](../lib/infrastructure/platform/media/now_playing_platform_service.dart) supports iOS and Android. No Linux PCM backend, native output-device enumeration or MPRIS integration currently exists. These are explicit future features, not responsibilities to invent or silently implement during organization. File selection, secure storage and other dependencies keep their existing plugin ownership.

## Responsibility boundaries and source organization

Keep physical responsibility folders beneath the existing runner target:

```text
linux/
  .clang-format
  CMakeLists.txt
  runner/
    main.cc
    bootstrap/
      my_application.h
      my_application.cc
      flutter_host.h
      flutter_host.cc
    data/
      models/
        directories/directory_open_result.h
    infrastructure/
      flutter/
        directories_channel_adapter.h
        directories_channel_adapter.cc
        window_constraints_channel_adapter.h
        window_constraints_channel_adapter.cc
      shell/
        directory_launcher.h
        directory_launcher.cc
    ui/
      shell/
        application_window.h
        application_window.cc
    CMakeLists.txt
    sources.cmake                # Shared explicit runner membership
  flutter/                       # Managed embedding, registration and output
  tests/                         # Portable values and real-SDK unhosted contracts
```

The data outcome carries accepted/failed status and an owned error message shared by the launcher and adapter. Ordinary parameters do not require model wrappers. Add other directories only when real responsibilities appear.

| Area | Owns | Boundary |
| --- | --- | --- |
| Bootstrap | GApplication lifecycle, arguments, Flutter project/view construction, plugin registration and per-engine capability assembly | Constructs dependencies; feature code does not discover the application or search windows globally |
| Data | Independent values, configuration, outcomes and their natural validation/copy/comparison operations | No GtkWidget, GObject, GError, FlValue, channel or independently released native resource |
| Infrastructure | Flutter transport, GIO launching and other OS mechanisms | Typed inputs/results; no native layout or duplicated Dart library/playback policy |
| UI | Shared GTK frame/chrome, presentation and native interaction structure | Receives values and callbacks; no channel decoding, filesystem operations or playback algorithms |
| Application when needed | State, validation, cancellation and coordination for an actual native workflow | Native API access alone does not require a controller |
| Pages when needed | Assembly and controller binding for an actual native content view | Reuses shared native UI; Flutter pages remain in `lib/pages` |

Keep Data as its own silo. An owned `std::string` error message is a value; a GError pointer that needs freeing is a resource. A structure holding a GTK widget, channel or signal connection belongs with its infrastructure or presentation owner, regardless of the `struct` keyword.

Keep Application and Pages absent until they contain real native work. The current folder-opening feature needs a transport adapter and a platform capability. Do not add a parallel Linux application framework around the existing Dart controllers.

Independent models and capabilities get ordinary headers and compilation units outside an exclusive component's private tree. Keep small single-owner helpers local. Avoid Utils/Common collections, implementation-file includes and source-directory READMEs; architecture documentation belongs in `docs`.

## Shared abstractions and readable assembly

Apply the same mechanism demonstrated by Katiby's reusable frames, Phonolite's Dart page/navbar family and the other native hosts: common decisions have one implementation owner, while callers supply content, values and capabilities.

ApplicationWindow composes GtkApplicationWindow and owns the shared title/header, initial geometry and presentation rules. FlutterHost assembles a Flutter view into that frame and binds its engine capabilities. A new GTK subclass is justified by an actual shared extension contract; an empty superclass around GTK's existing frame adds no useful structure. The existing GtkApplication GObject subtype is a framework integration responsibility, not a reason to subclass every service.

The directory flow should read as:

```text
Dart DesktopDirectoryService prepares the absolute directory
  → DirectoriesChannelAdapter validates the method and scalar path
  → DirectoryLauncher converts the filename to a URI and requests GIO opening
  → a typed result returns the accepted status or owned native message
  → the adapter sends the existing Flutter response
```

Compose concrete services and narrow callbacks first. A single adapter may own its attachment mechanics directly. Extract a shared channel owner when several adapters share actual registration, dispatch, reply or teardown decisions. An interface names a contract; shared execution policy still needs a shared implementation.

Desktop window limits originate in Dart's `DesktopWindowConfiguration`. On Linux the lifecycle platform sends `setMinimumContentSize` with logical `width` and `height` on `phonolite/window`. The adapter accepts finite positive numeric dimensions that fit a GTK integer, rounds fractional minimums up and invokes its typed size callback. FlutterHost binds that callback to ApplicationWindow, which sets the borrowed Flutter content widget's minimum request. GTK then accounts for header bars, shadows and later geometry changes. Do not replace this with `window_manager`'s direct GDK geometry hints: its bounds omit client decorations while its hints target the decorated GDK window, and GTK can overwrite those hints. No native copy of the Dart breakpoint is required.

If native views are added, common frames own content/toolbar placement and fixed or scrolling toolbar behavior. Pages assemble named sections and bind actions. Application menus/navigation remain shell responsibilities; page actions belong to the page toolbar. Keep nested GTK widget assembly readable through named pieces, rather than reproducing the same container and styling sequence in every page.

## C++ and GObject coding conventions

| Item | Convention | Example |
| --- | --- | --- |
| Files and folders | lower_snake_case, `.h` and `.cc` | `infrastructure/shell/directory_launcher.cc` |
| C++ types and aliases | PascalCase | `DirectoryLauncher`, `DirectoryOpenResult` |
| Owned functions, methods, parameters and locals | snake_case | `open_directory`, `absolute_path` |
| C++ namespaces and scoped enum values | snake_case | `phonolite`, `DirectoryOpenStatus::accepted` |
| Private C++ instance members | snake_case with trailing underscore | `launch_uri_`, `directory_channel_` |
| Constants | Descriptive snake_case with constexpr where suitable | `default_window_width` |
| GObject types, registration and instance fields | Preserve the established GObject conventions | `MyApplication`, `my_application`, `MY_APPLICATION`, `parent_instance` |

Keep external APIs, generated names, callback signatures, exported C symbols and channel keys exact. `g_application_run`, `fl_register_plugins`, `phonolite_quic_close` and the wire method `openDirectory` are external contracts. GObject's required init/class-init hooks retain their registered prefixes. Do not place GObject macro-generated declarations in a C++ namespace without verifying their linkage and generated references.

Headers are self-contained and guarded. Include their required declarations and use forward declarations when incomplete types suffice. Put substantial implementation in `.cc`; small value operations can remain inline. A unique_ptr to a forward-declared collaborator generally needs an out-of-line owner destructor where the collaborator is complete. Avoid `using namespace` in headers.

Include an implementation's own header first, then separate standard-library, GTK/GLib/GIO, Flutter and app groups. Sort within groups unless a real dependency requires otherwise. Include Flutter through `<flutter_linux/flutter_linux.h>`; individual embedding headers are not its public inclusion boundary. Use the existing CMake include root for app paths such as `"runner/data/models/directories/directory_open_result.h"`, avoiding absolute machine paths and chains of `../../` includes. [Flutter Linux public header](https://api.flutter.dev/linux-embedder/fl__method__channel_8h_source.html)

C++ headers present constructors/destructor and the public contract first, then protected hooks for a genuine specialization family, then private helpers/state. Definitions group lifecycle, public operations, private operations and final assembly. Declare members in safe construction/destruction order; a layout preference must not reorder a dependency's lifetime. GObject implementation files keep their private instance layout and G_DEFINE_TYPE before code that needs the generated parent reference; forward declarations support callback registration where required.

Use C++14 features deliberately: unique_ptr, make_unique, enum class, explicit constructors, const access and owned strings. Do not introduce optional, variant, string_view or C++20 designated initializers without a separate language-standard change. Use ordinary methods on owned C++ types and static/free callback trampolines for C APIs. Prefer named result models for shared outcomes and small local tuples only where their meaning is clear.

The launcher exposes an injectable capability contract:

```cpp
class DirectoryLauncher {
 public:
  using UriLauncher = std::function<DirectoryOpenResult(const std::string&)>;

  DirectoryLauncher();
  explicit DirectoryLauncher(UriLauncher launch_uri);
  DirectoryOpenResult open_directory(const std::string& absolute_path) const;

 private:
  UriLauncher launch_uri_;
};
```

The outcome is independent data; the injected operation provides a useful test boundary without opening a file manager. The production owner performs the actual GIO operation. Do not add builders to every constructor. When a real configuration family benefits from fluent construction, retain individual setters and keep coordinated or fallible work behind named commands.

Use two-space indentation, attached braces and a 120-column target. Keep signatures compact when they fit. Separate preparation, independent guards, native calls, state changes, notification and final results with one blank line; keep related assignments together. Use early returns to reduce nesting and named assembly helpers for large UI expressions. Comments explain ownership, units, invariants and consequential choices rather than narrating obvious statements. Inspect responsibilities well before the shared guide's 1,000-line review boundary.

## GTK and Flutter lifecycle

Preserve the current application identity and startup behavior during extraction:

1. Main owns a MyApplication reference and returns `g_application_run`'s status.
2. Construction sets the program name and application ID to `com.example.phonolite_app`, with G_APPLICATION_NON_UNIQUE. The executable remains `phonolite_app`.
3. Local command-line handling duplicates arguments after the executable name, registers the application, reports registration failure with status 1, then activates it with status 0 on success.
4. Activation creates a new GTK application window with a 1280-by-720 default size and the current title.
5. The X11 compile guard and runtime screen check choose a header bar only for the exact window-manager name `GNOME Shell`; other X11 managers receive a conventional title. Wayland/default follows the header-bar path. Preserve the close-button rule.
6. Create FlDartProject with the stored arguments, create FlView, retain the black background, show the child and add it to the window.
7. Connect first-frame before realizing the view. The first frame reveals the top-level window.
8. Register generated plugins, attach the directory adapter to that view's engine messenger, then focus the view.

Keep the first-frame sequence in a named host/shell collaboration. Showing the window immediately, moving plugin registration ahead of view realization, changing engine sharing, introducing GTK 4/libadwaita or enforcing one window changes behavior and needs separate verification.

G_APPLICATION_NON_UNIQUE controls process registration; it does not establish a single-window policy. Each activation still constructs a new view/window. Each window now retains its own FlutterHost through a GObject data association, so a later activation cannot overwrite another engine's channel owner. Replacing the command-line vector first clears its previous allocation; Flutter projects retain their own argument copies. These cleanup corrections preserve the existing activation behavior.

The host connects normal window-destroy handling before view realization and clears its data association to release adapters before GTK's default child destruction. It also handles independent view destruction. An explicit engine reference keeps the messenger valid through detachment even when FlView has already cleared its own engine reference during disposal. Destruction unregisters the adapter and disconnects signal IDs before releasing that engine reference. The shell wrapper borrows its GTK-owned window rather than destroying or unrefing it a second time. Host creation is noexcept so native allocation failure cannot unwind through a GTK C callback.

Keep GTK mutation and Flutter platform operations on the owning main context. Callbacks from workers require explicit delivery, owner lifetime, relevance and cancellation rules. Do not introduce detached threads, blocking waits in UI callbacks or general asynchronous wrappers as a formatting change. Preserve the current synchronous directory operation unless concurrency is intentionally redesigned.

## Native ownership and cleanup

GObject allocation and C++ construction are different mechanisms. A GObject instance is allocated/initialized through GType, not ordinary C++ construction of embedded fields. Do not place std::string, unique_ptr or other nontrivial C++ members directly in its instance structure and assume constructors/destructors run. Keep GLib-compatible fields or a pointer to an explicitly constructed C++ owner, with deliberate destruction through the GObject lifecycle. Keep callbacks from propagating C++ exceptions through C frames. [GObject construction](https://docs.gtk.org/gobject/tutorial.html)

| Resource | Ownership rule |
| --- | --- |
| Owned GObject-based embedding object | Release its owned reference with g_object_unref or the correct g_autoptr cleanup |
| GTK widget | Follow floating-reference/container ownership; widget destruction and reference release are distinct operations |
| FlValue | Use fl_value_ref/fl_value_unref as required; it is not an ordinary GObject |
| GError | g_error_free or supported automatic cleanup; copy a message before releasing the error |
| Allocated filename/URI string | g_free or g_autofree |
| Duplicated argument vector | g_strfreev; clear the pointer after releasing it |
| C++ collaborator | Explicit construction and delete, normally encapsulated by unique_ptr in ordinary C++ ownership |
| Signal or channel user data | Identify who retains it and who disconnects/destroys it before the callback target becomes invalid |
| FFI handle, returned string or buffer | Use the owning package's matching close/free operation |

Use g_autoptr/g_autofree at supported GLib scope boundaries or an appropriately typed C++ custom deleter. Never default-delete a GObject, free a Rust allocation with g_free, or wrap a borrowed pointer as owned without taking the required reference.

Dispose can run more than once. Detach handlers/signals and release dependent object resources while their dependencies remain valid, clear owned pointers and chain the parent implementation. Finalize handles remaining non-object storage and chains its parent. MyApplication clears its argument vector in dispose; the per-window host owns channel cleanup. Empty startup/shutdown overrides have been removed, leaving inherited framework behavior. Do not add boilerplate hooks merely to match an ordering template. [GObject dispose](https://docs.gtk.org/gobject/vfunc.Object.dispose.html), [GObject finalize](https://docs.gtk.org/gobject/vfunc.Object.finalize.html)

An ordinary signal connection does not extend user-data lifetime. Own/disconnect the handler ID or use an appropriate receiver-lifetime connection where its threading contract fits. A channel/adapter should unregister its callback while the messenger is valid, then release its channel and dependencies before the engine/view. Avoid channel → callback → owner → channel reference cycles. Keep engine replacement and outstanding-call completion explicit.

The directory adapter removes its binary messenger handler as well as its method callback: FlMethodChannel's messenger retains the registered channel. A destroy-notify tracks replacement/closure so an older adapter's later detach cannot unregister a newer handler on the same channel. Attachment and detachment are idempotent. [Flutter channel implementation](https://raw.githubusercontent.com/flutter/engine/main/shell/platform/linux/fl_method_channel.cc)

## Directory channel contract

DirectoriesChannelAdapter owns the method name, FlValue validation, Flutter error envelopes and exactly one response attempt. DirectoryLauncher owns filename-to-URI conversion and GIO opening; its result contains copied values rather than a borrowed GError.

| Case | Existing Linux behavior to preserve |
| --- | --- |
| Request | `phonolite/directories`, `openDirectory`, one scalar string |
| Missing, wrong-type, empty or relative path | `invalid_path`, `An absolute folder path is required.`, null details |
| URI conversion | g_filename_to_uri with the supplied absolute filename and no hostname |
| Native operation | g_app_info_launch_default_for_uri with no launch context |
| Accepted | Null success result |
| Conversion or launch failure | `open_failed`, native GError message when present or `Could not open the folder.`, null details |
| Unknown method | Not-implemented response |
| Reply transport failure | One response attempt; log the failure without attempting a second method reply |

Do not substitute shell-command construction, manual `file://` concatenation, Windows path rules or macOS's weaker nonempty-path validation. Preserve current filename encoding and escaping behavior. The [Dart directory service](../lib/infrastructure/platform/files/desktop_directory_service.dart) already creates the absolute directory before invoking this channel; trimming, canonicalizing or adding filesystem checks changes the boundary. Non-UTF-8 filename/locale behavior needs its own review. [GLib filename conversion](https://docs.gtk.org/glib/func.filename_to_uri.html)

GIO success acknowledges that opening was accepted, not that a file manager finished displaying the folder. Preserve its native error message rather than collapsing it into a generic error. Switching to an asynchronous API needs deliberate completion/cancellation rules. [GIO URI launching](https://docs.gtk.org/gio/type_func.AppInfo.launch_default_for_uri.html)

A method call borrowed by a callback must be retained if its reply occurs later, then released after responding. Releasing its last reference without a response is an embedding error. Closing/replacing a channel handler and destroy-notify ownership must agree with the adapter's lifetime. An asynchronous native result does not authorize arbitrary GTK access from that callback thread. [Flutter Linux channel ownership](https://api.flutter.dev/linux-embedder/fl__method__channel_8h_source.html)

## CMake packages and deployment

Keep runner membership explicit in [sources.cmake](../linux/runner/sources.cmake), shared by the production target and standalone compile checks. Update paths/includes together with physical moves. Preserve BINARY_NAME, APPLICATION_ID, generated registrant integration, Flutter assembly and bundle installation. Generated plugin registration and `linux/flutter` build glue remain tool-owned; generated changes should come from Flutter's dependency tooling.

The root/runner minimum is CMake 3.13, the FFI package entry points require 3.14, and vendored Opus raises the current full build's minimum to 3.16. The shared standard-settings helper selects C++14, `-Wall -Werror`, and non-Debug `-O3`/NDEBUG. Plugins also use that helper. Apply app-specific settings to the app target rather than silently changing every dependency's language mode or diagnostics.

The host links GTK 3, GLib and GIO through pkg-config. The installed secure-storage Linux CMake explicitly links libsecret >= 0.18.4; its parent package guidance and the app README also list jsoncpp dependencies. Verify actual build/runtime requirements against the selected plugin version and resulting ELF libraries. Secure storage expects the user's desktop Secret Service when the app runs. Compiling the plugin does not establish that the service is operational, and test doubles should not start it.

| Native package | Linux build/output | Ownership |
| --- | --- | --- |
| [phonolite_opus](../packages/phonolite_opus/linux/CMakeLists.txt) | Shared C facade with vendored Opus; `libphonolite_opus.so` | Decoder exports and shared upstream source; Linux Dart loading still needs implementation |
| [phonolite_local_audio](../packages/phonolite_local_audio/linux/CMakeLists.txt) | Cargo library copied into the build; `libphonolite_local_audio.so` | Decoder handles, PCM, seek positions and release |
| [phonolite_quic](../packages/phonolite_quic/linux/CMakeLists.txt) | Cargo library with native TLS dependencies; `libphonolite_quic.so` | Transport, authentication, certificate identity, native events and allocations |

Preserve exported names, fixed-width arguments, units, opaque handles and matching close/free functions. Keep shared C/Rust implementations and vendored code in their packages. A new Linux PCM backend or MPRIS capability should extend the appropriate platform boundary and reuse Dart playback workflows rather than relocating business logic into Runner.

Cargo currently follows the host toolchain, selects debug only for Debug and release otherwise, and does not pass `--locked`. The top-level CMake sysroot does not configure Rust target/linker selection automatically. Local-audio's output command lacks source DEPENDS, while QUIC tracks sources and Cargo manifests/lockfile. Opus modifies install settings and links a static library into a shared facade; verify install-prefix isolation and position-independent compilation on the actual Linux build. Keep such build-correctness work separate from source moves.

Package builds may need cached Cargo, SQLite and native TLS dependencies or network downloads. Dependency preparation is not permission to start an application/server. Native package compilation is broader than a standalone runner source check.

The installed bundle contains the executable, `data` assets/ICU data and `lib` Flutter/plugin/FFI/native-asset libraries; non-Debug builds include the AOT library. Preserve `$ORIGIN/lib` lookup. The intermediate executable under `intermediates_do_not_run` is not the distributable app. Ship the whole installed bundle and inspect its ELF architecture, exports and transitive runtime dependencies on the intended Linux target. [Flutter Linux distribution](https://docs.flutter.dev/platform-integration/linux/building)

## Formatter

Use clang-format **19.1.5** with [linux/.clang-format](../linux/.clang-format), matching the Windows C++ preferences:

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

The configuration permits compact signatures within the line target and limits excess whitespace. Developers still define logical paragraphs and meaningful component boundaries. Format an explicit list of handwritten runner/test `.h`/`.cc` files; use `-i` to apply or `--dry-run --Werror` to check. Include new responsibility folders when refactoring, and exclude generated registration, ephemeral artifacts, dependencies and vendored code. [LLVM formatting options](https://clang.llvm.org/docs/ClangFormatStyleOptions.html)

## Maintenance and verification

For future changes, preserve these boundaries:

1. Keep typed directory outcomes, GIO launching and channel parsing separate while retaining the wire contract.
2. Reuse the GTK shell from Flutter assembly, preserving first-frame timing and backend-specific chrome.
3. Keep application lifecycle/arguments and per-window engine capabilities under explicit Bootstrap ownership.
4. Align CMake membership, includes and generated integration with physical moves.
5. Verify invalid input, native failure, response lifetime, repeated activation and handler teardown as the affected contracts evolve.

The [Dart directory tests](../test/platform/desktop_directory_service_test.dart), [desktop keyboard tests](../test/widgets/desktop_playback_shortcuts_test.dart), [desktop mouse tests](../test/widgets/desktop_mouse_navigation_test.dart), [logging tests](../test/architecture/app_logging_test.dart) and [output lifecycle tests](../test/architecture/audio_output_lifecycle_test.dart) provide existing headless anchors. They do not verify a Linux audio backend. Some native-decoder tests currently search Windows libraries and skip other hosts; injected streaming tests can still encounter the Linux platform guard.

The [Linux architecture checks](../test/architecture/linux_architecture_test.dart) verify source membership, layer boundaries, startup ordering, per-window teardown and directory wire contracts. [Standalone native checks](../linux/tests/CMakeLists.txt) separate portable result values from real-SDK platform checks. The [portable helper](../tools/linux_checks/verify_models.py) compiles the production data header as C++14 and runs three value checks:

```sh
python tools/linux_checks/verify_models.py --cxx g++
```

The platform checks compile the production runner against real GTK/Flutter headers and provide three GIO launcher cases plus fifteen channel/lifetime cases using real codecs/channels, an in-memory messenger and an injected URI launcher. They never initialize GTK, construct an engine/window or open a file manager. These platform checks are prepared but have not been executed from the Windows workspace. Prepare the real Flutter Linux embedding and generated plugin headers, then use:

```sh
cmake -S linux/tests -B .dart_tool/linux_native_checks -DPHONOLITE_ENABLE_PLATFORM_CHECKS=ON
cmake --build .dart_tool/linux_native_checks
ctest --test-dir .dart_tool/linux_native_checks --output-on-failure
```

The standalone target avoids the Flutter app/native-package build graph. Set FLUTTER_EPHEMERAL_DIR when the prepared embedding is elsewhere. Portable-only mode is available with PHONOLITE_ENABLE_PLATFORM_CHECKS=OFF. A test that constructs GtkApplication, a real engine or a rendered window is not an unhosted logic check.

On a configured Linux build host, compilation can use:

```sh
flutter build linux --debug
flutter build linux --release
```

Run focused Dart checks without installing or launching the native app:

```sh
flutter test --no-pub test/architecture/linux_architecture_test.dart test/platform/desktop_directory_service_test.dart test/widgets/desktop_playback_shortcuts_test.dart test/widgets/desktop_mouse_navigation_test.dart test/architecture/app_logging_test.dart test/architecture/audio_output_lifecycle_test.dart
```

Check Profile when configuration behavior changes, and verify package rebuild inputs, bundle contents, runtime dependencies and exported FFI symbols where relevant. Portable value checks, source contracts and formatting passed from the Windows workspace. GTK/Flutter Linux compilation and the real-SDK native checks remain unverified here; they require a configured Linux host. During agent work, compilation and foreground headless verification are allowed; do not launch the app, file manager, display server, D-Bus/Secret Service, audio server or another background service. Desktop rendering, folder display and eventual real playback tests remain user-controlled.
