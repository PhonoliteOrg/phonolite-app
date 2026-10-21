# Phonolite iOS and Swift specification

This extends the [expected architecture](expected-architecture.md) and [coding standards](coding-standards.md) to Phonolite's handwritten Apple host code. Flutter owns the phone's application UI and domain workflows. Swift supplies Apple capabilities and the native CarPlay presentation.

The responsibility boundaries and readability expectations carry over. The source map below describes the implemented organization of the handwritten iOS host. The refactor preserves channel contracts, supported Flutter lifecycle registration, Swift language mode and SDK settings. Apple SDK compilation and native XCTest execution remain pending; the implementation has been reviewed from this Windows workspace.

Two Swift preferences are confirmed: use Swift-style type/file names and PascalCase responsibility folders; keep ordinary implementation on its owning type, using focused extensions mainly for protocol conformance. Other defaults below adapt the established Flutter preferences and can be refined through examples.

The [macOS native specification](macos-native-specification.md) carries these Swift preferences into the AppKit host with its own window, audio and build contracts.

## 1. Carry over the same organizing principle

**A shared owner defines common structure, design or behavior. Specializations supply meaningful differences. Assembly connects those pieces through explicit inputs and capabilities.** Apply this to native UI, message handling, state transitions, platform services and resource lifetimes.

Keep data definitions in one data silo. Keep native page assembly separate from reusable presentation. Give functionality a controller or capability owner. Keep framework entry points small and make their dependencies visible. Independent components get their own types and files; a larger collection of extensions on one delegate does not establish separate ownership.

Native functionality should support the existing Dart application. A CarPlay action requests playback through the existing Flutter boundary; it does not independently implement queue selection, likes, authentication or library filtering. A native controller may still own the loading state, cancellation and selection coordination needed by its native view.

## 2. Implemented owners and the rationale

The former delegate extensions combined entry points, channels, functional state, presentation and native resources. The current owners separate those responsibilities while sharing the common mechanisms:

| Responsibility | Current owners | Why it lives there |
| --- | --- | --- |
| Application, scene and engine composition | [AppDelegate](../ios/Runner/Bootstrap/AppDelegate.swift), [SceneDelegate](../ios/Runner/Bootstrap/SceneDelegate.swift), [CarPlaySceneDelegate](../ios/Runner/Bootstrap/CarPlaySceneDelegate.swift), [NativeHost](../ios/Runner/Bootstrap/NativeHost.swift), [FlutterEngineBinding](../ios/Runner/Bootstrap/FlutterEngineBinding.swift) | Framework entry points forward lifecycle events; the host wires capabilities and the current scene without spreading AppDelegate lookups through feature code |
| Shared Flutter transport | [FlutterChannelAdapter](../ios/Runner/Infrastructure/Flutter/FlutterChannelAdapter.swift) and the Now Playing, CarPlay and permission adapters beside it | Registration, invocation and released-owner replies share one mechanism; each channel family keeps its own methods, decoding and callbacks |
| Native browse functionality | [CarPlayBrowseController](../ios/Runner/Application/Controllers/CarPlay/CarPlayBrowseController.swift), [CarPlayClient](../ios/Runner/Infrastructure/Flutter/CarPlayClient.swift) and [CarPlayCodec](../ios/Runner/Infrastructure/Flutter/CarPlayCodec.swift) | The controller owns typed request state and stale-result rejection; transport owns wire values, while Dart retains library and playback business rules |
| CarPlay assembly and design | [CarPlayNavigationCoordinator](../ios/Runner/Pages/CarPlay/CarPlayNavigationCoordinator.swift), concrete pages, [CarPlayBrowsePage](../ios/Runner/Pages/CarPlay/CarPlayBrowsePage.swift), [CarPlayListFrame](../ios/Runner/UI/Structures/CarPlay/CarPlayListFrame.swift) and [CarPlayShell](../ios/Runner/UI/Shell/CarPlay/CarPlayShell.swift) | Pages select content/actions; the common page sequence, list design and scene navigation have shared owners |
| Playback data and system publication | [NowPlayingUpdate](../ios/Runner/Data/Models/Playback/NowPlayingUpdate.swift), [NowPlayingState](../ios/Runner/Data/Models/Playback/NowPlayingState.swift), [NowPlayingCodec](../ios/Runner/Infrastructure/Flutter/NowPlayingCodec.swift), [NowPlayingCoordinator](../ios/Runner/Infrastructure/Media/NowPlayingCoordinator.swift), [NowPlayingInfoPublisher](../ios/Runner/Infrastructure/Media/NowPlayingInfoPublisher.swift) | Values own metadata and position acceptance; the boundary decodes once; infrastructure coordinates native media and publishes to MediaPlayer |
| Artwork identity, resources and security | [ArtworkSource](../ios/Runner/Data/Models/Playback/ArtworkSource.swift), [NowPlayingArtworkController](../ios/Runner/Infrastructure/Artwork/NowPlayingArtworkController.swift), its loader/decoder/cache collaborators and [PinnedArtworkSession](../ios/Runner/Infrastructure/Security/PinnedArtworkSession.swift) | Shared identity is data; images, requests, bounded caches and pinned sessions remain with resource owners |
| Permission values, persistence and capabilities | [LocalNetworkPermissionStatus](../ios/Runner/Data/Models/Permissions/LocalNetworkPermissionStatus.swift), [LocalNetworkPermissionStore](../ios/Runner/Data/Storage/Permissions/LocalNetworkPermissionStore.swift), [LocalNetworkPermissionService](../ios/Runner/Infrastructure/Permissions/LocalNetworkPermissionService.swift), [LocalNetworkPermissionProbe](../ios/Runner/Infrastructure/Permissions/LocalNetworkPermissionProbe.swift), [ApplicationSettingsService](../ios/Runner/Infrastructure/Settings/ApplicationSettingsService.swift) | Saved data, Network probing, Settings access and Flutter messages have distinct owners |
| Audio session, remote commands and native ABI | [AudioSessionService](../ios/Runner/Infrastructure/Audio/AudioSessionService.swift), [RemoteCommandService](../ios/Runner/Infrastructure/Media/RemoteCommandService.swift), [phonolite_audio.m](../ios/Runner/Infrastructure/Audio/Native/phonolite_audio.m), [phonolite_opus_link.m](../ios/Runner/Infrastructure/Linking/phonolite_opus_link.m) | Apple session/command integration stays outside delegates; C/Objective-C audio handles, callbacks and exported FFI symbols retain their existing implementation and linking responsibilities |

