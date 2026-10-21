# Phonolite Android native specification

This extends the [expected architecture](expected-architecture.md) and [coding standards](coding-standards.md) to the Flutter Android host. The [iOS Swift](ios-swift-specification.md), [macOS native](macos-native-specification.md) and [Windows C++](windows-native-specification.md) specifications apply the same principles to their platforms. Android keeps its source sets, package names, resources and component lifecycle while adopting the same responsibility boundaries and readable assembly.

**Shared abstractions define common structure, design and behavior. Specialized components supply meaningful differences. Assembly connects them through explicit dependencies.** This applies to Kotlin functionality, system presentation, channel transport, audio resources and data operations. Consistency comes from shared owners rather than repeated implementations.

Use conventional lowercase Kotlin package folders, PascalCase type/file names and lowerCamelCase members. Keep the established two-space indentation, 120-column target, logical spacing, controlled mutation and ordinary methods on owned types. The handwritten Android host now uses this organization. The functional assessment below identifies the explicit corrections made alongside extraction and the remaining platform differences.

## Current source responsibilities

Flutter owns the phone's application pages, navigation, library state and playback workflows. Android supplies a process-owned Flutter engine, AudioTrack output, media-session/notification integration and Android Auto browsing.

| Current source | Responsibilities | Expected owners |
| --- | --- | --- |
| [MainActivity](../android/app/src/main/kotlin/com/example/phonolite_app/bootstrap/MainActivity.kt) | FlutterActivity presentation, borrowing the shared engine and keeping it alive after Activity destruction | Bootstrap |
| [PhonoliteApplication](../android/app/src/main/kotlin/com/example/phonolite_app/bootstrap/PhonoliteApplication.kt), [NativeHost](../android/app/src/main/kotlin/com/example/phonolite_app/bootstrap/NativeHost.kt), [FlutterEngineOwner](../android/app/src/main/kotlin/com/example/phonolite_app/bootstrap/FlutterEngineOwner.kt) and [binding](../android/app/src/main/kotlin/com/example/phonolite_app/bootstrap/FlutterEngineBinding.kt) | Loader initialization, process composition, one shared engine, plugin registration, channel assembly and Dart startup | Bootstrap |
| [Shared channel adapter](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/flutter/FlutterChannelAdapter.kt), family adapters/codecs and [VehicleClient](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/flutter/VehicleClient.kt) | Registration, platform-thread invocation, wire decoding/replies and typed native/Dart transport | Infrastructure/Flutter |
| [NativeMediaController](../android/app/src/main/kotlin/com/example/phonolite_app/application/controllers/media/NativeMediaController.kt), [position state](../android/app/src/main/kotlin/com/example/phonolite_app/data/models/playback/PlaybackPositionState.kt) and [VehicleBrowseController](../android/app/src/main/kotlin/com/example/phonolite_app/application/controllers/vehicle/VehicleBrowseController.kt) | Process snapshots/source availability, position acceptance, semantic browse nodes and selection | Application coordination and standalone Data values |
| [AudioOutputService](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/audio/AudioOutputService.kt), [session](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/audio/AudioOutputSession.kt), [focus controller](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/audio/AudioFocusController.kt), [device catalog](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/audio/OutputDeviceCatalog.kt) and [progress](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/audio/AudioPlaybackProgress.kt) | Registry, focus/noisy receiver, device enumeration, AudioTrack/writer ownership and progress accounting through an injected playback probe | Infrastructure/Audio; configuration/device values live in Data |
| [PhonoliteMediaService](../android/app/src/main/kotlin/com/example/phonolite_app/bootstrap/PhonoliteMediaService.kt), [service connection](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/media/MediaServiceConnection.kt) and [media-session controller](../android/app/src/main/kotlin/com/example/phonolite_app/infrastructure/media/MediaSessionController.kt) | Android callbacks, bound/started ownership, foreground policy, session publication and composed presentation | Bootstrap and Infrastructure/Media |
| [MediaItemFactory](../android/app/src/main/kotlin/com/example/phonolite_app/ui/media/MediaItemFactory.kt) and [PlaybackNotificationFactory](../android/app/src/main/kotlin/com/example/phonolite_app/ui/media/PlaybackNotificationFactory.kt) | Shared display labels/flags, media style, icons, action arrangements and final system-facing presentation assembly | UI/Media |
| [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml) and [automotive descriptor](../android/app/src/main/res/xml/automotive_app_desc.xml) | Framework component identities, permissions, launch configuration, media-service discovery and Android Auto registration | Android configuration/resources |
| [App Gradle build](../android/app/build.gradle.kts), [settings](../android/settings.gradle.kts) and native package builds | Dependencies, toolchain selection, source sets, native artifacts and APK output | Build configuration and owning packages |

The current media stack uses MediaBrowserServiceCompat, MediaSessionCompat and NotificationCompat.MediaStyle. It has no Compose screens, native content pages, ExoPlayer/Media3 implementation, Car App Library templates or separate Android Automotive OS application module. The historical `phonolite/carplay` channel also serves Android vehicle integration; keep that wire name.

