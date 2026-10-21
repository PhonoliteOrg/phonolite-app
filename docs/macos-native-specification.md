# Phonolite macOS native specification

This extends the [expected architecture](expected-architecture.md), [coding standards](coding-standards.md) and [iOS Swift specification](ios-swift-specification.md) to the Flutter macOS host. The same rule governs every responsibility: shared abstractions define common structure, design and behavior; specialized components provide meaningful differences; assembly connects them through explicit dependencies.

Use the established Swift preferences: PascalCase responsibility folders and type/file names, lowerCamelCase members, ordinary methods on their owning types, focused conformance extensions, controlled state and logical spacing. Native C keeps its own language conventions and exported ABI. The layout below defines the expected refactor; the current macOS source has not yet been reorganized.

## Current source responsibilities

Flutter owns application pages, navigation, playback workflows and library state. The native host supplies AppKit hosting, folder opening, PCM output and build integration.

| Current source | Responsibility | Expected owner |
| --- | --- | --- |
| [AppDelegate.swift](../macos/Runner/AppDelegate.swift) | Application entry point, last-window termination and secure restoration policy | Bootstrap |
| [MainFlutterWindow.swift](../macos/Runner/MainFlutterWindow.swift) | Nib-based window entry point, Flutter view assembly, plugin registration and directory channel | Bootstrap for host assembly; Infrastructure for extracted channel and Shell operations |
| [phonolite_audio.c](../macos/Runner/phonolite_audio.c) and [header](../macos/Runner/phonolite_audio.h) | Exported C interface, AudioQueue lifecycle, PCM buffers, completion accounting and output-device discovery | Infrastructure/Audio/Native with focused playback and device capabilities |
| [build_opus_static.sh](../macos/Runner/build_opus_static.sh) | Compile shared Opus sources into the Runner archive | Scripts and native build configuration |
| [MainMenu.xib](../macos/Runner/Base.lproj/MainMenu.xib) | Application/delegate connections, menu responder actions and initial window configuration | AppKit resource assembly at its registered path |
| [Info.plist](../macos/Runner/Info.plist), entitlements, [Configs](../macos/Runner/Configs/AppInfo.xcconfig) and [Xcode project](../macos/Runner.xcodeproj/project.pbxproj) | Bundle identity, startup resources, capabilities, target membership and linking | Host configuration and build integration |
| [GeneratedPluginRegistrant.swift](../macos/Flutter/GeneratedPluginRegistrant.swift) | Generated plugin registration | Flutter-managed integration |

The [Dart audio factory](../lib/infrastructure/audio/output/audio_output_factory.dart) selects CoreAudioPlayer on macOS. [CoreAudioBindings](../lib/infrastructure/platform/audio/apple/core_audio_bindings.dart) resolves the Runner's audio symbols from the process. The [desktop directory service](../lib/infrastructure/platform/files/desktop_directory_service.dart) creates the absolute directory before invoking its native channel.

macOS currently has no app-owned native content pages, CarPlay, Now Playing channel or remote-command service. The [Now Playing service](../lib/infrastructure/platform/media/now_playing_platform_service.dart) supports iOS and Android. Introduce macOS integrations as explicit features with their own contracts. UIKit, iOS scenes and AVAudioSession are outside this host's architecture.

## Responsibility boundaries

| Area | Owns | Boundary |
| --- | --- | --- |
| Bootstrap | AppKit entry points, engine/view construction, plugin registration and dependency lifetimes | Other areas do not import or discover the concrete host |
| Data/Models | Independent values, configuration, snapshots and outcomes with their natural validation/copy/comparison methods | No windows, channels, AudioQueues, callbacks or independently released resources |
| Data/Storage | Focused storage of native data when native persistence is actually needed | Capability use and presentation remain with their owners |
| Infrastructure | Flutter transport, NSWorkspace access, AudioQueue/CoreAudio resources and platform mechanisms | Typed capabilities; no duplicate Dart playback or library policy |
| Application | State transitions, validation and request coordination for an actual native workflow | No AppKit layout, Flutter codec dictionaries or raw audio-buffer ownership |
| Pages | Assembly and controller binding for an actual native content view | Reuses shared presentation; does not define repeated styling or functional workflows |
| UI | Shared native controls, design tokens, frames, toolbars and presentation structures | Receives values/actions; no channel decoding, file operations or playback algorithms |
| Scripts | Build-time native compilation and packaging mechanisms | No application behavior or hand-maintained generated output |

