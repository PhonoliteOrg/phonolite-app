# Phonolite Linux native C++ specification

This extends the [expected architecture](expected-architecture.md), [coding standards](coding-standards.md) and [Windows C++ specification](windows-native-specification.md) to the Flutter Linux host. Shared owners define common structure, design and behavior; specializations provide meaningful differences; assembly connects explicit dependencies. Linux adapts those principles to GTK 3, GObject, GLib/GIO, Flutter's C embedding API and CMake.

Use the established C++ preferences: snake_case operations, lower_snake_case files and folders, PascalCase types, public-contract-first headers, controlled state and logical spacing. Retain Linux's `.cc` implementation extension and the current C++14 baseline. The source map below describes the implemented host organization. Linux PCM playback uses an isolate-owned Dart FFI adapter to the desktop audio service.

## Current responsibilities and support

Flutter owns application pages, navigation, library state and playback workflows. The current Linux runner supplies the desktop host and folder opening:

| Current source | Responsibility | Owner |
| --- | --- | --- |
| [main.cc](../linux/runner/main.cc) | Create the application, run GApplication and release the owned application reference | Small process composition root |
| [MyApplication](../linux/runner/bootstrap/my_application.cc) | GObject application type, argument ownership, registration and activation | Bootstrap |
| [FlutterHost](../linux/runner/bootstrap/flutter_host.cc) | Per-window Flutter view/engine, plugin registration, capability assembly and teardown | Bootstrap |
| [ApplicationWindow](../linux/runner/ui/shell/application_window.cc) | GTK frame, title/header selection, initial geometry and presentation | UI/Shell |
| [Directory outcome](../linux/runner/data/models/directories/directory_open_result.h), [channel adapter](../linux/runner/infrastructure/flutter/directories_channel_adapter.cc) and [launcher](../linux/runner/infrastructure/shell/directory_launcher.cc) | Independent result values, Flutter wire handling and GIO opening | Data and separate Infrastructure capabilities |
| [Method response sender](../linux/runner/infrastructure/flutter/method_response_sender.cc) | Typed Flutter replies with caller-owned transport errors, shared by native channel adapters | Infrastructure/Flutter |
| [Window constraints adapter](../linux/runner/infrastructure/flutter/window_constraints_channel_adapter.cc) | Validate the `phonolite/window` content-size request and invoke the shell capability bound by FlutterHost | Infrastructure transport and UI/Shell sizing |
| [runner CMake](../linux/runner/CMakeLists.txt) | Explicit runner sources, generated registrant, compiler settings and target linkage | Runner build integration |
| [project CMake](../linux/CMakeLists.txt) | Application identity, Flutter/plugin integration, bundle installation and library lookup | Project build integration |
| [generated registrant](../linux/flutter/generated_plugin_registrant.cc), [generated plugin CMake](../linux/flutter/generated_plugins.cmake) and [Flutter CMake](../linux/flutter/CMakeLists.txt) | Managed embedding/plugin integration and ephemeral build output | Flutter-managed files |
| Package-specific Linux CMake and shared C/Rust sources | Decoder and transport libraries with stable FFI exports | Owning native packages |

The [output factory](../lib/infrastructure/audio/output/audio_output_factory.dart) selects [PulseAudioPlayer](../lib/infrastructure/platform/audio/linux/pulse_audio_output.dart) on Linux. The playback session accepts Linux for both streamed Opus and original/local decoded PCM. The adapter loads `libpulse.so.0`, connecting to either PulseAudio or PipeWire's PulseAudio compatibility service, and supports interleaved signed 16-bit and left-aligned 32-bit PCM. No development headers or extra native plugin are needed for production audio builds.

[Device discovery](../lib/infrastructure/platform/audio/audio_device_discovery.dart) currently advertises System Default only on Linux; route the application through the desktop sound settings. The [Now Playing service](../lib/infrastructure/platform/media/now_playing_platform_service.dart) has no Linux MPRIS integration yet. File selection, secure storage and other dependencies retain their plugin ownership.

### Audio and tray ownership

[NativePulseAudioStream](../lib/infrastructure/platform/audio/linux/native_pulse_audio_stream.dart) owns the libpulse mainloop, context, stream and pending flush operation. It pumps the asynchronous API with nonblocking iterations on the audio worker isolate, so no C callback enters a different isolate. Startup has a timeout and stop can close a connecting stream. The connection disables daemon autospawning and uses the desktop's existing service.