Android Auto renders browsing and playback UI from the supplied media service/session. Phonolite owns the supplied content, actions and presentation metadata, rather than the final vehicle layout. [Android media apps for cars](https://developer.android.com/training/cars/media)

## Android structure and responsibility boundaries

Android's structure constrains discovery and lifetime more than the placement of ordinary Kotlin collaborators. Keep the existing app Gradle module and source roots. Responsibility folders become subpackages beneath `com.example.phonolite_app`.

| Area | Owns | Boundary |
| --- | --- | --- |
| `bootstrap` | Application/Activity/service entry points, dependency construction, engine startup and service binding | Connects other owners; feature code does not discover concrete entry points globally |
| `data/models` | Independent values, snapshots, configuration and outcomes with natural validation, copying and comparison | No Activity, Context, MediaSession, AudioTrack, messenger, worker or independently released resource |
| `data/storage` | Native persistence and focused data operations when actually needed | Stored values remain separate from platform access/lifecycle |
| `application/controllers` | Native functional state, request coordination, source availability, relevance and selection policy | Typed contracts; no channel dictionaries, AudioTrack calls or notification construction |
| `infrastructure/flutter` | Channels, codecs, transport replies and typed clients that call Dart | Decode once and delegate; preserve the wire contract |
| `infrastructure/audio` | Audio sessions, focus, routing, device enumeration, writer lifetime and native progress mechanisms | No Flutter codec parsing or library/queue-selection business rules |
| `infrastructure/media` | Session ownership, state publication, service start/stop, foreground policy and system registration | Presentation assembly arrives through explicit collaborators |
| `ui` | Shared native presentation, including notification design and browse-item display builders | Receives values/actions; no transport, service lifecycle or playback policy |
| `pages` | Assembly/controller binding for an actual app-owned native screen when one exists | Reuses common UI structures; Flutter pages stay in `lib/pages` |

Application here means the responsibility area; Android's framework Application subclass remains an entry point in Bootstrap. Android framework components initialize composed dependencies through their supported lifecycle callbacks. Give ordinary collaborators constructor-injected dependencies rather than adding custom constructors to manifest-created components.

Kotlin subpackages organize source but do not enforce module isolation. `internal` is module-wide, and Kotlin has no Java-style package-private visibility. Use private state, explicit imports and architecture review to preserve these boundaries. Introduce another Gradle module when a real reuse, build or compiler-enforced dependency need justifies it. [Kotlin visibility](https://kotlinlang.org/docs/visibility-modifiers.html)

## Expected source organization

Keep Android's required source sets and resource layout. This map shows the primary owners; small independent value contracts remain in their corresponding Data directories:

```text
android/
  .editorconfig
  settings.gradle.kts
  build.gradle.kts
  gradle.properties
  gradle/wrapper/
  app/
    build.gradle.kts
    src/
      main/
        AndroidManifest.xml
        kotlin/com/example/phonolite_app/
          bootstrap/
            MainActivity.kt
            PhonoliteApplication.kt
            PhonoliteMediaService.kt
            NativeHost.kt
            FlutterEngineOwner.kt
            FlutterEngineBinding.kt
          data/models/
            playback/
              NativeNowPlayingState.kt
              NativeRemoteCommand.kt
              PlaybackPositionState.kt
              SourceAvailability.kt
            vehicle/
              VehicleEntry.kt
              VehicleBrowseResult.kt
              VehicleBrowseNode.kt
              VehicleMediaIds.kt
            audio/
              OutputDevice.kt
          application/controllers/
            media/NativeMediaController.kt
            vehicle/VehicleBrowseController.kt
          infrastructure/
            flutter/
              FlutterChannelAdapter.kt
              FlutterChannelEndpoint.kt
              MethodChannelEndpoint.kt
              NowPlayingChannelAdapter.kt
              NowPlayingCodec.kt
              VehicleChannelAdapter.kt
              VehicleClient.kt
              VehicleCodec.kt
              AudioOutputChannelAdapter.kt
              AudioOutputCodec.kt
            audio/
              AudioOutputService.kt
              AudioOutputSession.kt
              AudioFocusController.kt
              OutputDeviceCatalog.kt
              AudioPlaybackProgress.kt
              AudioPlaybackProbe.kt
              AudioTrackPlaybackProbe.kt
            media/
              MediaSessionController.kt
              MediaServiceGateway.kt
              MediaServiceConnection.kt
              MediaServiceObserver.kt
              MediaServiceActions.kt
              MediaPendingIntents.kt
              PlaybackNotificationController.kt
              ArtworkDecoder.kt
              MediaMetadataFactory.kt
          ui/media/
            MediaItemFactory.kt
            PlaybackNotificationFactory.kt
        res/
          drawable*/
          mipmap*/
          values*/
          xml/automotive_app_desc.xml
      debug/AndroidManifest.xml
      profile/AndroidManifest.xml
      test/kotlin/com/example/phonolite_app/         # Headless JVM contract checks
      androidTest/kotlin/com/example/phonolite_app/  # Device tests when added
```

The root package and namespace stay intact. For example, moving MainActivity to the bootstrap package gives it the fully qualified name `com.example.phonolite_app.bootstrap.MainActivity`. Update the manifest's relative/FQCN reference and explicit Intent/class references together. The Gradle namespace/applicationId need not change. Resource imports still use the configured namespace, such as `com.example.phonolite_app.R`.

Standalone data definitions live outside transport/service owners. Keep raw MethodCall/Result and Any-based wire representations inside transport. VehicleClient exposes typed results and operations to functional code; the former BridgeInvokeResult envelope is no longer a general application contract. A small transport-only reply helper may stay private beside its adapter.

NativeHost composes the process's native capabilities and state. FlutterEngineOwner owns engine creation; FlutterEngineBinding connects adapters to that engine. The media service attaches its service-scoped session/presentation collaborators to those existing process capabilities. Independent owners receive narrow dependencies rather than a NativeHost service locator.

AudioPlaybackProgress owns progress accounting through AudioPlaybackProbe and an injected monotonic clock; AudioTrackPlaybackProbe owns Android observations. Purely mathematical/data rules can live with a Data value when appropriate. Queue chunks containing an active generation/ownership handoff belong beside the writer. An AudioTrack session is a resource owner even though it contains fields that look like data.

Create native `pages`, reusable view structures and storage owners when those responsibilities actually appear. A browsable Android Auto node is not an app-owned native screen. Keep generated registration, `build`, `.gradle`, `.cxx` and package artifacts under tool ownership. Keep source documentation in `docs`, without directory READMEs or broad Utils/Common collections.

## Shared structures and native presentation

Apply Katiby's shared-frame and named-assembly approach, the Dart BasePage/navbar family and the native families already defined in the other specifications. Share meaningful decisions at the appropriate level:

| Family | Shared owner defines | Specialized pieces supply |
| --- | --- | --- |
| Flutter transport | Registration, platform-thread invocation, detach behavior and completion mechanics | Channel names, typed payloads and feature replies |
| Native request coordination | Loading/relevance/error sequencing and completion policy | Browse operation, scope and selection |
| Notifications | Common media style, icon/action arrangement, labels and consistent presentation | Playback values and semantic actions |
| Browse-item presentation | Common description construction, flags and empty/error presentation | Item content, identity and supported action |
| Audio sessions | PCM format handling, queue admission, write lifecycle and accounting | Session configuration, samples and supported route preference |
| Actual native pages | Shared frame, content/toolbar arrangement and design | Page sections, controller bindings and actions |

The current three channels already provide a family where attachment and outbound invocation can share a focused collaborator or base. Keep feature methods/decoding on their adapters. A protocol/interface establishes a contract; duplicated behavior still requires a shared implementation owner.

PlaybackNotificationFactory and MediaItemFactory are system-facing presentation abstractions. They belong in UI even though Android owns the final rendered layout. Pass typed presentation inputs and supported actions into them. Infrastructure retains notification-channel registration, PendingIntent mechanisms, session ownership and foreground transitions. Bootstrap wires these collaborators so Infrastructure does not reach into concrete page or design implementations.

Keep metadata conversion that only translates native values in Infrastructure. Place recurring design choices and visible arrangement in UI. Give common artwork decoding one owner where execution and lifetime match; a bitmap/resource cache belongs with its resource owner, rather than in an otherwise pure metadata model.

If native Views or Compose are intentionally introduced later, keep page assembly separate from common controls and frames. A shared frame owns recurring toolbar/content placement, including fixed or scrolling variants when relevant; pages supply content/actions. App navigation stays in the shell. Native controllers or suitable ViewModels own functionality. The FlutterActivity itself remains the phone's Flutter host rather than a duplicate Kotlin implementation of the app's Dart screens.

## Kotlin naming files and member order

Use lowercase dot-separated packages matching physical folders, PascalCase filenames/types and lowerCamelCase properties, functions and parameters. Use `UPPER_SNAKE_CASE` for Kotlin constants, such as `SEEK_BACKWARD_TOLERANCE_MS`; keep framework methods, channel strings, media IDs and Intent action values exact. XML resources retain Android's lowercase underscore names and qualifier directories. These conventions adapt the project style to Kotlin. [Kotlin source and naming conventions](https://kotlinlang.org/docs/coding-conventions.html)

Order files as package declaration, imports, closely related contract declarations, primary type and tightly coupled private helpers. Use explicit imports rather than source paths or wildcards; follow the Android formatter's alphabetical import order. Kotlin imports declarations by package, including within the app. Avoid fully qualified names throughout method bodies when a clear import is available.

Prefer one primary concept per file. Small private supporting declarations can stay with their exclusive owner. Standalone models, reusable capabilities and independent presentation components get normal files and imports outside a component's private source tree. File size alone does not determine responsibility; inspect well before the shared 1,000-line review boundary.

Use this type order, omitting unused sections:

1. Primary-constructor inputs, callbacks, configuration and injected dependencies.
2. Companion constants/immutable definitions needed to read the type.
3. Private state and owned resources, with dependent initialization in safe order.
4. Init blocks and secondary constructors where required.
5. Deliberate accessors, with getter/setter pairs together.
6. Lifecycle, initialization, attachment and shutdown in lifecycle order.
7. Public operations and narrow shared extension contracts by responsibility.
8. Private operations and named presentation pieces.
9. Final view/host/presentation assembly when the type has that role.

Constants near the beginning are a Phonolite choice; general Kotlin guidance often puts the companion last. Keep companion behavior focused and avoid process state hidden behind mutable companion properties. Kotlin evaluates property initializers and init blocks in their declaration sequence: preserve that sequence, callback registration and lazy evaluation when reorganizing. Keep overloads adjacent and equality/hash/description methods together near the end when provided.

Prefer `val`, private backing state and `private set` for intentionally observable mutable properties. Public setters remain appropriate for supported local changes. Coordinated work, failure or asynchronous operations deserve named commands. Use internal collaborators inside the app module where useful; framework-instantiated classes retain the accessibility and construction required by Android. Kotlin classes are final by default; add open/abstract only for a real shared extension contract.

Ordinary behavior belongs on the class the project owns. Use extensions for useful operations on external types or a focused external API adaptation. They do not add stored state or grant access to private members of another class. Extract a collaborator instead of spreading an owned class across extension files or exposing mutable state to support that split.

## Kotlin values mutation and readable operations

Use data classes for suitable value contracts, ordinary classes for identity/resource owners, and enums or sealed types for meaningful closed alternatives. Named models take priority over Pair/Triple contracts shared across files; small local results may use them where the meaning is clear.

Kotlin's generated copy operation directly supports the agreed nullable update semantics:

```kotlin
data class TrackMetadata(val id: String, val albumId: String?)

val unchanged = track.copy()
val cleared = track.copy(albumId = null)
val replaced = track.copy(albumId = "album-2")
```

Generated data-class equality/copying uses primary-constructor properties, and copying is shallow. Choose equality by responsibility rather than marking every model/service as data. A ByteArray such as current artwork needs an explicit ownership and content-comparison policy; generated equality does not compare its bytes by content. A read-only List or val reference does not make the referenced contents deeply immutable. Copy at a real ownership boundary when necessary, without adding repeated copies to the PCM path. [Kotlin data classes](https://kotlinlang.org/docs/data-classes.html)

Use typed nullable values and early exits rather than deep nesting. Prefer a short Elvis return for a missing local value and a normal if block for a substantive guard. Keep one blank line between independent guards and logical paragraphs. Related configuration assignments remain contiguous; separate the final result from earlier work. Use braces for multi-step branches and keep else/catch attached to their construct.

```kotlin
fun outputLabel(device: OutputDevice?): String {
  val selected = device ?: return "System Default"

  if (selected.name.isBlank()) {
    return "Output ${selected.id}"
  }

  return selected.name
}
```

Use expression bodies for obvious observations and single expressions; use block bodies and explicit returns for workflows. Scope functions such as let/apply/also/run may make a short local operation clearer, but chains of nested implicit receivers should become named values and operations. Use safe casts at untyped boundaries, meaningful when branches and exhaustive owned alternatives. Keep broad Throwable/runCatching behavior from existing boundaries unchanged during extraction; narrowing or changing recovery is separate behavior work.

Retain individual setters and use builders where construction genuinely benefits. A standard Android builder already provides this style:

```kotlin
val attributes = AudioAttributes.Builder()
  .setUsage(AudioAttributes.USAGE_MEDIA)
  .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
  .build()
```

Keep one configuration call per line and avoid new wrapper builders around every initializer. Do not turn asynchronous workflows into fluent chains that hide ordering. Use KDoc for contracts needing units, lifetime, failures or completion meaning, and comments for consequential decisions rather than narrating syntax. Skip decorative member banners.

## Component and engine lifetimes

| Lifetime | Owns | Boundary to preserve |
| --- | --- | --- |
| Application/process | Shared engine owner, native state and service-accessible capabilities | Can be initialized by a service before any Activity |
| Flutter engine binding | Channels and dependencies tied to one messenger | Ends on deliberate engine detach/replacement, not Activity recreation |
| Activity | Foreground Flutter presentation and Activity-specific bindings | Borrows the shared engine; destruction does not destroy it |
| Media service | MediaSession, active service registration and foreground/notification state | Service destruction releases its resources without treating the Activity as its owner |
| Audio session | AudioTrack, queue, writer and progress state | Explicit close/release path; callback/worker completion semantics remain visible |
| Browse request | Detached result, scope, callback and relevance | Completes once even when its owner/request loses relevance |

Start Flutter loader initialization in Application.onCreate, then lazily finish initialization, create the engine, register generated plugins, attach channels and execute the default Dart entry point. Publish the initialized engine/binding together in one volatile session under the existing synchronization. Explicit registration uses an engine with automatic registration disabled, so plugins initialize once. The media service requests this same engine before assembling its browser, supporting service-first startup.

MainActivity continues to provide the application-owned engine and return false from shouldDestroyEngineWithHost. An Activity-scoped coroutine or ViewModel is not the owner for process/service playback resources. Recreating or leaving the Activity must not silently shut down background playback. [Android Activity lifecycle](https://developer.android.com/guide/components/activities/activity-lifecycle)

Use applicationContext for process capabilities and a scoped Activity only where an Android API requires one. Resolve the native host at framework entry points, then pass narrow dependencies. Avoid retaining Activity/View references in process objects, companion singletons, channel closures or workers.

Android may kill the process without an application cleanup callback. Application.onTerminate is not a production shutdown mechanism. Define explicit cleanup for sessions, service resources, request scopes and deliberate engine replacement, while keeping durable state separate from ephemeral native resources. [Android Application contract](https://developer.android.com/reference/android/app/Application#onTerminate())

## Flutter channels and native functional contracts

Adapters own MethodCall/Result, maps, method names, StandardMessageCodec values and unknown-method handling. Decode once into typed requests; encode typed responses at the boundary. Native controllers keep request/state policies, while Dart retains queue selection, likes, authentication, library filtering and shuffle algorithms.

| Channel | Current contract |
| --- | --- |
| `phonolite/now_playing` | Incoming setNowPlaying/clearNowPlaying; successful calls return true; outbound remoteCommand carries the existing type/arguments |
| `phonolite/carplay` | Incoming authState/carPlayState; source/auth updates return true; outbound browse/play methods keep their existing names and local/server scopes |
| `phonolite/audio_output` | open, write, flush, setVolume, pause, resume, collectDoneSamples, isIdle, close and listOutputDevices with existing scalar/map/byte-array results |

Unknown methods continue to use notImplemented. Preserve missing/malformed argument fallbacks, Boolean/number/string coercions and response types. Android has no current `phonolite/permissions` adapter; the existing [Dart permission service](../lib/infrastructure/platform/permissions/local_network_permission_service.dart) targets iOS.

Keep metadata's seconds-to-milliseconds conversion, clamping/rounding and zero defaults. Remote seek converts milliseconds back to seconds. The 750 ms backward-position tolerance resets on track or epoch changes and when metadata clears. Keep those data rules with a focused position-state owner; dispatch/service effects remain outside it. Android metadata currently defaults omitted fields rather than adopting iOS's mixed patch contract.

VehicleClient decodes typed browse results and preserves malformed-item filtering, default enabled values, empty/error messages, media IDs/prefixes and play/shuffle method selection. VehicleBrowseController can own request coordination and relevance; MediaItemFactory assembles the platform display objects. Preserve detached MediaBrowser result completion, server-before-local ordering and source availability updates. Cancellation/relevance improvements must still fulfill Android's result obligation and remain explicit changes.

The root now contains browsable Server Library and Local Library destinations, at most two, with the existing categories beneath each source. Existing category/leaf IDs remain available; new source IDs are `server_root` and `local_root`. The no-source placeholder is browsable. This avoids the old seven-item mixed root hiding local destinations on hosts that normally expose at most four browsable tabs. [Android Auto root constraints](https://developer.android.com/training/cars/media/create-media-browser/content-hierarchy#structure-the-root-menu)

Channel attachment should be idempotent for its engine binding, with handlers removed before that binding ends. Outgoing invocation uses the Android main thread; the current bridge posts through a main Handler. Incoming task queues and result callbacks have their own threading contracts. Preserve those boundaries when extracting, and marshal UI/service publication where required. [Flutter platform threading](https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading)

## Media service and presentation contracts

Keep the framework service as a thin entry point that forwards to composed owners. Preserve MediaSession callback registration, token publication, MediaButtonReceiver forwarding, START_STICKY and null-Intent behavior. Android can discover/start the media service independently of a visible Activity. The existing stack follows the [media browser service contract](https://developer.android.com/media/legacy/audio/mediabrowserservice).

Preserve notification channel `phonolite.playback`, notification ID 3010, session tag `phonolite_media_session`, Intent action values, immutable/update-current PendingIntent flags and notification action order. Presentation builders own design; service/session owners control activation, state publication and foreground transitions. The paused state currently leaves a notification while dropping foreground status, and clearing metadata stops/cancels through the existing paths.

Source availability and the latest playback snapshot belong to a clear process owner rather than a collection of mutable service companion properties. Replacing that storage must preserve service-first startup, updates while the service is absent, attach/detach notification and existing source-state merging. A weak service reference alone does not define ownership or make multi-field updates atomic.

Keep the exported mediaPlayback service, browser/media-button Intent filters and automotive descriptor aligned with source moves. It does not require the former nonexistent BIND_MEDIA_BROWSER_SERVICE permission. The current browser root policy continues to accept clients; choosing package/signature restrictions is separate access policy. Runtime permission/foreground-start rules depend on API/target level. POST_NOTIFICATIONS is declared without a request workflow. [Android browser manifest](https://developer.android.com/training/cars/media/configure-manifest), [foreground-service declarations](https://developer.android.com/develop/background-work/services/fgs/declare)

MediaServiceConnection distinguishes a bound-only instance from started ownership. First publication requests started ownership once, explicit onStartCommand records it, and later metadata updates avoid repeated start requests. Pending ownership survives attachment; clear/current-instance detachment resets it; failed starts can retry. Playback must keep its started lifetime after the last browser unbind. [Android bound/started service lifetimes](https://developer.android.com/develop/background-work/services/bound-services)

Current Android guidance uses Media3 for new playback implementations. Adopting Media3/ExoPlayer, changing MediaSession behavior or replacing the existing Dart/AudioTrack playback path is a separate feature/migration decision. Responsibility folders do not require changing the media library. [Android Media3 guidance](https://developer.android.com/media/implement/playback-app)

## Audio resources concurrency and completion

The [Dart Android output adapter](../lib/infrastructure/platform/audio/android_channel_output.dart) communicates through the PCM channel. AudioOutputChannelAdapter owns method decoding and result defaults; AudioOutputService owns session IDs/registry; AudioOutputSession owns AudioTrack/writer resources; AudioFocusController owns focus/noisy-device mechanisms. OutputDeviceCatalog returns named values that the adapter encodes into the existing device maps.

| Contract | Behavior to preserve |
| --- | --- |
| PCM | Signed 16-bit interleaved mono/stereo; channel PCM is ByteArray; progress is interleaved sample count, not bytes or frames |
| Admission | Queue capacity is five waiting chunks, with a separate pending-frame limit; the writer can hold an already dequeued chunk |
| Status | Zero write success, `-3` backpressure, existing invalid-session/PCM failures and propagated AudioTrack failures |
| Writer | Nonblocking AudioTrack writes, partial-write progress and existing retry/sleep behavior outside the channel handler |
| Progress | Polling/estimation capped by submitted frames; retain completed samples until collection, including polls from write/pause/isIdle |
| Flush | Advance generation, clear pending writes and reset submitted/playback-head tracking; already accumulated uncollected completions remain available |
| Idle | Pending playback and queue state; idle may still have completed samples waiting to be collected |
| Close | Remove/invalidate session, clear/wake queue, interrupt writer and attempt AudioTrack cleanup under existing locks |
| Focus and route | Pause on noisy output or the handled focus losses; preferred output selection remains best effort, with system routing for the default |

The existing close does not join the writer thread, and cleanup attempts swallow some platform exceptions. Its reply must not be described as proof of thread termination or successful release. A stronger awaitable close contract needs a separate lifecycle change and focused concurrency verification. Preserve the Dart adapter's handling of an open that completes after disposal begins.

Flush currently retains uncollected completion counts and does not first poll the final old playback position. Preserve that distinction from resetting pending writes. Reported progress includes a playback-head estimate; it is not proof of exact physically audible completion. Generation validation and the write lock keep obsolete chunks from advancing the new submitted-frame ledger.

Keep memory and sample ownership explicit across channel decoding, queue admission and worker consumption. A read-only reference is not a deep copy. Do not add copies or replace the channel with JNI/FFI as a styling change. Preserve focus-request acceptance behavior and ignored preferred-device results during extraction; stricter routing/focus failures are behavior changes.

Give every mutable owner a documented thread/isolation domain. Volatile fields, concurrent maps, atomics and synchronized blocks have different responsibilities; none individually establishes the safety of a compound workflow. Keep main-thread channel/service work separate from AudioTrack writing and preserve lock order. Avoid slow work or waiting for a writer while holding a lock it needs.

Coroutines are an option for deliberately changed asynchronous workflows, with an explicit owner, dispatcher and cancellation/completion contract. Suspending does not preserve request relevance automatically. Keep callback obligations, generation checks and release rules after suspension. Do not introduce GlobalScope, unowned executors or lifecycleScope ownership for process playback. A coroutine migration is not a prerequisite for readable Kotlin or a reason to change the current writer's scheduling.

## Android resources Gradle and native packages

Keep `src/main`, `src/debug`, `src/profile`, `res` types and qualifier folders intact. Android discovers resources and merges manifests by source set. Move Kotlin collaborators inside the source root and update package/import/component references together. Preserve launch/normal themes, launcher icons, native media drawables, resource names and embedding metadata. New shared native styling belongs in appropriate theme/style resources and UI abstractions.

Preserve namespace/applicationId `com.example.phonolite_app`, main Activity singleTop/configChanges behavior, process-text query and cleartext-disabled network policy. The existing manifest permissions cover internet/network state, wake lock, notifications and foreground media playback. Renaming the application identity or changing permissions/signing is separate product/build work.

The checked-in build selects AGP 8.9.1, Kotlin plugin 2.1.0 and Gradle wrapper 8.12. Java source/target and Kotlin bytecode target are 11; that does not mean Gradle runs on JDK 11. SDK and NDK versions come from Flutter extension values. The installed Flutter SDK currently resolves compile/target SDK 36, minimum SDK 24 and NDK 27.0.12077973; these are SDK observations, not fixed literals in the app build. Keep toolchain upgrades separate from organization.

The app uses core-ktx 1.13.1 and androidx.media 1.7.0. Release currently uses debug signing, and its existing copy finalizer emits app-release.apk and phonolite-release.apk. Preserve build behavior and artifact paths during structural work without presenting that signing setup as a release-distribution policy.

| Native package | Android integration | Preserve |
| --- | --- | --- |
| [phonolite_opus](../packages/phonolite_opus/android/build.gradle) | External CMake builds vendored Opus into the FFI shared wrapper | `libphonolite_opus.so`, C ABI and upstream source/build ownership |
| [phonolite_local_audio](../packages/phonolite_local_audio/android/build.gradle) | cargo-ndk release builds copied into jniLibs | `libphonolite_local_audio.so`, handles, decoder units and matching close |
| [phonolite_quic](../packages/phonolite_quic/android/build.gradle) | cargo-ndk plus locked quiche/BoringSSL, NDK/CMake/Ninja preparation | `libphonolite_quic.so`, authentication/pin checks, native allocations and matching free |

These are FFI packages, not handwritten Kotlin/JNI plugins. Keep C/Rust/native build glue in the owning package. The Rust builds currently target armeabi-v7a, arm64-v8a and x86_64; the app's effective ABI set must match the artifacts actually packaged. Library minSdk/build declarations and native API levels do not define the merged application's minimum by themselves.

Local-audio and QUIC preBuild hooks delete their task-owned Cargo/jniLibs output and rebuild it; QUIC also fetches locked dependencies and builds native TLS libraries. Even a nominal Gradle compilation/test task may traverse those hooks. Respect build outputs, caches and package boundaries; bypassing native tasks provides partial Kotlin verification rather than a complete APK/ABI check.

## Kotlin formatter configuration

Use ktlint **1.7.1** with [android/.editorconfig](../android/.editorconfig). The Android Studio style provides a Kotlin/Android baseline, overridden with the project's indentation and line-width preferences:

```editorconfig
root = true

[*.{kt,kts}]
charset = utf-8
indent_style = space
indent_size = 2
max_line_length = 120
insert_final_newline = true
ktlint_code_style = android_studio

# Preserve the established app package; new responsibility segments remain lowercase words.
[app/src/**/kotlin/com/example/phonolite_app/**/*.kt]
ktlint_standard_package-name = disabled
```

Under this style, signatures that fit are eligible to remain compact rather than being split solely for having multiple parameters. Preserve logical paragraph breaks manually and use the formatter's normal wrapping when a signature exceeds the limit. Verify these examples when selecting the pinned tool; no formatter can replace responsibility or readability review. [ktlint rules and configuration](https://github.com/ktlint/ktlint/blob/master/documentation/release-latest/docs/rules/standard.md#function-signature)

The [formatter helper](../tools/android_checks/format_kotlin.py) pins the Maven artifact and SHA-256, caches it under `.dart_tool/android_tools`, and selects handwritten Kotlin/test/build-script files explicitly. Run from the app root:

```sh
python tools/android_checks/format_kotlin.py
python tools/android_checks/format_kotlin.py --format
```

The initial formatter download needs network access; later checks use the verified cache. Java must be available. The package-name rule exception is scoped to the established `phonolite_app` prefix; new responsibility segments still follow lowercase naming and architecture checks. Keep generated sources, dependencies and vendored code outside formatting passes. EditorConfig does not register a Gradle plugin or enforce lifetimes. C/Rust/Groovy/XML retain their own tools. [ktlint CLI](https://ktlint.github.io/ktlint/latest/install/cli/)

## iOS reference and functional assessment

The comparison used the [iOS native host](../ios/Runner/Bootstrap/NativeHost.swift), [CarPlay browse controller](../ios/Runner/Application/Controllers/CarPlay/CarPlayBrowseController.swift), [remote commands](../ios/Runner/Infrastructure/Media/RemoteCommandService.swift) and [native audio bridge](../ios/Runner/Infrastructure/Audio/Native/phonolite_audio.m), together with their shared Dart clients. The common expected behavior is server/local browsing and playback selection, now-playing metadata and epochs, remote controls, interruption/route-loss pause and bounded PCM output.

The structural extraction preserves those contracts. These source-evidenced corrections were made explicitly:

| Problem | Corrected behavior | Verification anchor |
| --- | --- | --- |
| Service-only browsing could return no sources without ever starting Flutter | Media-service creation initializes the same process engine before browser assembly; source updates refresh the tree | Startup source checks plus real SDK compilation |
| The browser service required nonexistent BIND_MEDIA_BROWSER_SERVICE permission | Exported browser discovery uses the supported manifest contract without that blocking attribute | Manifest/resource checks and Android source contracts |
| Default engine construction plus manual registration registered plugins twice | Automatic registration is disabled and the generated registrar runs once before channel attachment/Dart startup | Engine ordering/source contract |
| Focus loss left cached ownership true | Loss clears ownership before requesting pause; explicit resume can reacquire focus; separate registration state preserves final abandonment; gain does not auto-resume playback | Focus callback ordering and cleanup source contract |
| Every metadata update requested another service start | A shared connection tracks pending/started ownership, including bound-only service startup, and requests it once until clear/destruction; late start acknowledgements cannot undo a clear | Ten headless lifecycle checks |
| Up to seven mixed root items could hide local categories in Android Auto | Two browsable source roots retain existing nested destinations and playback operations | Typed browse-controller checks, presentation review and SDK compilation |

Android intentionally keeps its own API behavior: system seek is supported here while the iOS remote-command service disables it; Android receives inline artwork from Dart while iOS can load artwork natively; Android uses AudioTrack/output devices while iOS uses AudioQueue/session policies. The Android metadata decoder retains its full-value/defaulting behavior, and completion/flush accounting keeps the existing Dart orchestration rather than copying iOS counters mechanically.

Remaining differences are concrete follow-up work:

- Android vehicle browse entries still omit the artwork URL/credential/pin presentation supported by the iOS path. Adding it needs an Android image-loading/access contract.
- The local Android source retains Artists, Playlists and Liked destinations; it does not yet expose the local Shuffle destination available in CarPlay. Adding it requires explicit scoped browse/action support.
- Focus denial is recorded without preventing AudioTrack playback. Android 15+ foreground eligibility and the ordering of service promotion/output startup need device validation before changing denial/retry behavior. [Android audio focus](https://developer.android.com/media/optimize/audio-focus)

The service retains its existing browser-client acceptance policy. A package/signature allowlist would be an explicit access-policy change, rather than an incidental replacement for the removed permission. Native hardware, real Android Auto rendering and OS service scheduling remain outside headless verification.

## Adoption and verification

For future changes, preserve the extracted responsibility boundaries and make functional changes visible:

1. Extract standalone values/codecs and shared channel mechanics, retaining exact payload/reply behavior.
2. Separate engine/bootstrap composition while preserving one service-accessible process engine and Activity borrowing.
3. Extract audio session/focus/device/progress owners without changing locks, generations, buffering or close meaning.
4. Extract media state/browse coordination and shared presentation builders, leaving the framework service focused on lifecycle delegation.
5. Move entry points with aligned manifest/Intent/package/resource references, then apply Kotlin layout within the affected owners.

The [Android source contracts](../test/requirements/platform_android_contract_test.dart), [architecture checks](../test/architecture/android_architecture_test.dart), [Dart output lifecycle tests](../test/architecture/audio_output_lifecycle_test.dart) and [native media codec tests](../test/architecture/native_media_codec_test.dart) anchor existing behavior. Five dependency-free test mains under `src/test/kotlin` exercise progress, metadata/source state, browse routing, transport and service lifetime. These headless checks do not execute AudioTrack, an Android service or Android Auto.

Put pure Kotlin model/codec/controller tests under `src/test/kotlin`, using injected transport, clocks and capabilities. Device/emulator-dependent tests belong under `src/androidTest/kotlin`. Keep headless checks independent of listeners, real media playback and running Flutter engines. Verify source packages/imports, merged manifest identities/resources, channel contracts, compile output and packaged native symbols/ABIs as appropriate to the change.

The [headless Kotlin verifier](../tools/android_checks/verify_kotlin.py) compiles all handwritten production/test Kotlin against the configured Android SDK, cached Flutter embedding and AndroidX APIs. It uses the app's cached Kotlin compiler version, aapt2-generated resource IDs and the real manifest/resources, then runs the five JVM test mains. From the app root:

```sh
python tools/android_checks/verify_kotlin.py
```

It resolves SDK paths from local.properties/environment and accepts explicit path overrides. It neither starts Gradle nor rebuilds native packages. Its resource/Kotlin compilation does not replace a complete variant APK build, manifest merge with every plugin, native ABI packaging or device testing. Kotlin and resource checks, ktlint 1.7.1 and focused Dart checks passed for the refactor.

From `android`, a configured build environment can compile or run local unit tests without installing or starting the app:

```sh
./gradlew --no-daemon -Pkotlin.compiler.execution.strategy=in-process :app:assembleDebug
./gradlew --no-daemon -Pkotlin.compiler.execution.strategy=in-process :app:testDebugUnitTest
```

On Windows use `gradlew.bat`. The SDK/JDK/NDK, Flutter artifacts and native package toolchains/dependencies must be available. Check Profile/Release configurations where relevant. Local unit tasks alone do not establish native runtime behavior or device compatibility.

Disable persistent Gradle reuse and use in-process Kotlin compilation for agent verification. Gradle may use a disposable JVM to honor configured JVM arguments; it stops after the build. Ensure no task-owned compiler/server process remains afterward, without stopping unrelated user work. [Gradle daemon behavior](https://docs.gradle.org/current/userguide/gradle_daemon.html), [Kotlin compiler strategy](https://kotlinlang.org/docs/compiler-execution-strategy.html)

During agent work, do not run the app, media service, emulator, connected/instrumentation tests, adb server, development server or other background service. Device/Android Auto, focus/noisy-output, real playback and notification checks remain user-controlled. Complete APK/native package builds and native runtime checks were not performed as part of the headless refactor verification.