Data remains its own silo across languages. A reusable configuration record belongs there even when its first consumer is a native service. A C struct containing an AudioQueue, mutex, buffers and callback state is a resource implementation and stays with that infrastructure owner. The `struct` keyword alone does not make something a data model.

AppKit's NSWindow already supplies the standard window structure. A small subclass that assembles a Flutter engine belongs in Bootstrap. When app-owned window design or behavior becomes a reusable family, give it a shared owner in `UI/Shell` and specialize or compose it from the host. Do not manufacture an empty base class to wrap NSWindow.

Keep native Pages and Application absent until they contain real responsibilities. Flutter pages remain under `lib/pages`; embedding Flutter does not turn every native host window into an application page.

## Expected source organization

Use physical folders that match Xcode groups inside the existing Runner module. The initial extraction should have this shape:

```text
macos/
  .swift-format
  Scripts/
    build_opus_static.sh
  Runner/
    Bootstrap/
      AppDelegate.swift
      MainFlutterWindow.swift
      FlutterEngineBinding.swift
    Infrastructure/
      Flutter/
        DirectoriesChannelAdapter.swift
      Shell/
        DirectoryLauncher.swift
      Audio/
        Native/
          phonolite_audio.h
          phonolite_audio.c
          audio_queue_player.h
          audio_queue_player.c
          audio_output_devices.h
          audio_output_devices.c
    Base.lproj/
      MainMenu.xib
    Assets.xcassets/
    Configs/
    Info.plist
    DebugProfile.entitlements
    Release.entitlements
  RunnerTests/
  Flutter/                       # Managed registration, configuration and output
  Runner.xcodeproj/
  Runner.xcworkspace/
  Podfile
  Podfile.lock
```

MainFlutterWindow remains the nib entry point. FlutterEngineBinding assembles and retains the channel adapter for the specific engine; the window owns its binding. It need not become a second owner of the view controller already retained by AppKit. AppDelegate keeps application policy and required framework forwarding. Add an app-scoped NativeHost only when services genuinely outlive individual windows or several bindings need shared coordination.

DirectoriesChannelAdapter owns wire parsing and replies. DirectoryLauncher accepts a typed URL and performs the NSWorkspace operation; returning Bool is sufficient for the current accepted/failed outcome. The C facade preserves the public ABI, the queue player owns playback resources and accounting, and the device capability owns CoreAudio enumeration. These are ordinary compilation units with headers, not included `.c` implementation fragments.

Create `Data/Models`, `Data/Storage`, `Application`, `Pages` and `UI` owners when their actual values, policies or views appear. For example, a native device picker could use `Data/Models/Audio/OutputDevice.swift`, an Application controller and a page assembled from shared UI structures. Do not duplicate the existing Dart picker just to populate this tree.

An exclusive component directory contains that component and its private implementation. An independently meaningful model, service or reusable structure belongs in its responsibility area outside that component's private tree. Avoid broad Utils, Helpers and Common collections, and keep documentation in `docs` without source-directory READMEs.

## Shared abstractions and assembly

Consistency must come from shared code. Use Katiby's reusable frames and named assembly pieces, Phonolite's Dart BasePage/navbar family, and the iOS transport/presentation families as precedents for the mechanism, while respecting each platform's lifecycle.

| Family | Shared owner defines | Specialization or assembly supplies |
| --- | --- | --- |
| Native frames and toolbars | Common chrome, spacing, adaptive layout and placement | Page content and semantic actions |
| Native controls and sections | Appearance, interaction states and recurring arrangements | Labels, values, variants and callbacks |
| Native functional workflows | Repeated state transitions, cancellation, relevance and notification policy | Feature commands, data and injected capabilities |
| Flutter channels | Shared attachment, invocation and teardown mechanics when several adapters need them | Channel/method names, typed decoding and feature replies |
| Native audio capabilities | Queue ownership, buffer lifecycle and completion rules | PCM values and deliberately supported configuration |
| Native data operations | Shared value or storage rules | Subject-specific data and schema |

The current single directory adapter can own its attachment mechanics directly. Extract a common FlutterChannelAdapter when multiple adapters share actual lifecycle decisions; a generic base is not required before there is a family. A protocol defines a contract; repeated behavior still needs a shared implementation owner.