`PulseAudioPlayer` implements `BoundedAudioPcmOutput`: native writable capacity controls refill of its 200 ms queue. The shared timeline therefore does not apply its additional 125 ms audible-progress limit to Linux. Device latency can exceed that limit; waiting for audible consumption before replenishing the native queue would then starve playback despite decoded PCM being available. Playback credit still follows the latency-based clock rather than native writes or writable capacity.

The server queue is capped at 200 ms. Writes copy complete frames, yield on backpressure, and use a generation to cancel pending data on flush/disposal. Seeking waits for the server's flush acknowledgement before accepting new PCM and resets the playback clock. Reported progress subtracts the server's queued/device latency from written frames and never moves backwards within a generation; merely queueing samples does not count as listening. Interpolated latency can retain a residual frame after playback ends, so a server drain acknowledgement confirms consumption independently of that estimate. The shared timeline probes native completion only for a sealed source at the queue's tail. Ordinary progress reads never request a drain: continuous writes would keep it pending until the server's operation timeout. New writes cancel a pending probe, and pausing, seeking or disposal cancels it before suspending or releasing the stream. A drain covers only the frames written when it was requested; later writes need their own confirmation. One operation owner manages native acknowledgements and callback lifetimes. Pause corks the stream, and volume converts linear gain to PulseAudio's cubic volume scale. Native errors reach the playback owner instead of leaving an indefinitely blocked queue.

[NativeDesktopTray](../lib/infrastructure/platform/app/desktop_tray.dart) owns the tray icon, image, Show/Quit menu, native listeners and cleanup. `tray_manager` 0.8 uses StatusNotifierItem over D-Bus directly, removing the deprecated libayatana-appindicator dependency. Its native assets require Flutter 3.47 / Dart 3.13 and GTK 3/X11/XInput development files. No legacy API bridge or warning suppression is used. GNOME still needs a StatusNotifierItem/AppIndicator host extension.

### Build and runtime readiness

| Area | Current implementation | Remaining validation or work |
| --- | --- | --- |
| Desktop host | GTK window, Flutter engine/plugin registration, minimum content size, directory opening, icon and teardown | On-screen checks under X11 and Wayland remain manual |
| Tray and startup | Tray/window plugins and app-owned XDG autostart registration | Verify the desktop's AppIndicator host and actual login behavior manually |
| Secure storage | Local libsecret plugin with Phonolite labels and unchanged lookup attributes | An unlocked desktop Secret Service is needed at runtime; build checks never access the user's secrets |
| Native libraries | Opus decoder, local file decoder and QUIC transport built and bundled as shared libraries | Native decoder checks cover in-memory/file fixtures; a build does not test live server connections |
| Playback | Streamed/local PCM through PulseAudio or PipeWire-Pulse; pause, volume, seek/flush and latency-based progress | Headless queue/FFI tests pass; listening on real hardware remains manual |
| Devices and media controls | System Default is the only advertised Linux output | Native device enumeration and MPRIS integration are absent |
| Distribution | Full-bundle nFPM packages, signed GitHub metadata, independent coordinator and privileged installer | Production keys and clean-target installation/restart evidence are required before enabling each target |