These are concrete examples of the shared-owner rule. Adding a page or channel should reuse the established assembly or transport mechanism. Add a new owner when responsibility or lifetime differs, rather than duplicating the sequence or extending an unrelated delegate.

## 3. Framework constraints and project choices

| Concern | Constraint to preserve | Organization we can choose |
| --- | --- | --- |
| Flutter hosting | Use lifecycle/registration APIs supported by the selected Flutter engine and preserve required superclass forwarding | Delegates can compose ordinary Swift owners in responsibility folders |
| UIKit and CarPlay scenes | Scene classes, roles, storyboards and lifecycle callbacks must remain correctly registered | Functional operations and template assembly can live outside the delegate |
| Channels | A channel is attached to a specific binary messenger and has a codec/method contract | Each channel family can have a narrow adapter and typed values |
| Swift imports | Imports identify modules, not source-file paths; accessible declarations in the same module need no per-file import | Start with responsibility folders inside the existing Runner module |
| Xcode membership | This project's file references and source build phases explicitly register compiled files | Physical directories can match the conceptual tree after project references are updated |
| Native packages | Podspec source lists, linker retention and C ABI names affect the binary | Reusable plugin capabilities can remain in their owning package |

Swift's module model is different from Dart's library URI model. Write `import Flutter`, `import Foundation` or `import CarPlay` where used. A folder such as `Data/Models` does not create an importable module. Organize inside Runner first; introduce another framework/package target when reuse or a compiler-enforced boundary justifies it. [Swift import declarations](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/ReferenceManual/Declarations.md#import-declaration)

The current [Xcode project](../ios/Runner.xcodeproj/project.pbxproj) uses explicit groups/file references. Moving a file requires checking its target membership and build path, not just its filesystem location. Keep configured plist, entitlement, bridging-header and storyboard paths aligned. [Xcode file organization](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project)

At this review, the workspace's Flutter installation is 3.35.6 and Runner specifies Swift language mode 5.0. Runner's target configurations specify iOS 16.6; the Podfile/project defaults include 15.0. These are distinct settings. Swift language mode does not identify the installed compiler. Record the actual macOS build toolchain before changing lifecycle or concurrency configuration.

Availability checks should cover APIs newer than Runner's supported minimum. Omit branches for older versions already guaranteed by the target; the host and CarPlay use their supported scene/template APIs directly. Retain required framework callback selectors and newer feature checks, including the dynamic iOS 27 MiniPlayer setter.

Current Flutter documentation describes newer UIScene registration, including `FlutterImplicitEngineDelegate` and its engine-initialization callback. The installed 3.35.6 engine includes `FlutterSceneDelegate` but does not expose that newer callback. Preserve the supported registration sequence during an organization refactor; plan an engine/lifecycle migration separately against the chosen SDK. [Flutter UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)

## 4. Current source map

Physical folders and Xcode groups follow the same responsibility names inside the existing Runner module. This map includes the handwritten owners; generated resources and build output keep their tool ownership.

```text
ios/
  .swift-format
  Scripts/
    build_opus_static.sh
  Runner/
    Bootstrap/
      AppDelegate.swift
      SceneDelegate.swift
      CarPlaySceneDelegate.swift
      NativeHost.swift
      FlutterEngineBinding.swift
    Data/
      Models/
        Playback/
          NowPlayingUpdate.swift
          NowPlayingState.swift
          NativeRemoteCommand.swift
          ArtworkSource.swift
          ArtworkCacheKey.swift
          ArtworkSessionIdentity.swift
        CarPlay/
          CarPlayScope.swift
          CarPlayItem.swift
          CarPlaySourceState.swift
          CarPlayListRequest.swift
          CarPlayListResult.swift
          CarPlayCommand.swift
        Permissions/
          LocalNetworkPermissionStatus.swift
      Storage/
        Permissions/LocalNetworkPermissionStore.swift
        Offline/OfflineBackupExclusions.swift
    Application/
      Controllers/
        CarPlay/CarPlayBrowseController.swift
    Infrastructure/
      Flutter/
        FlutterChannelEndpoint.swift
        FlutterChannelAdapter.swift
        NowPlayingChannelAdapter.swift
        CarPlayChannelAdapter.swift
        PermissionsChannelAdapter.swift
        NowPlayingCodec.swift
        CarPlayCodec.swift
        CarPlayClient.swift
      Media/
        NowPlayingCoordinator.swift
        NowPlayingInfoPublisher.swift
        RemoteCommandService.swift
      Artwork/
        NowPlayingArtworkController.swift
        NativeArtworkLoader.swift
        NativeArtworkDecoder.swift
        NativeArtworkCache.swift
        CachedNowPlayingArtwork.swift
        CarPlayArtworkLoader.swift
      Security/PinnedArtworkSession.swift
      Audio/
        AudioSessionService.swift
        Native/phonolite_audio.h
        Native/phonolite_audio.m
      Linking/phonolite_opus_link.m
      Permissions/
        LocalNetworkPermissionService.swift
        LocalNetworkPermissionProbe.swift
      Settings/ApplicationSettingsService.swift
    Pages/
      CarPlay/
        CarPlayRootPage.swift
        CarPlayBrowsePage.swift
        CarPlayArtistsPage.swift
        CarPlayAlbumsPage.swift
        CarPlayPlaylistsPage.swift
        CarPlayNavigationCoordinator.swift
    UI/
      Shell/CarPlay/CarPlayShell.swift
      Structures/CarPlay/
        CarPlayListFrame.swift
        CarPlaySourceGrid.swift
        CarPlayNowPlayingPresenter.swift
      Shared/CarPlay/CarPlayIconProvider.swift
    Assets.xcassets/
    Base.lproj/
    Info.plist
    Runner.entitlements
    RunnerDebug.entitlements
    Runner-Bridging-Header.h
    GeneratedPluginRegistrant.h
    GeneratedPluginRegistrant.m
  RunnerTests/
    RunnerTests.swift
    NowPlayingContractTests.swift
    CarPlayContractTests.swift
  Flutter/                       # Flutter build configuration/generated output
  Runner.xcodeproj/
  Runner.xcworkspace/
  Podfile
```

The delegates now live in Bootstrap; UIKit registration continues to name their existing classes and module. Keep generated registrants, Flutter ephemeral output, Pods, vendored sources and generated link support under their tool/package ownership. Do not hand-edit generated registration to maintain the tree.

The handwritten [Opus build script](../ios/Scripts/build_opus_static.sh) lives under Scripts. Runner's existing Build Opus Static phase invokes the new path; its ordering, outputs and the script's root/output behavior are preserved. Native audio code lives under Infrastructure/Audio/Native and symbol retention under Infrastructure/Linking. Generated Opus output remains build output rather than a handwritten architecture owner. The separate macOS build script and its integration are unchanged. The [bridging header](../ios/Runner/Runner-Bridging-Header.h) remains at its configured Runner path.

### Responsibility and dependency boundaries

| Area | Owns | Boundary |
| --- | --- | --- |
| Bootstrap | Construction, app/engine/scene bindings and framework entry points | Wires the other areas; deep code does not locate dependencies through AppDelegate |
| Data | Native value contracts, their natural operations and data storage | No Flutter channels, concrete pages or presentation assembly |
| Application | Native-facing controllers and functional coordination needed by native views | Uses typed data and narrow capabilities; does not build UIKit/CarPlay objects or duplicate Dart business rules |
| Infrastructure | Flutter transport, Apple capabilities, networking, decoding and native resources | Receives typed values/callbacks; no concrete Application-controller dependencies or concrete page selection |
| Pages | Final native page assembly and concrete destinations | Binds controllers to shared UI and constructs the native destination |
| UI | Reusable presentation, template structures, symbols and navigation surfaces | Receives values/actions; common frames do not own feature algorithms or channel parsing |

Although these folders share the Runner Swift module, maintain the conceptual dependencies in constructors and method signatures. A controller can receive a typed browsing capability implemented by the Flutter adapter. An incoming channel adapter can receive a typed callback assembled by Bootstrap. Neither needs a concrete page or a global application lookup.

Classify technical media orchestration as Infrastructure; create an Application controller when there is native-facing functional state or policy to own. The existence of Application does not require a Swift copy of every Dart controller. Keep framework image objects and template resources with their infrastructure/presentation owners; shared data models can carry image identifiers and source values.

Two representative flows are:

```text
CarPlay selection
  → page callback → native controller → typed Flutter adapter
  → existing Dart application operation

Dart now-playing update
  → channel codec → typed native update → media coordinator
  → system publisher + scene presentation input
```

## 5. Shared native UI assembly

The CarPlay counterpart of BasePage is a shared template frame and assembly contract. Apple's templates supply the platform presentation; shared project code supplies consistent loading/empty/error states, row construction, titles, symbols and action binding within that API. Concrete pages select their data and actions. [Apple CarPlay templates](https://developer.apple.com/documentation/carplay/cplisttemplate)

The implemented [CarPlayListFrame](../ios/Runner/UI/Structures/CarPlay/CarPlayListFrame.swift) owns loading/empty/error rows, row enablement, artwork binding and selection completion. [CarPlayBrowsePage](../ios/Runner/Pages/CarPlay/CarPlayBrowsePage.swift) owns the common sequence: create the loading template, present it, request typed results, then update that same template. Concrete artist/album/playlist pages supply request values, messages and selection actions.

For example, [CarPlayArtistsPage](../ios/Runner/Pages/CarPlay/CarPlayArtistsPage.swift) assembles the family with this pattern:

```swift
let frame = CarPlayListFrame(
  loadingMessage: "Loading artists...",
  emptyMessage: scope == .local ? "No downloaded artists" : "No artists found",
  errorMessage: scope == .local ? "No downloaded artists" : "Connect to a server",
  loadArtwork: loadArtwork
)
let page = CarPlayBrowsePage(
  controller: controller,
  request: .artists(scope: scope),
  frame: frame,
  onSelect: onSelect
)

page.show(present: present)
```

Create the loading template once, then update that same template as results arrive. Preserve its identity and navigation position. [CarPlayBrowseController](../ios/Runner/Application/Controllers/CarPlay/CarPlayBrowseController.swift) owns independent request identities and invalidates pending presentation callbacks on disconnect. The frame supplies common design without owning the request policy. [CarPlaySourceGrid](../ios/Runner/UI/Structures/CarPlay/CarPlaySourceGrid.swift) supplies consistent source actions and symbols, and [CarPlayNowPlayingPresenter](../ios/Runner/UI/Structures/CarPlay/CarPlayNowPlayingPresenter.swift) owns the system Now Playing template's custom like action.

[CarPlayShell](../ios/Runner/UI/Shell/CarPlay/CarPlayShell.swift) owns root/push presentation and scene template resources. [CarPlayNavigationCoordinator](../ios/Runner/Pages/CarPlay/CarPlayNavigationCoordinator.swift) selects concrete destinations and binds their supplied capabilities. Bootstrap constructs the artwork loader and adapts it to the shared frame's loading callback; pages and shared UI receive that callback without constructing the infrastructure implementation. Keep page actions distinct from the scene's app navigation, as in the Flutter shell.

Use composition when the common responsibility can be supplied as typed inputs, a renderer or a collaborator. Use a base class when a real superclass-owned lifecycle/assembly sequence needs specialization. Swift has no direct equivalent of Dart's abstract class syntax; prefer protocols and composed implementations over required hooks whose default is `fatalError`. A shared protocol alone does not share implementation.

Build named UI pieces before final assembly. Extract a repeated row, loading state, symbol treatment or action group into its owning structure. Keep substantial actions outside anonymous layout closures. Do not flatten everything into one expression or introduce a wrapper for every obvious constructor call.

The unpopulated `nowPlayingItem` path and empty visibility hook were removed during extraction. The active system Now Playing template and custom like action remain the presentation contract; do not restore obsolete hooks merely to complete an imagined hierarchy.

## 6. Swift files, types and member order

Use `UpperCamelCase.swift` filenames matching the primary type, such as `AudioSessionService.swift`. Use PascalCase responsibility directories. Preserve framework-required names and the established C/Objective-C ABI names at their boundary.

Order files as imports, tightly related contract declarations, primary type, then any focused conformance extensions or small private helpers. Alphabetize imports, keeping Apple/standard modules and Flutter/other dependencies in clear groups. Each file imports the frameworks it directly uses. Keep one primary responsibility per file; closely coupled private helpers may remain beside it.

Within a type, use the established reading order:

1. Static constants and shared immutable definitions.
2. Immutable inputs, dependencies and callbacks.
3. Private state and owned resources.
4. Initializers.
5. Observable properties and deliberate setters.
6. Lifecycle, attachment, detachment and shutdown operations, including `deinit` where applicable.
7. Public operations and explicit specialization contracts.
8. Private operations and named presentation pieces.
9. Final view/template/host assembly, when the type has that role.

Keep a data type's equality/hash/description operations together near its end when provided. Preserve initializer evaluation, superclass initialization and callback scheduling when reordering. A file approaching the Dart guide's 1,000-line review boundary should already have had its responsibilities inspected; that boundary is not a desirable file size or a newly installed Swift check.

### Naming and visible contracts

Use `lowerCamelCase` members and meaningful Swift argument labels: `loadArtists(scope:)`, `publish(snapshot:)`, `connect(to:)`. Familiar Swift initialisms such as `artworkURL` and `albumID` are appropriate; existing wire keys such as `albumId` keep their exact spelling. Use booleans such as `isPlaying`, `hasSource` and `canLoadMore`.

Use explicit parameter/return types and typed callback aliases where they name a recurring contract. Infer obvious local values and prefer `let` unless a binding changes. Prefer named concepts over multi-field tuples reused across files; tuples remain useful for small local results. Readability at call sites takes priority over shortening declarations. [Swift API design guidelines](https://www.swift.org/documentation/api-design-guidelines/)

### Encapsulation and extensions

Use `private` for implementation state, `private(set)` for intentionally observable state with owner-controlled writes, and the default `internal` access for collaboration within Runner. Add `public` or `open` only for an actual module boundary and supported external extension contract. Swift has no `protected` access level. [Swift access control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/)

Keep ordinary behavior on the type the project owns. Focused extensions may group protocol conformance or provide a useful convenience on an external type. Prefer same-file conformance extensions where private implementation access is needed. Extensions cannot add stored properties; `private` reaches same-file extensions, while `fileprivate` also ends at the file boundary. Splitting into `AppDelegate+Feature.swift` does not provide Dart-style shared library privacy. Extract a composed owner instead of widening mutable state simply to split a file. [Swift extensions](https://docs.swift.org/latest/documentation/the-swift-programming-language/extensions/), [access boundaries](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/)

Keep superclass lifecycle overrides in the primary class declaration. Use `@objc`, `NSObject` inheritance and selectors where the actual framework contract needs them. Mark concrete owners `final` when subclassing is not an intended contract; retain extensibility where a shared family or framework requires it.

For example, this complete language-level pattern keeps the state on its owner and the callback contract together:

```swift
protocol SceneConnectionHandling: AnyObject {
  func sceneDidConnect()
  func sceneDidDisconnect()
}

final class SceneConnectionOwner {
  private(set) var isConnected = false

  private func connect() {
    isConnected = true
  }

  private func disconnect() {
    isConnected = false
  }
}

extension SceneConnectionOwner: SceneConnectionHandling {
  func sceneDidConnect() {
    connect()
  }

  func sceneDidDisconnect() {
    disconnect()
  }
}
```

An Apple delegate applies the same organization while implementing the exact required callback signatures. Give stateful resource owners explicit initializers; a stateless value structure can use its memberwise initializer when that makes the contract clear.

### Data, mutation and equality

Prefer structs/enums for values and classes for identities, framework delegates and resource owners. Store shared native values under Data. Keep small calculations, copying and validation with their natural data owner; put substantial persistence in a focused store there.

Swift value copying often supplies the desired update operation directly:

```swift
struct TrackMetadata {
  let id: String
  var albumID: String?

  func removingAlbum() -> TrackMetadata {
    var updated = self
    updated.albumID = nil

    return updated
  }
}
```

For a reusable patch API, explicitly represent unchanged, cleared and replaced values rather than making an ordinary optional argument carry all three meanings. Preserve each existing channel field's actual missing/null behavior at decoding. Use `Equatable`/`Hashable` when content equality belongs to that value; define entity identity comparisons explicitly and retain reference identity for services/controllers. Structs containing reference objects are not automatically deeply immutable or safe to pass between isolation domains.

Ordinary property setters remain valid for deliberate local changes. Use named commands for operations that coordinate state, can fail or await work. A fluent builder is optional where construction has a genuine shared configuration responsibility; retain the user's one-configuration-call-per-line preference and individual setters. Avoid builder layers around every initializer.

## 7. Logical spacing and readable operations

Use two-space indentation and a 120-column formatting target. Keep one blank line between members and between logical paragraphs inside methods: input preparation, guards, request execution, state changes, notifications and the final result. Keep related assignments together. Attach `else`, `catch` and related clauses to their own construct.

Prefer early `guard` exits to deep nesting. Separate independent guards and put a blank line before a final return after earlier work. Keep the return directly inside a simple guard. For example:

```swift
import Foundation

func trackLabel(title rawTitle: String, artist rawArtist: String?) -> String {
  let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  let artist = rawArtist?.trimmingCharacters(in: .whitespacesAndNewlines)

  guard !title.isEmpty else {
    return "Untitled"
  }

  guard let artist = artist, !artist.isEmpty else {
    return title
  }

  return "\(artist) / \(title)"
}
```

Use explicit returns in multi-step operations. A short single-expression computed property or operation may use Swift's concise form when its intent remains obvious. Use collection transforms for clear value transformations and loops for branching, mutation or ordered work. Avoid nested ternaries, unnecessary force unwraps/casts and `try!`; describe recovery with typed errors or intentional fallbacks. Preserve exhaustive handling of owned enums and meaningful `@unknown default` handling for evolving framework enums.

Use `///` for contracts whose units, ownership, errors, completion or callback obligations need explanation. Explain consequential decisions without narrating syntax or adding large comment banners. Keep supporting documentation in `docs`, not README files scattered through native responsibility directories.

## 8. Flutter boundary contracts

Channel adapters own method/channel names, `Any` dictionaries, Flutter codec values, `FlutterResult`, error envelopes and unknown-method handling. Decode once into named values and delegate. Domain/native controllers operate on typed contracts. Generated Pigeon APIs are a possible later transport choice; adopting them is a contract migration rather than a prerequisite for readable native organization. [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)

Preserve the current integration behavior when extracting:

- Channel names `phonolite/now_playing`, `phonolite/carplay` and `phonolite/permissions`, channel method names, command discriminator values such as `prev`, and existing error/unknown-method behavior.
- Numeric units, payload defaults, file-URL encoding, malformed-item handling and permission status keys.
- Exactly one result per incoming method call and exactly one required completion per CarPlay selection, including errors, cancellation and a released owner.
- Completion meaning: accepting metadata does not wait for artwork; requesting permission does not mean permission was granted; accepting a Settings-opening request does not mean a setting changed.
- Current Now Playing updates are a mixed patch contract. Missing title/position fields can retain state; artwork source/identity/credential absence can clear or reset artwork. A new strict full-snapshot decoder would change behavior.
- Artwork identity, credentials and pins, epoch/seek position rules, bounded caching, invalidation of pending requests and intentional retry on a later update.

Keep the existing [Dart native value models](../lib/data/models/playback/native_now_playing_snapshot.dart) and [native codecs](../lib/infrastructure/platform/media/now_playing_codec.dart) aligned with their Swift counterparts. A typed Swift wrapper does not imply a change to the wire format. Preserve the authenticated pin supplied by the existing trust owner; the native artwork adapter enforces that decision without becoming another source of trust policy.

## 9. Lifetimes, queues and Swift concurrency

| Lifetime | Owns | Ends when |
| --- | --- | --- |
| Application/native host | Process-wide native services and media state/cache | The owning host shuts down |
| Flutter engine binding | Channels, messenger references and registration state for that engine | That binding detaches or its engine is replaced |
| CarPlay scene/session | Interface controller, templates, navigation and scene requests | The scene disconnects |
| Request | Task/listener, cancellation, generation and completion | It completes, is cancelled or loses relevance |
| Native audio handle | Buffers, callbacks and native release | Its explicit close/release protocol completes |

CarPlay disconnection clears scene presentation and invalidates its pending work. It does not stop app-owned playback or discard app-owned Now Playing metadata/cache. Channel attachment is idempotent for one binding; a changed messenger requires deliberate detachment/rebinding. Pass dependencies at scene/engine assembly rather than searching all windows or repeatedly reaching through `UIApplication.shared.delegate` from feature code.

Give each mutable owner one documented isolation domain. UIKit/CarPlay presentation and outgoing Flutter method invocation use the platform main thread. Flutter can configure incoming handlers on a background task queue; result callbacks have their own contract and the installed API permits replies from any thread. Do not treat that permission as permission to mutate UI off the main thread. [Flutter threading](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading), [versioned FlutterResult contract](https://github.com/flutter/flutter/blob/3.35.6/engine/src/flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h)

Prefer explicit `@MainActor` ownership for compatible UI-facing types in a deliberate concurrency migration. Retain supported serial-queue boundaries while organizing existing callback code. Other mutable resources can use an actor or a serial queue according to their execution contract. Do not add `Task` blocks to every callback or require Swift 6 language mode merely to reorganize source. [Swift migration guidance](https://www.swift.org/migration/)

An `await` permits other work to change actor-owned state. Retain request-generation, scene-identity and cancellation checks after suspension; actor isolation alone does not establish request relevance. Keep background file reads and image decoding outside presentation mutation. Do not transfer framework resources between actors by adding unchecked sendability just to silence diagnostics. [Actor reentrancy](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md)

The creator owns cleanup unless ownership is transferred. Release notification observers, remote-command registrations, request tasks, network listeners and channel handlers at the appropriate boundary. Use weak captures for real ownership cycles or intentionally borrowed owners; handle the released-owner path when a callback still owes completion. Use `defer` for synchronous scope cleanup and an explicit awaitable stop operation when shutdown needs asynchronous work; `deinit` cannot supply an awaited shutdown protocol.

Keep timing-sensitive native audio execution separate from ordinary Swift orchestration. Do not add main-actor hops, channels or general task scheduling to the audio callback path as part of organization. Preserve C ABI symbols, buffer ownership, generation counters, error reporting and linking. AudioQueue completion callbacks and Audio Unit realtime render blocks have different contracts; assess the actual API before applying realtime restrictions or replacing the existing C/Objective-C implementation. [Apple realtime render guidance](https://developer.apple.com/documentation/AVFAudio/building-a-signal-generator)

## 10. Formatter configuration

The project now includes [ios/.swift-format](../ios/.swift-format) with the following configuration. Use the Swift project's `swift-format` tool with a pinned compatible version. Tool availability is separate from the app's Swift language mode; this Windows workspace has neither executed the formatter nor established a toolchain/version pin.

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

These settings support compact signatures and limit repeated blank lines. The formatter does not discover logical paragraphs or establish responsibility boundaries. Check fluent-builder layout against the pinned formatter before adopting a narrow documented exception. [Formatter configuration](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md)

On a compatible macOS toolchain, commands from the app root are:

```sh
swift format format --in-place --recursive ios/Runner ios/RunnerTests
swift format lint --strict --recursive ios/Runner ios/RunnerTests
```

Scope formatting to handwritten Swift. Keep generated/vendored output and native C/Objective-C out of a Swift formatting pass. Validate and pin the compatible formatter on the Apple build environment before the first automated formatting/lint pass; source layout here was reviewed manually. [Official swift-format usage](https://github.com/swiftlang/swift-format)

## 11. Implemented choices and future changes

The extraction uses one process-level NativeHost, one existing engine binding and scene-scoped CarPlay coordinators. Flutter lifecycle registration, callback APIs, Swift 5.0 language mode and deployment settings were preserved. No `@MainActor`/actor conversion, Swift 6 migration or implicit-engine lifecycle upgrade is part of this organization change.

The current choices provide these extension rules:

- **Browse functionality.** One CarPlayBrowseController owns the shared typed request/relevance policy. The common CarPlayBrowsePage and list frame implement shared sequencing/design. Add specialized controllers when functional policy diverges; different page labels alone do not justify duplicating request logic.
- **Runner versus packages.** App-specific CarPlay composition remains in Runner. Extract a framework/package only when actual additional consumers and a stable capability/lifetime contract justify a module boundary.
- **Artwork ownership.** NowPlayingArtworkController owns its request generation, bounded cache and current native artwork. NativeArtworkLoader owns its request and created sessions; an injected URLSession stays borrowed. CarPlayArtworkLoader retains its independent per-request session and decode behavior. Both use PinnedArtworkSession for equivalent security policy; sharing that mechanism does not merge caches, cancellation slots or different decode timing.
- **Media presentation.** NowPlayingCodec decodes the existing mixed patch contract into NowPlayingUpdate. NowPlayingState owns position acceptance, and NowPlayingInfoPublisher owns MediaPlayer publication. The coordinator emits typed presentation state through a callback wired by NativeHost, rather than reaching into a concrete scene delegate.
- **Channels.** FlutterChannelAdapter shares registration and invocation mechanics. Family adapters keep method names, argument/result envelopes and typed callbacks. FlutterEngineBinding retains the existing attach-once behavior; supporting engine replacement requires an explicit detach/rebind design and verification.
- **Callbacks and concurrency.** Existing callback/queue boundaries remain in place. A later `async throws` or isolation migration must preserve required Apple/Flutter completions, cancellation and request relevance after suspension.

Refine future variations with concrete examples and tests before broad changes. Keep shared code responsible for meaningful common structure or behavior; avoid introducing protocols, builders or base classes without a real shared contract.

## 12. Verification and adoption

The [RunnerTests](../ios/RunnerTests/RunnerTests.swift) retain all twelve original artwork/metadata cases, including authenticated request identity, downsampling, failed responses, stale artwork, seek epochs and clearing. Added cases cover borrowed-session reuse after clearing, typed presentation callbacks and the mixed metadata/artwork patch contract. [NowPlayingContractTests](../ios/RunnerTests/NowPlayingContractTests.swift) cover pure decoding/state/identity rules, and [CarPlayContractTests](../ios/RunnerTests/CarPlayContractTests.swift) cover typed browse transport and request relevance with injected clients. In-memory URLProtocol doubles do not require an HTTP listener.

The [Dart Apple source contracts](../test/requirements/platform_apple_contract_test.dart) and [iOS architecture checks](../test/architecture/ios_architecture_test.dart) verify native ownership, paths, source registration and important contract details. A passing source-text check does not establish Swift compilation or runtime behavior.

Xcode references, source target membership, build-script/native paths, plist/entitlement/resource references, generated registration and exported FFI symbols must remain aligned with this map. The handwritten source organization is implemented, but the Windows workspace has no Swift/Xcode executable: Apple SDK compilation, formatter execution and native XCTest execution remain pending on a compatible Apple build environment. Link/source checks and manual review cannot substitute for that build. Add focused coverage for new channel replies, scene lifecycle or permission replacement behavior when those contracts change.

Do not launch apps, simulators, servers or background services during agent work. Static analysis and compilation are allowed. Native tests that require launching an app/simulator must be left for an explicitly authorized environment/workflow. Keep this supplement linked with the shared architecture and Dart standard rather than adding README files to each native directory.