For native views added later, a shared page/frame must own the recurring content and toolbar arrangement, including fixed or scrolling toolbar behavior where relevant. Pages assemble content into that structure. App-level menus and navigation belong to the shell; page actions belong to the page toolbar. Keep final assembly readable through named controls and sections instead of deeply nested view or constraint construction.

Prefer composition for capabilities that do not share an identity or lifecycle. Add superclass hooks only for a real family with narrow variation points. Extract independent work into an ordinary owner rather than spreading a delegate across feature extension files.

## Swift files and type organization

Use PascalCase Swift filenames/types and responsibility folders, such as `Infrastructure/Shell/DirectoryLauncher.swift`. Use lowerCamelCase methods, properties and parameters with useful argument labels: `openDirectory(at:)`, `attach(to:)`, `publish(snapshot:)`. Swift initialisms such as `deviceID` and `artworkURL` are appropriate. Keep external selectors, framework overrides, wire keys and generated names exact.

Order each file as imports, closely related contract declarations, the primary type, then focused same-file conformance extensions and tightly coupled supporting types. Group Foundation/AppKit imports, FlutterMacOS or other dependencies, and actual project modules with blank lines; sort within groups and import only what is used. Swift imports modules rather than source paths. A folder inside Runner does not create a new module or require per-file imports.

Apply the same member order as the iOS standard, omitting empty groups:

1. Static constants and immutable shared definitions.
2. Inputs, callbacks, configuration and injected dependencies.
3. Private mutable state and owned resources.
4. Initializers and construction helpers.
5. Accessors, with deliberate getter/setter pairs together.
6. Initialization, lifecycle, attachment and shutdown in lifecycle order.
7. Public operations and shared extension contracts grouped by responsibility.
8. Private operations and named presentation pieces.
9. Final host/view assembly when the type has that role.

Keep property initialization and superclass/callback ordering correct when moving declarations. Swift has no C++ access sections or protected access level; do not copy the Windows public-first header layout mechanically.

Use `private` for implementation state, `private(set)` for observable state controlled by its owner, and default `internal` access for Runner collaborators. Add public/open access only for a real module or extension contract. Mark concrete owners `final` unless a framework or shared family intentionally permits subclassing. Preserve NSObject inheritance, `@objc`, outlets and selectors where the AppKit contract requires them.

Ordinary methods belong on the type the project owns. Use focused extensions mainly for protocol conformance or useful conveniences on external types. Keep superclass lifecycle overrides on the primary declaration. Same-file extensions can share private implementation; another `Type+Feature.swift` file cannot provide Dart-style shared library privacy or add stored properties. Extract a collaborator instead of widening mutable state to split a file.

Prefer `let`, explicit public contracts, inferred obvious locals, early guards and typed results. Avoid unnecessary force unwraps/casts, `try!`, nested ternaries and blanket error swallowing. Short single-expression operations can use concise Swift syntax; multi-step operations should have explicit returns and visible sequencing.

The following small capability illustrates dependency injection, ordinary owner methods and logical spacing. It can be tested with a closure that records the URL without opening Finder:

```swift
import AppKit
import Foundation

final class DirectoryLauncher {
  private let openURL: (URL) -> Bool

  init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
    self.openURL = openURL
  }

  func openDirectory(at directory: URL) -> Bool {
    return openURL(directory)
  }
}
```

The adapter constructs the file URL after validating the message. The service does not invent path normalization, directory creation or extra validation. AppKit access stays on the platform main thread.

## Data and readable operations

Use structs/enums for values and classes for identities, delegates and resource owners. Keep calculations, validation and copying with the natural data owner. Choose equality by responsibility: content equality for suitable values, explicit identity comparisons for entities, reference identity for services/controllers. A struct containing references is not automatically deeply immutable or Sendable.

Prefer named models for concepts shared across files; tuples are suitable for small local results. Swift value copying can express a local update directly. If a reusable patch API needs unchanged, cleared and replaced states, represent those states explicitly; an ordinary optional argument cannot communicate all three. Preserve existing missing/null behavior at each transport boundary.

Allow individual property setters for supported local changes. Coordinated work, failure or asynchronous execution deserves a named command. A fluent builder is optional for a real configuration family; keep one configuration call per line and retain individual setters. Do not add builders around every initializer or replace existing Apple APIs for stylistic symmetry.

Use two-space indentation, attached braces and a 120-column target. Keep one blank line between members and between logical paragraphs: preparation, independent guards, platform calls, state changes, notification and final results. Keep related assignments contiguous. A return inside a simple guard stays with that guard; separate a final return from earlier work. The formatter limits excess whitespace but does not identify logical paragraphs.