Build prerequisites, including the required Git submodule and Ubuntu development packages, are listed in the [app README](../README.md#linux). Cross-compilation is not configured for the Rust libraries: build each architecture on a matching host/toolchain until explicit Cargo target/linker support is added.

## Responsibility boundaries and source organization

The runner keeps physical responsibility folders beneath its existing target. Standalone updater targets live under `linux/updater`, sharing data and infrastructure through an ordinary static library. Their Application workflows own authorization and installation sequencing; the user-session UI stays outside the privileged target. The helpers are built during packaging and do not add cryptography development dependencies to normal Flutter builds.

Runner organization:

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
        method_response_sender.h
        method_response_sender.cc
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
2. Construction sets the program name and application ID to `com.phonoliteorg.phonolite_app`, and the human-readable application name to `Phonolite`, with the default GApplication flags for single-instance registration. The executable remains `phonolite_app`.
3. Local command-line handling duplicates arguments after the executable name, registers the application, reports registration failure with status 1, then activates it with status 0 on success.
4. Activation creates a GTK application window with a 1280-by-720 default size. Both its window title and header-bar title use the human-readable application name.
5. The X11 compile guard and runtime screen check choose a header bar only for the exact window-manager name `GNOME Shell`; other X11 managers receive a conventional title. Wayland/default follows the header-bar path. Preserve the close-button rule.
6. Create FlDartProject with the stored arguments, create FlView, retain the black background, show the child and add it to the window.
7. Connect first-frame before realizing the view. The first frame reveals the top-level window.
8. Register generated plugins, attach the directory adapter to that view's engine messenger, then focus the view.

Keep the first-frame sequence in a named host/shell collaboration. Showing the window immediately, moving plugin registration ahead of view realization, changing engine sharing, introducing GTK 4/libadwaita or enforcing one window changes behavior and needs separate verification.

Process registration does not establish a single-window policy. Each activation still constructs a new view/window. Each window retains its own FlutterHost through a GObject data association, so a later activation cannot overwrite another engine's channel owner. Replacing the command-line vector first clears its previous allocation; Flutter projects retain their own argument copies.

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

The directory and window adapters share `send_method_response`, which uses Flutter's typed success/error/not-implemented responders. These preserve caller ownership of transport errors. The generic responder in the current embedding propagates an intermediate automatically freed GError, so using it on a failed transport can invalidate the adapter's error message. The native checks cover failure of all three reply types without retrying or starting an engine. Their test messenger interprets an empty envelope as not implemented before dispatching to the codec, matching Flutter's channel behavior.

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

The [Linux packaging and update implementation plan](linux_distribution_update_plan.md) sequences native packages published through GitHub Releases, signed update discovery, authorized package installation and application restart.

Keep runner membership explicit in [sources.cmake](../linux/runner/sources.cmake), shared by the production target and standalone compile checks. Update paths/includes together with physical moves. Preserve BINARY_NAME, APPLICATION_ID, generated registrant integration, Flutter assembly and bundle installation. Generated plugin registration and `linux/flutter` build glue remain tool-owned; generated changes should come from Flutter's dependency tooling.

The root/runner minimum is CMake 3.13, the FFI package entry points require 3.14, and vendored Opus raises the current full build's minimum to 3.16. The shared standard-settings helper selects C++14, `-Wall -Werror`, and non-Debug `-O3`/NDEBUG. Plugins also use that helper. The tray uses native assets from tray_manager 0.8/nativeapi rather than a generated AppIndicator plugin target; nativeapi owns its C++17 toolchain configuration separately.

The host links GTK 3, GLib and GIO through pkg-config. The installed secure-storage Linux CMake explicitly links libsecret >= 0.18.4; its parent package guidance and the app README also list jsoncpp dependencies. Verify actual build/runtime requirements against the selected plugin version and resulting ELF libraries. Secure storage expects the user's desktop Secret Service when the app runs. Compiling the plugin does not establish that the service is operational, and test doubles should not start it.

Secure storage scopes its keyring entry to APPLICATION_ID, currently `com.phonoliteorg.phonolite_app`. Changing that identity requires a fresh sign-in; credentials under a previous identity are not migrated automatically.

The [local secure-storage plugin](../packages/flutter_secure_storage_linux/README.md) retains upstream version 1.2.3 with the visible credential label `PhonoliteSecureStorage` and helper label `PhonoliteSecureStorage Control`, plus current Clang-compatible literal-operator spelling in its bundled JSON header. The root dependency override selects this copy. The lookup schema, account attribute and stored values retain upstream behavior. Existing credential entries receive the new label on their next write, without requiring another sign-in for the label change.

| Native package | Linux build/output | Ownership |
| --- | --- | --- |
| [phonolite_opus](../packages/phonolite_opus/linux/CMakeLists.txt) | Shared C facade with position-independent static Opus; `libphonolite_opus.so` | Decoder exports and shared upstream source; Linux Dart loading uses the bundled library |
| [phonolite_local_audio](../packages/phonolite_local_audio/linux/CMakeLists.txt) | Cargo library copied into the build; `libphonolite_local_audio.so` | Decoder handles, PCM, seek positions and release |
| [phonolite_quic](../packages/phonolite_quic/linux/CMakeLists.txt) | Cargo library with native TLS dependencies; `libphonolite_quic.so` | Transport, authentication, certificate identity, native events and allocations |

Preserve exported names, fixed-width arguments, units, opaque handles and matching close/free functions. Keep shared C/Rust implementations and vendored code in their packages. A new Linux PCM backend or MPRIS capability should extend the appropriate platform boundary and reuse Dart playback workflows rather than relocating business logic into Runner.

Cargo follows the host toolchain, selects debug only for Debug and release otherwise, and passes `--locked`. The top-level CMake sysroot does not configure Rust target/linker selection automatically. Local-audio tracks its Rust, vendored decoder and shared Opus inputs; QUIC tracks its Rust sources and Cargo manifests/lockfile. Both Linux Opus build paths optimize the codec in Debug while preserving debug symbols; the standalone package also optimizes Flutter's custom Profile mode. The standalone Opus package explicitly enables position-independent code for its static library and keeps its install prefix directory-scoped. The root bundle repairs the old plugin-owned cached install prefix while preserving an intentionally configured custom prefix.

Package builds may need cached Cargo, SQLite and native TLS dependencies or network downloads. Dependency preparation is not permission to start an application/server. Native package compilation is broader than a standalone runner source check.

The installed bundle contains the executable, `data` assets/ICU data and `lib` Flutter/plugin/FFI/native-asset libraries; non-Debug builds include the AOT library. Preserve `$ORIGIN/lib` lookup. The intermediate executable under `intermediates_do_not_run` is not the distributable app. Ship the whole installed bundle and inspect its ELF architecture, exports and transitive runtime dependencies on the intended Linux target. [Flutter Linux distribution](https://docs.flutter.dev/platform-integration/linux/building)

The [desktop launcher installer](../distribution_tools/linux/install_desktop_entry.py) registers a selected bundle under `$XDG_DATA_HOME/applications`, falling back to `~/.local/share/applications` when that variable is unset or relative. Its filename matches APPLICATION_ID, with `Name=Phonolite` and absolute executable/icon paths. It installs a self-contained SVG icon under the same data root's `icons/hicolor/scalable/apps`, embedding the existing PNG with a two-pixel transparent inset on each side at a 48-pixel dock size. GNOME uses this metadata to associate Wayland windows with their dock name and logo; setting the GTK window icon alone is insufficient. Re-register after moving the bundle or selecting a different build. This operation never starts the app and is separate from login autostart registration. [GNOME desktop integration](https://developer.gnome.org/documentation/guidelines/maintainer/integrating.html)

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

The [Dart directory tests](../test/platform/desktop_directory_service_test.dart), [desktop keyboard tests](../test/widgets/desktop_playback_shortcuts_test.dart), [desktop mouse tests](../test/widgets/desktop_mouse_navigation_test.dart), [logging tests](../test/architecture/app_logging_test.dart) and [output lifecycle tests](../test/architecture/audio_output_lifecycle_test.dart) provide existing headless anchors. The Linux output tests add cancellable queue/startup coverage and a headless fixture checks the real Dart FFI implementation against PulseAudio public headers.

The [Linux architecture checks](../test/architecture/linux_architecture_test.dart) verify source membership, layer boundaries, startup ordering, per-window teardown and directory wire contracts. [Standalone native checks](../linux/tests/CMakeLists.txt) separate portable result values from real-SDK platform checks. The [portable helper](../tools/linux_checks/verify_models.py) compiles the production data header as C++14 and runs three value checks:

```sh
python tools/linux_checks/verify_models.py --cxx g++
```

The platform checks compile the production runner against real GTK/Flutter headers and provide three GIO launcher cases plus seventeen channel/lifetime cases using real codecs/channels, an in-memory messenger and an injected URI launcher. They never initialize GTK, construct an engine/window or open a file manager. Prepare the real Flutter Linux embedding and generated plugin headers, then use:

```sh
cmake -S linux/tests -B .dart_tool/linux_native_checks -DPHONOLITE_ENABLE_PLATFORM_CHECKS=ON
cmake --build .dart_tool/linux_native_checks
ctest --test-dir .dart_tool/linux_native_checks --output-on-failure
```

To compile the optional PulseAudio ABI fixture, install `libpulse-dev` on a development/test host. The production app only needs the `libpulse0` runtime. CMake adds `libfake_pulse_audio.so` when it finds the public headers; run the fixture with:

```sh
PHONOLITE_PULSE_TEST_LIBRARY="$PWD/.dart_tool/linux_native_checks/libfake_pulse_audio.so" \
  flutter test --no-pub test/platform/linux_pulse_ffi_test.dart
```

The fixture implements libpulse entirely in memory and checks format/volume layouts, PCM bytes, playback latency, flush/drain acknowledgements, error propagation and handle cleanup. A 44.1 kHz production-worker regression verifies continuous refill when device latency exceeds the shared scheduling horizon. Its simulated server clock enforces a 30-second operation deadline; continuous playback through the production worker must pass that deadline without requesting completion or restarting. Residual-latency cases verify that the final frame completes, prepared successors become audible in order, and completion occurs once without a false output timeout. Pause, seek and writes racing a drain cannot credit unplayed data or inherit an obsolete deadline. It never connects to an audio server or opens hardware.

The standalone target avoids the Flutter app/native-package build graph. Set FLUTTER_EPHEMERAL_DIR when the prepared embedding is elsewhere. Portable-only mode is available with PHONOLITE_ENABLE_PLATFORM_CHECKS=OFF. A test that constructs GtkApplication, a real engine or a rendered window is not an unhosted logic check.

On a configured Linux build host, compilation can use:

```sh
flutter build linux --debug
flutter build linux --release
```

Run focused Dart checks without installing or launching the native app:

```sh
flutter test --no-pub test/platform/linux_audio_output_test.dart test/platform/desktop_lifecycle_platform_test.dart test/architecture/audio_output_lifecycle_test.dart test/architecture/gapless_playback_test.dart test/architecture/linux_architecture_test.dart test/platform/linux_startup_registration_test.dart test/platform/desktop_directory_service_test.dart test/widgets/desktop_playback_shortcuts_test.dart test/widgets/desktop_mouse_navigation_test.dart test/architecture/app_logging_test.dart test/architecture/opus_decoder_native_test.dart
```

The Opus native tests discover built Linux libraries and decode synthetic packets without opening an audio device. File/QUIC-source decoder tests accept `PHONOLITE_LOCAL_AUDIO_LIBRARY` pointing to the bundle's `lib/libphonolite_local_audio.so`; source callbacks use in-memory fixtures rather than a network listener. `audio_output_lifecycle_test.dart` and gapless playback tests can exercise the Linux session with injected devices, without opening hardware.

Check Profile when configuration behavior changes, and verify package rebuild inputs, bundle contents, runtime dependencies and exported FFI symbols where relevant. Linux x64 Debug/Profile/Release compilation, complete bundle dependency resolution, all 51 native decoder/transport header exports, real-SDK native checks, and focused audio/lifecycle/platform tests have been verified on Ubuntu 26.04. All three bundles include the native tray asset and have no AppIndicator library dependency. Opus packet decoding is checked against each built mode, and native file/source fixtures verify precision, seeking and cleanup without an audio device. This establishes build and headless integration readiness; GUI behavior, actual keyring access, live networking and audio-device output are separate runtime checks. During agent work, compilation and foreground headless verification are allowed; do not launch the app, file manager, display server, D-Bus/Secret Service, audio server or another background service. Desktop rendering, folder display and real hardware playback tests remain user-controlled.

## Packaged update boundary

`AppUpdateBackend` assembles one Linux platform/feed owner. Its transport uses system
certificate authorities independently of music-server pins. The installed native
coordinator verifies the exact Ed25519-signed manifest before Dart receives release
fields. Downloads use private staging, bounded HTTPS redirects/deadlines and a
signed length/SHA-256 check. The root installer independently repeats verification
on a protected copy and checks package ownership, host target and native identity.

The coordinator requests polkit authorization before asking Flutter to prepare.
`DesktopSettingsController.prepareForUpdate` drains accepted writes and propagates
cleanup failure. Only its successful preparation sends `prepared`; the installer
then requires the original PID/start-time identity to exit before invoking the
manager. The root-owned transaction lock also prevents another packaged instance
from starting during replacement. Debug builds have a separate `.devel` application
ID; application storage and production identity remain stable.

The helper uses fixed command vectors and never launches a GUI. APT refuses removals,
DNF retains local package signature checking, and Arch requires installed dependencies
without refreshing repositories or initiating a partial system upgrade. Native RPM
and Arch trust must already be established by the administrator. Receipts distinguish
transaction completion from desktop relaunch acknowledgement. Package failures do not
imply rollback; the coordinator presents repair guidance and never automatically
repeats or downgrades an ambiguous transaction.

The [release operations](linux_distribution_update_plan.md#release-operations) define
manual production key setup, gated target validation, artifact verification and
recovery. Only foreground headless tests and builds are automated in this workspace;
actual polkit dialogs, installation/removal and restart checks remain user-controlled.