```swift
func directoryURL(from argument: Any?) -> URL? {
  guard let path = argument as? String, !path.isEmpty else {
    return nil
  }

  return URL(fileURLWithPath: path, isDirectory: true)
}
```

Comments explain contracts, units, ownership and consequential decisions. Use `///` for supported API contracts when useful. Avoid narration of obvious statements and decorative section banners. Inspect responsibilities well before a file reaches the shared guide's 1,000-line review boundary; that is not a desired file size or an installed native lint rule.

## AppKit and Flutter lifecycle contracts

Preserve the current nib lifecycle during extraction:

1. Create the FlutterViewController.
2. Save the existing window frame, install the content view controller and restore the frame with display enabled.
3. Register generated plugins for that controller.
4. Attach the directory channel to that engine's binary messenger.
5. Forward `super.awakeFromNib()` in its existing final position.

Changing this sequence, creating a separate shared engine or supporting multiple windows is a lifecycle change that needs its own verification. A file move does not require migrating to a newer Flutter hosting API.

Preserve AppDelegate's `@main` entry point, FlutterAppDelegate inheritance and true results for last-window termination and secure restorable state. `MainMenu.xib` identifies AppDelegate and MainFlutterWindow in module Runner, connects the delegate's `applicationMenu` and `mainFlutterWindow`, and configures the resizable initial 800-by-600 window. `Info.plist` selects `MainMenu` and `NSApplication`. Keep class names, target module, outlets, responder actions, menu shortcuts and resource registration aligned with filesystem changes.

A binding belongs to one engine/messenger. Attachment should be idempotent for that binding; engine replacement requires explicit detachment and rebinding. Remove method handlers while their messenger remains valid, then release dependent owners. A channel's name identifies its communication path, and a nil method handler unregisters it. [Flutter macOS channel contract](https://api.flutter.dev/macos-embedder/interface_flutter_method_channel.html)

Keep each request's exactly-once reply obligation visible, including unknown methods, failures and a released owner. A weak capture must still complete an outstanding request where the contract requires it. Do not search all windows or reach through `NSApplication.shared.delegate` from feature code to recover dependencies.

| Directory request case | Existing macOS behavior |
| --- | --- |
| Request | Channel `phonolite/directories`, method `openDirectory`, one scalar string |
| Missing, wrong-type or empty path | `invalid_path`, message `A folder path is required.`, nil details |
| Native operation | `URL(fileURLWithPath: path, isDirectory: true)` passed to `NSWorkspace.shared.open` |
| Opening accepted | Nil success reply |
| Opening failed | `open_failed`, message `Could not open the folder.`, nil details |
| Unknown method | `FlutterMethodNotImplemented` |

Keep the scalar payload, path spelling and Bool-to-reply mapping. The current Swift path does not have Windows' separate malformed-UTF-8 branch or integer Shell error details. Acceptance does not mean Finder has finished displaying the folder. The current [NSWorkspace operation](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)) remains the platform capability.

## Native C audio organization and ownership

Keep the exported `phonolite_audio_*` facade C-compatible. Preserve all twelve declared functions, integer widths, pointer types, `extern "C"` guards, opaque PhonoliteAudioPlayer handles, symbol visibility and retention. Moving source must preserve process symbol lookup. Changing C to Objective-C/Swift or adding a method-channel PCM path is a separate implementation change.

Use lower_snake_case C files, functions, fields and locals for owned code being materially refactored; use PascalCase named types and retain required Apple member/API names. Header guards and ABI macros retain their established conventions. A public C header presents includes, C linkage guards, opaque/value declarations and operations in readable lifecycle order. Keep implementation-only declarations in local static helpers or a focused internal header.

Keep resource internals with the queue player. Do not publish its buffer list, queue or mutex to unrelated files merely to shorten one implementation. A device-discovery module is independently meaningful and gets its own ordinary header/source pair. Private helpers that only support one operation remain local. Do not include `.c` files to share private scope.

Preserve these runtime contracts when extracting:

| Contract | Behavior to retain |
| --- | --- |
| PCM format | Interleaved, signed packed 16-bit samples; sampleCount counts Int16 values, not frames or bytes |
| Start and backpressure | Start once queued data is ready; five in-flight buffers; queue-full result `-3` remains distinguishable from other failures |
| Buffer ownership | Write copies caller samples into an owned AudioQueue buffer; completion releases the tracked entry/buffer |
| Progress | Collect completed sample counts with atomic exchange; keep sample/channel/time conversion at its existing Dart owner |
| Flush | Advance the generation, reset in-flight/completed accounting and reset the queue; old completions must not count toward the new generation |
| Close | Invalidate accounting, stop/dispose synchronously, then release remaining bookkeeping and the player |
| Pause, resume and volume | Preserve lazy restart, error state transitions and volume clamping to zero through one |
| Device discovery | Filter alive output devices; preserve enumeration order, IDs/sentinels, caller-owned UTF-8 name buffers and return meanings |

AudioQueue callbacks execute independently of the Dart caller. Preserve mutex/atomic boundaries, callback context lifetime and release ordering. Their presence does not establish that every player operation is safe for arbitrary concurrent callers. Document the supported call sequence rather than adding an unverified thread-safety guarantee.

C allocation pairs, CoreFoundation ownership and AudioQueue buffer ownership remain explicit. A borrowed PCM pointer must not escape write after the existing copy. A queue disposal/callback boundary must finish before freeing its context; an ordinary Swift deinit or actor does not establish that guarantee. Do not introduce logging, main-actor hops, Flutter messages or general task scheduling into the callback path during organization.

The current device-selection attempt writes `kAudioQueueProperty_CurrentDevice` and ignores its status. Preserve that behavior during extraction; correcting the property's representation or making selection failure observable requires focused Apple SDK and hardware verification. Likewise, buffer/error correctness changes need their own evidence rather than being hidden in a structural refactor.

## Isolation and asynchronous work

AppKit presentation, window/menu mutation and outgoing Flutter invocation use the platform main thread. Incoming channel handlers may have a configured task queue; do not infer UI permission from a reply callback's threading rules. Verify the selected engine's contracts when changing queues. [Flutter channel threading](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading)

Give every mutable owner one documented isolation domain. Preserve the current supported callback/queue boundaries during an organization refactor. Use `@MainActor`, actors and async/await where a deliberate concurrency change benefits from them, with the selected deployment target and language mode verified. Do not add Task wrappers everywhere, unchecked Sendable conformances or a Swift 6 mode change merely to move files.

An await allows other work to change state. Request generation, engine/window identity, cancellation and exactly-once completion still matter after suspension. The creator owns task, observer and handler cleanup unless ownership transfers. Use weak captures for actual cycles or borrowed lifetimes, and explicit stop operations for shutdown that must await work. Keep audio's C synchronization contract distinct from Swift actor isolation.

## Xcode sandbox and package integration

Swift folder organization is a project choice. XIB class/module identity, source target membership, build phases and linked symbols are executable contracts. This [Xcode project](../macos/Runner.xcodeproj/project.pbxproj) uses explicit file references and Sources entries. Moves must update those paths, the Opus script invocation/input/output paths, resource references and any relative header imports together. Keep generated registration and Flutter assembly tool-owned.

Runner and the [Podfile](../macos/Podfile) declare macOS 10.15; Runner uses Swift language mode 5.0 and GNU C11. The local-audio and QUIC podspecs require macOS 11.0. The current [Podfile.lock](../macos/Podfile.lock) lists only Opus and older plugin integration, while the generated registrant includes additional plugins. Resolve the effective minimum and dependency state on the Apple build environment before claiming compatibility or migrating language settings. Swift language mode does not identify the compiler or formatter version.

Preserve the current entitlement split. [DebugProfile.entitlements](../macos/Runner/DebugProfile.entitlements) enables sandboxing, outgoing/incoming networking and JIT; [Release.entitlements](../macos/Runner/Release.entitlements) enables sandboxing and outgoing networking. Both contain an empty keychain access-group array. The plist currently allows arbitrary ATS loads. Altering these settings changes capabilities or network policy and belongs to explicit feature/security work.

New file access must use the appropriate sandbox capability. A path or Finder-opening request does not grant arbitrary read/write access. If persistent user-selected resources require security-scoped bookmarks, keep saved bookmark data in Data/Storage and active access lifetime in Infrastructure. Preserve Flutter's development entitlement exceptions and check each build configuration when changing capabilities. [Flutter macOS entitlement guidance](https://docs.flutter.dev/platform-integration/macos/building#entitlements-and-the-app-sandbox)

Keep shared native packages in their own source trees:

| Package | macOS integration | Ownership |
| --- | --- | --- |
| [phonolite_opus](../packages/phonolite_opus/macos/phonolite_opus.podspec) | Podspec C source compilation; Runner also has its own static-build/force-load path | Shared Opus decoder and vendored source |
| [phonolite_local_audio](../packages/phonolite_local_audio/macos/phonolite_local_audio.podspec) | Rust static archive, Objective-C link anchor and CocoaPods configuration | Local decoding, opaque handles, PCM and seek results |
| [phonolite_quic](../packages/phonolite_quic/macos/phonolite_quic.podspec) | Rust static archive, Objective-C link anchor and CocoaPods configuration | Transport, authentication, certificate identity and native allocations |

The package loaders try their packaged macOS framework and can fall back to process lookup. Preserve export names, calling conventions, linker anchors, archive retention, units and matching close/free functions. Rust-allocated QUIC strings require the package's free function. Do not move Rust implementations or upstream Opus into Runner to make the host tree symmetrical. Native C, Objective-C link anchors, shell scripts and Rust retain appropriate language conventions.

The active Runner Opus phase builds `Runner/libphonolite_opus.a`, and all three configurations force-load that archive. Its script computes repository paths from its location and currently uses the host clang target without an explicit universal-architecture loop. The package podspec also defines Opus compilation with C99. Assess consolidation, architecture coverage and artifact locations as explicit build work; preserve both definitions until the chosen replacement is verified. Moving the script to Scripts requires updating its root calculation and Xcode references.

## Formatter configuration

Use the Swift project's swift-format tool with [macos/.swift-format](../macos/.swift-format), matching the iOS configuration:

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 2 },
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": false,
  "lineBreakBeforeEachArgument": false,
  "lineBreakBeforeEachGenericRequirement": false,
  "lineBreakBeforeControlFlowKeywords": false
}
```

These settings favor compact signatures where they fit and retain at most one blank line. Developers still establish logical paragraphs and named assembly boundaries. [swift-format configuration](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md)

On an Apple toolchain that provides `swift format`, run from the app root:

```sh
swift format format --configuration macos/.swift-format --in-place --recursive macos/Runner macos/RunnerTests
swift format lint --configuration macos/.swift-format --strict --recursive macos/Runner macos/RunnerTests
```

Pin and verify a compatible formatter on the Apple build environment before automated enforcement. A newer formatter executable can be separate from Runner's Swift language mode. Scope it to handwritten Swift; generated registrants, Pods, native C and vendored packages remain outside this pass. C formatting requires an explicit C-aware configuration and file list rather than silently inheriting Windows pointer conventions. [Official swift-format usage](https://github.com/swiftlang/swift-format)

## Adoption and verification

Apply the refactor in coherent responsibility groups:

1. Extract the directory adapter/service and explicit engine binding while preserving startup order and replies.
2. Move Bootstrap owners and align Xcode/XIB references without changing class identities or window/menu behavior.
3. Separate the native audio facade, queue resource and device capability while preserving ABI and synchronization.
4. Relocate the build script with aligned invocation and paths; keep build correctness changes separately reviewable.
5. Apply Swift/C layout within the affected owners and add useful boundary coverage.

The [Apple source contracts](../test/requirements/platform_apple_contract_test.dart) and [Dart directory tests](../test/platform/desktop_directory_service_test.dart) anchor existing behavior. Update their source paths when moving owners, retaining coverage of exports, directory replies and audio accounting. Add injected channel/service checks, pure value checks and tests of failure, cleanup and stale-completion rules where a meaningful seam exists. In-memory doubles should not open Finder, create a server or require audio hardware.

The current [RunnerTests](../macos/RunnerTests/RunnerTests.swift) contains a placeholder test, and its Xcode target is app-hosted. Ordinary `xcodebuild test` launches Runner. During agent work, use compilation/build-for-testing and genuinely unhosted headless checks; leave hosted execution, rendered-window checks, Finder opening and real audio/device tests to the user under the no-application-launch instruction.

On a compatible configured Mac, compilation can use the existing CocoaPods workspace without launching the app:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug build
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug build-for-testing
```

Check Profile and Release builds, exported symbols, target membership, static archive integration and entitlements as appropriate to the changes. Use a checkout with real package symlinks and resolved dependencies. Compilation, formatter execution and native checks require the Apple build environment; this Windows documentation pass establishes neither a successful macOS build nor native runtime coverage. No apps, servers or background services should be launched during agent work.
