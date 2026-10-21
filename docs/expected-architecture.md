# Expected Phonolite architecture

This is the authoritative guide to organizing Phonolite source. It defines where responsibilities belong and how shared abstractions establish consistent code structure, behavior and UI design. It combines the organization demonstrated in Katiby with the responsibility boundaries and shared structures developed in Phonolite.

The companion [coding standards](coding-standards.md) define how individual Dart files, types and operations should read, including member ordering, formatting, naming, encapsulation and lifecycle contracts.

The [iOS and Swift specification](ios-swift-specification.md) extends these responsibility and assembly principles to the native host and documents the source map for Apple integration and CarPlay.

The [Windows native C++ specification](windows-native-specification.md) applies the same principles to the Flutter Win32 host, native resource lifetimes, platform channels and package boundaries.

The [macOS native specification](macos-native-specification.md) defines the corresponding AppKit/Flutter host organization, Swift and C conventions, audio ownership and Xcode integration rules.

The [Android native specification](android-native-specification.md) applies these principles to Kotlin packages, Android component lifetimes, shared engine ownership, audio resources and system media presentation.

The [Linux native C++ specification](linux-native-specification.md) defines the GTK/Flutter host boundaries, GObject and C++ ownership, directory transport, CMake integration and future Linux playback responsibilities.

The directory tree should explain the app before someone reads its implementation. A reader should be able to locate a responsibility, understand a page's assembly, and follow named components into the details.

## Governing rule: abstraction, specialization and assembly throughout the app

**Shared abstractions define the general structure, design and behavior. Specialized implementations supply the parts that vary. Composition assembles those pieces into larger responsibilities.** This is an architectural requirement throughout the app: UI, controllers, application workflows, data operations, storage and runtime integration.

Consistency must come from shared code. A developer should inherit or compose the common decisions, then implement the meaningful differences. Copying a layout, algorithm or lifecycle and keeping each copy consistent by convention does not satisfy this architecture.

There are three related roles:

| Role | Owns | Consumers supply |
| --- | --- | --- |
| Shared abstraction | The common structure, rules, design, behavior and extension contract for a coherent family | Only the inputs and variation points that family allows |
| Specialized implementation | A particular responsibility within that structure | Its content, actions, data rules or platform-specific operations |
| Assembly | Selection, wiring and composition of those pieces into a larger component or workflow | Explicit dependencies, values, children and callbacks |

These roles repeat at different scales. A section assembles controls, a page assembles sections, and the shell assembles the page, player and app navigation. A controller can assemble shared workflows and data capabilities; a server connection assembles endpoint clients around a shared transport. An assembled component can itself become a building block for another assembly.

The page base and navbar are examples of this general rule. The same expectation applies wherever a family shares decisions:

| Responsibility area | Shared owner defines | Specialization and assembly provide |
| --- | --- | --- |
| UI design and controls | Theme/tokens, control states, typography, surfaces and interaction patterns | Semantic variants, labels, values, icons and callbacks |
| UI structures and shell | Common frames, layout rules, spacing, adaptive behavior and assembly hooks | Section/page content, toolbar actions and destination definitions |
| Controllers and application workflows | Common state transitions, notification/lifecycle mechanics and recurring operation policies | Feature state, commands, validation and injected capabilities |
| Data and storage | Shared value rules, containers, serialization helpers and persistence/transaction mechanisms where applicable | Subject-specific values, queries, schema and storage operations |
| Infrastructure and platform integration | Capability contracts, shared execution policy and resource lifecycle | Protocol-specific operations, endpoint payloads and platform adapters |

An abstraction can be a base class with hooks, an interface with implementations, a composed collaborator, a parameterized component or a shared data operation. Choose the mechanism that expresses the relationship clearly. An interface establishes a common contract; any behavior that implementations must share also needs a shared implementation owner. A common interface alone does not remove duplicated policy.

Keep these structures in their responsibility areas. `ui/shell` owns the page/navigation families; application owns shared functional workflows; data owns shared data operations; infrastructure owns technical capability families. Do not collect unrelated abstractions into a general-purpose base directory or make one universal superclass own all responsibilities.

This document defines the expected architecture, not a claim that every existing component already follows it. The linked implementations are precedents. New work must use or establish the appropriate shared structure, and refactors must move the affected family toward this model while preserving behavior.

## 1. Organize by responsibility

A directory identifies an owner or kind of work. A file identifies a coherent component within that responsibility. Class inheritance, file size and the first consumer of a helper do not determine its source home.

- Give data, application functionality, page assembly, UI presentation and runtime integration distinct source areas.
- Assemble views and workflows from named components with explicit inputs, dependencies and callbacks.
- Define common structure, design and behavior once within each family; expose clear extension points for the parts that vary.
- Give independent components ordinary Dart libraries and normal imports.
- Keep closely related implementation details together, with ownership and cleanup visible.

### Source areas

| Area | Owns | Placement boundary |
| --- | --- | --- |
| `lib/bootstrap/` | Dependency construction, startup sequence, root setup and application shutdown | Connects the other areas; the other areas do not import bootstrap |
| `lib/pages/` | Final page assembly, controller binding, page-scoped visual state and concrete route destinations | Uses UI components and controller APIs; delegates functional work |
| `lib/ui/` | Presentation components, shared frames, visual interaction and assembly helpers | Supplies the building blocks used by pages; never imports pages |
| `lib/application/` | Controllers, shared workflows and application lifecycles | Provides functionality without widget, route or dialog ownership |
| `lib/data/` | Data definitions and operations naturally belonging to that data | Has one designated source silo, independent of application and presentation |
| `lib/infrastructure/` | Runtime execution, protocols, workers, native resources and platform adapters | Implements technical capabilities using standalone data definitions |

`lib/main.dart` is the thin entry point that delegates to bootstrap. Group subjects or features inside their owning area. Shared presentation is further grouped by its role.

```text
lib/
  main.dart
  bootstrap/
  pages/<feature>/
  application/
    controllers/<feature>/
    app/                       # App facade and its private workflows
    downloads/
    library/
    listening_stats/
    playback/
    presentation/              # Application-facing labels/helpers
  data/
    models/<subject>/
    projections/<subject>/
    queries/<subject>/
    rules/<subject>/
    structures/<subject>/
    configuration/<subject>/
    storage/<subject>/
    files/
    repositories/
  ui/
    app_scope.dart
    controller_binding.dart
    shell/
      base_page.dart
      base_form_page.dart
      page_body.dart           # Toolbar placement and body contracts/layout
      page_scroll_view.dart    # Shared sliver viewport and content gutters
      adaptive_scaffold.dart
      playback_content_inset.dart
      toolbars/
      navigation/              # App destination surfaces
    structures/
      modals/
      sections/
    features/<feature>/
      widgets/
      sections/
      dialogs/                 # Use the roles that actually exist
    shared/
      design_system/           # Controls, layout, surfaces, icons, theme
      music/                   # Shared music presentation
    navigation/                # History, transitions and input helpers
  infrastructure/
    audio/
    downloads/
    server/
    platform/
    artwork/
    security/
```

The tree is an ownership map. Create a directory when it has a meaningful responsibility and real contents; individual features need only the subdirectories they use. Abstraction, specialization and assembly happen within these areas; they do not require three additional top-level directories.

## 2. Separate page assembly, presentation and functionality

### Pages assemble complete views

Every tab root, detail screen, settings subpage, home view and splash view belongs under `pages/<feature>`. Established public names such as `ArtistDetailScreen` and `PlaylistDetailView` still represent pages; the filename suffix does not change their responsibility.

A page selects components, binds their data and callbacks, presents confirmations and chooses concrete navigation destinations. It may own focus, text editing, scroll position and other local visual state. Functional state and operations belong to controllers.

The shared page family defines the surrounding frame and assembly contract. Each page supplies its content and connections through that contract. A page should read as the assembly of its particular view, with common presentation decisions inherited or composed from their shared owners.

[SettingsPage](../lib/pages/settings/settings_page.dart) is the concrete pattern: it composes general, user, local-storage and miscellaneous sections. It creates login, password, shuffle and log routes, then supplies callbacks to the sections. The sections do not need to know which page implements a destination.

### UI supplies presentation components

Use `ui/features/<feature>` for feature-specific widgets, sections and dialogs. Use `ui/shared/music` for shared album, artist, track and playback presentation, and `ui/shared/design_system` for general controls, surfaces, typography, icons and layout helpers.

A component may deserve its own UI file even when only one page uses it. A liked-track section, playlist list/grid section or toolbar has a recognizable responsibility independent of its current consumer. Small private rendering helpers can remain beside that component.

UI owns layout, animation, hover, focus, Flutter text/scroll/animation controllers, visual drag state, modal presentation and dismissal. Constructor parameters should expose the data, state, child widgets and callbacks needed to render that responsibility.

Shared design has several levels: theme and tokens define visual values; controls own consistent rendering and interaction; section, modal and shell structures own common arrangements. Use all applicable levels. Supplying the same colors to several separately rebuilt controls does not make their structure or interaction shared. A design change should flow from its owning abstraction to every member of the family.

### Controllers provide functionality

Feature controllers live under `application/controllers/<feature>`. They own validation, loading/errors, functional selection, filtering, pagination, debouncing, asynchronous commands, request generations and stale-result guards. Shared application workflows live in the app component or other named application modules.

For example, a widget observes scroll position and passes the remaining extent to [LibraryController](../lib/application/controllers/library/library_controller.dart). The controller decides whether another page of artists should load. The widget owns the Flutter `ScrollController`; the controller owns the loading policy.

| Responsibility | Expected owner |
| --- | --- |
| Read field text, manage focus, animate or track drag position | Page or UI component |
| Validate a password, filter results or decide which items are selected | Feature controller |
| Present a confirmation and display its result | Page or UI component |
| Execute the approved deletion, save or playback action | Application controller/workflow |
| Describe an action result, destination or data snapshot | Data model/projection |
| Construct a route to a concrete page | Page |

An event handler can collect input, present a confirmation, call a controller, check that its widget is still mounted and perform a visual response. It should delegate data access and the functional operation. Controller results describe values or destinations rather than Flutter widgets and routes.

[FeatureController](../lib/application/controllers/feature_controller.dart) provides notifications and a disposal guard. [ControllerBinding](../lib/ui/controller_binding.dart) connects notifications to rendering and disposes controllers owned by that view. Shared application state remains owned by the existing application controller; a new page controller must not create another playback engine, library or download manager.

Apply the same separation inside functionality. When controllers share a loading, pagination, cancellation or command policy, give that policy a common owner with explicit feature inputs. Controllers specialize or compose it rather than copying the sequence. Keep independent policies in focused collaborators when putting them in one controller base would combine unrelated responsibilities.

## 3. Use shared extensible structures

A shared structure owns the stable arrangement or execution protocol for a coherent family and names the responsibilities that vary. Concrete implementations supply those responsibilities through hooks, parameters or injected capabilities. Keep the hierarchy short and the inputs visible. This applies equally to presentation and functional code.

### Choose how the family extends

| Mechanism | Use it for | Common ownership |
| --- | --- | --- |
| Base class with named hooks | A stable assembly/execution sequence with specialized steps or content | The base owns the sequence and invariants; subclasses implement the permitted differences |
| Parameterized component or function | A shared operation or arrangement whose variations are values, children or callbacks | Consumers configure the same implementation |
| Shared collaborator or strategy | A policy/capability used across otherwise independent components | Consumers delegate common work and inject the varying behavior |
| Interface with adapters | Interchangeable implementations of a capability, such as platform audio output | The interface defines the contract; shared collaborators own any common execution policy |
| Composition | Building a larger responsibility from existing pieces | The assembly wires those pieces while each keeps its own rules and lifecycle |

Using a `Base...` class everywhere is not the goal. Every common decision needs one owner, and every family needs a clear way to supply its differences. Inheritance and composition are ways to achieve that expectation.

### Presentation examples already in use

Katiby's [BasePage](../../katiby-app/lib/pages/base_page.dart), [KatibyBaseNavbar](../../katiby-app/lib/widgets/navigation/katiby_base_navbar.dart) and [KatibyBaseModal](../../katiby-app/lib/widgets/modals/katiby_base_modal.dart) demonstrate this pattern: shared frames call methods such as `navbar()`, `mainContent()`, `leadingNavbarContent()`, `modalContent()` and `modalActions()`. Specialized implementations provide content while the frame keeps the presentation consistent.

Phonolite applies that approach through these families:

| Shared structure | Location | Extension points and use |
| --- | --- | --- |
| Page frame | [base_page.dart](../lib/ui/shell/base_page.dart) and [page_body.dart](../lib/ui/shell/page_body.dart) | `pageContent(context, assemble)` supplies `navbar` and `PageBody` slots; the base owns scrolling/fixed placement, optional scaffold/safe-area/background and `decoratePage` |
| Form page | [base_form_page.dart](../lib/ui/shell/base_form_page.dart) | `pageTitle`, `formContent`, back visibility/action, dismissal guard and form width; used by login and password reset |
| Page toolbar | [base_page_toolbar.dart](../lib/ui/shell/toolbars/base_page_toolbar.dart) | Leading, title and trailing-action content, alignment, spacing and constraints; used by title/back headers and configurable `PageToolbar` |
| App navigation | [base_app_navigation.dart](../lib/ui/shell/navigation/base_app_navigation.dart) | Destination rendering, selected presentation, surface dimensions/border, arrangement and decoration; used by side and bottom navigation |
| Standard alert | [base_alert_modal.dart](../lib/ui/structures/modals/base_alert_modal.dart) | `modalTitle`, `modalContent`, `modalActions`, `modalScrollable`; used by storage-path, playlist-membership and output-device dialogs |
| Box section | [base_section.dart](../lib/ui/structures/sections/base_section.dart) | `sectionTitle`, `sectionContent`, heading and spacing; used by settings sections |
| Sliver section | [base_sliver_section.dart](../lib/ui/structures/sections/base_sliver_section.dart) | Optional heading, `sectionSliver` and padding; used by liked-track and playlist collections |

The assembly `build` methods are marked `@nonVirtual`. Extend a family through its hooks rather than copying its outer frame. `BasePageState` and `BaseAlertModalState` reuse `ControllerBinding`; concrete consumers bind the controller they own. Binding invokes the controller's idempotent `initialize()` before attaching its render listener, preserving startup order and handling detached initialization errors. Feature-specific startup belongs in the controller's `initializeFeature()` hook; construction stays inert. Bases supply this lifecycle protocol without a concrete feature-controller dependency.

Page framing defaults to embedded content. Standalone pages explicitly opt into their own scaffold and safe area, preserving the surrounding tab shell's ownership. Fixed page toolbars also work in an embedded page without adding a scaffold. The form base supplies its back/title toolbar and constrained form body through the same contract, sharing keyboard dismissal and playback/keyboard clearance. Its consumers retain their fields, focus behavior and application actions.

### Functional examples already in use

- [FeatureController](../lib/application/controllers/feature_controller.dart) supplies a shared update/notification protocol and disposal guard. Feature controllers extend it with their state and commands, while [ControllerBinding](../lib/ui/controller_binding.dart) supplies the common view-binding mechanics. This separates reusable mechanics from specialized functionality and page assembly.
- [ServerConnection](../lib/infrastructure/server/server_connection.dart) composes endpoint clients around one [ApiTransport](../lib/infrastructure/server/transport/api_transport.dart). The transport owns common session, authentication, trust, retry and request policy; endpoint clients provide their particular API operations. Composing one transport keeps those decisions consistent without an endpoint inheritance hierarchy.
- [AudioPcmOutput](../lib/infrastructure/audio/output/audio_pcm_output.dart) defines the device-output contract. Platform adapters implement its operations, and the audio runtime uses that contract. The contract allows platform variation; common engine policy remains owned by the runtime using it.
- [ObsidianTheme and ObsidianPalette](../lib/ui/shared/design_system/theme/obsidian_theme.dart) centralize theme and color decisions. Controls and structural families build on those shared definitions, so visual consistency is implemented at each relevant level.

These examples demonstrate different mechanisms for the same architectural rule. They do not imply that every controller policy, data operation or UI control has already been consolidated.

### Shared implementation families

Use these owners when extending their families. Each owns actual common implementation; its consumers supply the specialized pieces.

| Family and shared owner | Common decisions | Specialized consumers and assembly |
| --- | --- | --- |
| [Page body/layout](../lib/ui/shell/page_body.dart) and [scroll/content slivers](../lib/ui/shell/page_scroll_view.dart) | Toolbar/body assembly, fixed/scrolling placement, system/player clearance and the page gutter | Pages supply slots and body configuration through the base; sliver content retains its own vertical spacing |
| [Page toolbar actions](../lib/ui/shell/toolbars/page_toolbar_actions.dart) | Wrapping action alignment and responsive icon dimensions/spacing | Pages provide actions; toolbars and app navigation retain separate owners |
| [CollectionSliver](../lib/ui/structures/collections/collection_sliver.dart) | Lazy list/grid assembly, separators and standard grid geometry | [Artist collections](../lib/ui/shared/music/artists/artist_collection_sliver.dart), [album collections](../lib/ui/shared/music/albums/album_collection_sliver.dart), playlist sections and artist contributions supply item presentation |
| [Media selection](../lib/ui/shared/music/media_selection.dart), [row](../lib/ui/shared/music/selectable_media_row.dart) and [card](../lib/ui/shared/music/selectable_media_card.dart) | Selection/deletion interaction, feedback and semantics | Artist and album widgets supply artwork, labels and callbacks |
| [ObsidianListRow](../lib/ui/shared/design_system/controls/obsidian_list_row.dart) and [modal list row](../lib/ui/shared/design_system/modals/obsidian_modal_list_row.dart) | Responsive row geometry, labels and interaction surfaces for their respective families | Media, search, settings and picker widgets supply leading/trailing content and actions |
| [SelectionSliverSection](../lib/ui/structures/sections/selection_sliver_section.dart) | Search, selection summary/actions and choice-content assembly | Shuffle artist and genre sections supply choices and controller commands; [choice rows](../lib/ui/shared/design_system/controls/obsidian_choice_row.dart) compose the shared row |
| [Media hero frame](../lib/ui/shared/music/media_hero_frame.dart) and [details](../lib/ui/shared/music/media_hero_details.dart) | Shared title/summary treatment and hero content arrangement | Artist and album heroes retain their distinct artwork, dimensions and metadata |
| [Artwork image](../lib/ui/shared/music/artwork/artwork_image.dart) and [placeholder](../lib/ui/shared/music/artwork/artwork_placeholder.dart) | Provider/loading/error assembly and fallback presentation | Album art and artist avatars provide fit, shape and subject-specific fallback content |
| [Pointer interaction](../lib/ui/shared/design_system/interaction/pointer_interaction.dart) and [chamfer geometry](../lib/ui/shared/design_system/surfaces/chamfer_geometry.dart) | Pointer lifecycle/haptics and shared path construction | Controls retain their own appearance and shape parameters |
| [PlaybackScrubber](../lib/ui/features/playback/widgets/components/playback_scrubber.dart) | Progress interpolation, drag preview, seek callbacks and timer cleanup | Compact and expanded controls implement presentation; compact-only ticker/tracing behavior uses explicit hooks |
| [Editor dialog](../lib/ui/shared/design_system/modals/obsidian_editor_dialog.dart) and [statistics module shell](../lib/ui/features/listening_stats/widgets/stats_module_shell.dart) | Their families' surrounding layout and surfaces | Playlist editor supplies form/actions; statistics assembly composes standalone header/history/KPI/analysis/ranking components |
| [ControllerSelection](../lib/application/controllers/shared/controller_selection.dart) | Enter/toggle/replace/clear transitions and grouped selection under one notification boundary | Feature controllers provide identities, eligibility and feature commands |
| [RequestGeneration](../lib/application/workflows/request_generation.dart), [DebouncedAction](../lib/application/workflows/debounced_action.dart) and [FeatureController](../lib/application/controllers/feature_controller.dart) | Request freshness, one pending delayed action, owned subscriptions and disposal guards | Application owners provide operation-specific session checks, delays, work and cleanup/flush policy |
| [Track identity rules](../lib/data/rules/library/track_identity.dart) and [downloaded-track capability](../lib/application/downloads/downloaded_track_selection.dart) | Data identity and application-level download eligibility respectively | Selection controllers compose the capability while the pure identity definition stays in data |
| [JsonSettingsFile](../lib/data/storage/preferences/json_settings_file.dart) | File resolution, JSON read/write, optional atomic replacement and serialized updates | Preference stores retain schema, defaults, managed-path checks and error policy |
| [ArtistCredit](../lib/data/models/library/artist_credit.dart) and [JsonValues](../lib/data/structures/serialization/json_values.dart) | Contributor roles/credit fallback and tolerant value conversion | Album, track, release and other models define their subject schema |
| [Offline library database access](../lib/data/storage/offline/library/offline_library.dart) | The common connection acquisition/recovery/release protocol | Store operations retain their SQL and transaction boundaries; paths with distinct tracing or setup remain explicit |
| [JsonApiEndpoint](../lib/infrastructure/server/api/json_api_endpoint.dart) and [ApiResponseDecoder](../lib/infrastructure/server/transport/api_response_decoder.dart) | Typed endpoint request/mapping assembly and buffered HTTP/JSON validation/decoding | Endpoint clients define routes and response factories; transport retains authentication, retries and session ownership |
| [Audio output configuration](../lib/infrastructure/audio/engine/session/audio_output_configuration.dart) | Output compatibility, replacement/epoch checks, cleanup, creation and state application | Local/remote source owners retain buffer/header preparation; this shared protocol remains private to the engine |

Design-system controls, surfaces and section headers have ordinary files under their own roles. The existing `obsidian_widgets.dart` export facade preserves compatibility; new consumers should import the role-specific owner they use. Statistics components likewise use ordinary imports rather than sharing library privacy merely to split a large file.

### When to introduce, extend or compose a structure

| Situation | Expected choice |
| --- | --- |
| A known family has a common frame or operation sequence with identifiable variation points | Establish or extend its shared structure before implementing variants; migrate existing consumers together |
| A new member belongs to an established family | Use that family's abstraction and extension contract; add a meaningful extension point if needed |
| Independent components need the same functional policy or data operation | Extract a shared collaborator/operation in the owning area and compose it into each consumer |
| A capability has alternative platform or technical implementations | Define its contract, isolate the varying implementations and share common execution policy |
| A component already exposes the required child/content/action parameters | Compose it directly; `PageToolbar` supports custom slots without another subclass |
| A recognizable presentation responsibility makes a page easier to read | Extract a standalone UI component, including for a single consumer |
| A small private helper only supports one coherent operation | Keep it beside that operation |
| Behavior coordinates application capabilities or functional state | Extract a controller or named workflow |
| An operation constructs, queries, transforms, opens or saves particular data | Place it with the data or its data-service/store responsibility |
| A parser, worker or native resource has its own technical lifecycle | Give it an infrastructure module with explicit ownership |

Identify the family, its common decisions and its permitted variations before implementing another member. Do not wait for several copied implementations: a known family can start with a shared structure and its first concrete consumer. Define the structure from actual responsibilities and required variations, rather than speculative configuration.

Choose hook and parameter names that describe those variations. The shared implementation must own the decisions intended to stay consistent and remain understandable without opening every consumer. Prefer composition when varying content or behavior is already expressible through parameters or collaborators. Keep a custom editor, player surface or adaptive sheet in its own presentation family when its layout/lifecycle differs from a standard alert.

## 4. Put shared page design in the shell

The source home follows the responsibility. `BasePage` belongs in `ui/shell` because it provides the shared page frame. Its abstract nature is the implementation technique, not a reason to put it in a general abstraction directory.

The shell owns shared page framing, adaptive placement of page/player/navigation surfaces, system-area handling and playback clearance. Generic history, transitions and input helpers remain under `ui/navigation`. Modal and section frames remain with their own presentation families under `ui/structures`.

### Page toolbars and app navigation stay separate

`ui/shell/toolbars` owns actions and navigation for an individual page. [LibraryHeader](../lib/ui/shell/toolbars/library_header.dart) provides the styled title and supplied trailing actions. [DetailActionHeader](../lib/ui/shell/toolbars/detail_action_header.dart) provides the back link and optional actions, including back-only form, log and shuffle headers. Pages supply callbacks and choose the destinations.

`ui/shell/navigation` owns app-wide destination controls. [AppSideNavigation](../lib/ui/shell/navigation/app_side_navigation.dart) provides the desktop column. [AppBottomNavigation](../lib/ui/shell/navigation/app_bottom_navigation.dart) provides the compact row, height, safe-area padding and iOS glass treatment. Their base shares destination labels/icons, selected presentation, callback dispatch and surface styling.

[AdaptiveScaffold](../lib/ui/shell/adaptive_scaffold.dart) chooses and positions the app navigation beside the page and player. [HomePage](../lib/pages/home/home_page.dart) owns destination definitions, selected tabs, nested navigators and history. Page toolbars and app navigation do not import one another.

### The base page owns toolbar and content assembly

Every page supplies its pieces through `pageContent(context, assemble)`. The `assemble` callback belongs to the base page; it combines the optional `navbar` with a `PageBody` using the shared `PageLayout`. A page must not construct its own page-level `Scaffold`, `PageScrollView`, `CustomScrollView` or `SingleChildScrollView` to arrange those slots. Scrollable lists and other viewports inside a content component remain legitimate content responsibilities.

For example, a simple page supplies content without rebuilding the surrounding layout:

```dart
@override
Widget pageContent(BuildContext context, PageAssembler assemble) => assemble(
  context,
  navbar: const LibraryHeader(title: 'EXAMPLE'),
  body: const PageBody.slivers(
    slivers: [SliverToBoxAdapter(child: Text('Page content'))],
  ),
);
```

Reactive pages keep stream/listenable builders around this call and supply both slots from the same snapshot. Do not add separate copies of the same subscription just to render the toolbar and body independently. The base retains controller binding, framing and decoration ownership even when the slots are produced inside a reactive builder.

| Contract | Expected use |
| --- | --- |
| `PageToolbarPlacement.scrolling` | Default: the toolbar and body share one scroll position |
| `PageToolbarPlacement.fixed` | The toolbar occupies its natural responsive height above the remaining body viewport; works with or without an owned scaffold |
| `PageBody.slivers` | Lazy sliver content; the shared layout inserts the toolbar, common padding and overlay clearance |
| `PageBody.scroll` | Box content in a shared scroller; supports the same toolbar modes and optional keyboard clearance |
| `PageBody.box` | Bounded content such as a flex layout or the app shell; use fixed placement when supplying a toolbar |
| `navbarPadding` | Additional toolbar spacing; content and actions still use the shared toolbar families |

For scrolling bodies, `PageBody.padding` applies to the combined toolbar/content region. In fixed mode its top padding moves with the toolbar while its sides/bottom continue around the scrolling body. For a bounded box body, padding applies to the body itself. Playback top clearance appears before the toolbar and bottom clearance with the body exactly once; the form family also requests keyboard clearance. Fixed toolbar height is measured from its content instead of assuming every header is 56 pixels high.

Library, detail, liked, playlist, settings, statistics, shuffle and auth-form headers keep their scrolling behavior. Search and Logs retain fixed toolbars above their existing flexible content. Home supplies the app shell as a body without a page toolbar, and Splash likewise supplies a body without an empty toolbar placeholder. The independent app-navigation family remains assembled by `AdaptiveScaffold` around the current page and playback surfaces.

The standalone statistics composite also reuses `PageLayout`; the production statistics page supplies `StatsHeader` and header-free `StatsCardsContent` as separate slots. Reusable UI composites may share the layout implementation without becoming page classes or choosing app destinations.

## 5. Keep data and its related operations in one silo

All application and technical data definitions belong under `lib/data`: entities, immutable values, enums, settings, response records, controller-facing results, worker messages, native ABI records and mutable containers. Widget configuration, visual design tokens and purely visual state remain in UI.

Data-specific helpers can construct, parse, serialize, copy, validate, derive properties, query or mutate the data. Opening and saving data are also legitimate responsibilities in this silo. Katiby's [NotebookPage](../../katiby-app/lib/entities/notebook_page.dart), with metadata, serialization and `write()`, illustrates why a data object may contain relevant operations.

| Data area | Responsibility |
| --- | --- |
| `models/<subject>` | Data definitions, related enums, parsing/serialization, copying and small value helpers |
| `projections/<subject>` | Prepared/grouped snapshots and their construction rules |
| `queries/<subject>` | Searching, matching and data selection operations |
| `rules/<subject>` | Pure comparison, accounting and progress rules without I/O |
| `structures/<subject>` | Containers and their mutation/query methods, including caches and buffers |
| `configuration/<subject>` | Data configuration and reconstruction/opening of its store |
| `storage/<subject>` | File locations, schemas, migrations, persistence and CRUD operations |
| `files` | Reusable file-data operations such as hashing and deletion |
| `repositories` | Shared data access, account-scoped caches and reconciliation |

Keep a small helper with its data type when it naturally belongs there. Give substantial persistence or shared access a named store/repository module within data. Keep application-dependent preparation in a controller: it obtains the required values and supplies them to a result/snapshot constructor. A result model must not reach back into its consuming controller or runtime.

Within this silo, common data rules and operations also have shared owners. Related stores should use shared persistence and transaction mechanisms, and recurring parsing, comparison or mutation rules should be supplied by a shared helper/container where they have the same meaning. Subject-specific models and stores provide their particular values and operations. Assembly must preserve the existing database and transaction owner.

Download projections retain functional groups and status rules; flattened row entries, section captions and pixel spacing belong to download presentation in UI. Shared pause, track-alias/index and artwork-identity decisions have data-owned rules or structures consumed by both application and runtime. Persistent server trust belongs with authentication storage, while certificate enforcement remains infrastructure.

Each definition has one physical source home. A facade can re-export a public type without duplicating its implementation. Necessary technical dependencies are explicit: ABI records can use `dart:ffi`, worker messages can carry ports/tokens, and store configuration can reconstruct a store. Models do not navigate or operate audio/download engines.

## 6. Make independent components standalone

A file boundary should represent a responsibility someone can name. Prefer normal imports for independent models, parsers, buffers, adapters, controls and helpers. A component's first consumer does not own every module it uses.

Dart `part` files express an intentional shared private implementation boundary. Use them when private implementation access is necessary for one cohesive library. Every such component has an exclusive directory containing its entry point and its own private parts. Independent source must remain outside that entire tree.

Phonolite's audio organization makes the distinction concrete:

```text
data/models/audio/stream_settings.dart          # Standalone data
data/models/audio/raw_opus_event.dart          # Standalone event data
data/structures/audio/pcm_ring_buffer.dart      # Standalone container
infrastructure/audio/protocol/                # Standalone byte parsing
infrastructure/audio/output/                  # Output contract/factory
infrastructure/platform/audio/                # Native adapters/bindings
infrastructure/audio/engine/
  audio_engine.dart                           # Component entry point
  worker/                                     # Its private parts
  session/
  sources/
  seeking/
  buffering/
  pipeline/
  telemetry/
  testing/
```

Stream settings describe data, the Opus reader parses a protocol, and the ring buffer owns a mutable data structure. Their use by the engine does not make them private engine implementation. Import them normally from their respective source areas.

### Current private component boundaries

| Exclusive component directory | Entry point | Owns |
| --- | --- | --- |
| `application/app` | [app_controller.dart](../lib/application/app/app_controller.dart) | Shared application state and private session, library, collections, playback, preferences, statistics and download workflows |
| `infrastructure/audio/engine` | [audio_engine.dart](../lib/infrastructure/audio/engine/audio_engine.dart) | Worker/session ownership, sources, seeking, buffering policy, decoding, output pumping and telemetry |
| `infrastructure/downloads/client` | [offline_download_client.dart](../lib/infrastructure/downloads/client/offline_download_client.dart) | Client/actor lifecycle, correlation, planning, scheduling, transfers, snapshots and recovery |
| `data/storage/offline/library` | [offline_library.dart](../lib/data/storage/offline/library/offline_library.dart) | Shared database/schema, metadata, downloads/jobs, collections, managed files, relocation and deletion |
| `data/storage/listening_stats/database` | [listening_stats_storage.dart](../lib/data/storage/listening_stats/database/listening_stats_storage.dart) | Serialized SQLite worker and counter implementation |

Private responsibility objects can own their state while sharing the parent Dart library. Existing forwarding mixins preserve facade calls and virtual dispatch; keep forwarding free of behavior. Document cross-component coordination through the facade. Sharing library privacy does not make a part independently reusable, and an independent helper should not become a part just to fit a directory.

Splitting a file into parts only separates source text. It does not establish reusable abstractions or remove repeated behavior. An independently reusable structure or policy needs its own responsibility and extension contract outside a private component tree; the component then imports, implements or composes it. A policy shared only by private responsibilities within one cohesive library can remain a private owner there, such as the engine's local/remote output-configuration protocol.

## 7. Keep dependency direction explicit

| Source owner | Permitted project dependencies | Boundary |
| --- | --- | --- |
| Bootstrap | All areas needed to assemble the app | Other areas do not import bootstrap |
| Pages | UI, application capabilities, data values/projections and destination pages | No infrastructure or concrete data I/O imports |
| UI | Other UI modules, application APIs and data values/projections | No pages, bootstrap, infrastructure, concrete stores/repositories/file operations/storage configuration |
| Shared frames/toolbars/navigation | Generic UI helpers and presentation configuration supplied by consumers | No concrete feature-controller or feature-widget ownership; toolbar and app-navigation families remain independent |
| Application | Other application modules, data and infrastructure capabilities | No pages or Flutter widget/route/dialog dependencies |
| Data | Other data modules and necessary technical libraries; repositories can use infrastructure clients | No application, pages, UI or bootstrap dependencies |
| Infrastructure | Data definitions/helpers, technical libraries and other technical adapters | No application, pages or UI dependencies |

Avoid cycles between concrete libraries. The data-repository/client relationship is explicit: a repository may use an infrastructure client, while the client uses independent data models. A model must not depend on that repository's consuming runtime. Endpoint clients receive narrow callbacks for facade capabilities, rather than importing the facade that constructs them. Bind callbacks to the facade's methods so subclass overrides still dispatch normally.

Native-media adapters decode channel methods into typed requests and encode typed responses/snapshots. Their standalone contracts live in `data/models/playback`; application coordinators supply functional values and commands. Keep native method strings, response envelopes and platform discovery outside application workflows and the audio engine's exclusive part tree.

Controllers can use `flutter/foundation.dart` for notifications. They must not use `BuildContext`, `Navigator`, dialogs, widgets, `setState` or Flutter visual controllers. A shared data result can carry values and typed action information, with route construction remaining in the page.

## 8. Preserve runtime and resource ownership

Organization changes must preserve behavior, initialization order, cancellation and cleanup. Keep a single clear owner for each mutable state, timer, stream, worker, native handle, connection and transaction.

| Runtime boundary | Expected ownership |
| --- | --- |
| Server access | Endpoint clients share one `ApiTransport` for HTTP client, base URL, token, trust, session revision, retries and coalesced requests; payload/error records live in data |
| Audio | Engine owns worker communication/recovery; worker owns the active session; session owns output handles and cancellation; standalone parsers/containers remain outside the engine |
| Downloads | Application manager delegates runtime execution to the download client; actor/runtime owns initialization and disposal; messages/configuration/snapshots live in data |
| Offline persistence | Stores share the existing database pool and transaction boundary; splitting source must not open extra connections or split atomic operations |
| Listening persistence | The database component retains serialized worker and counter ownership |
| Views | Pages/components own their visual controllers and bound feature controllers; shared app state retains its existing application owner |

Create private state owners with their parent before subscriptions when scheduling order depends on that construction. Keep constructors free of externally visible I/O; explicit initialization starts workers and I/O. Preserve existing initialization and stream scheduling semantics during a move rather than silently changing them.

Audio adapters are constructed unopened and initialized by their owning session. Their disposal futures complete after native release, including an Android open still in flight. Engine shutdown waits for output-release and worker-retirement acknowledgments, with bounded forced retirement reserved for an unresponsive worker.

Cleanup must remain idempotent and awaitable where resources require it. Preserve request generations, stale-result guards, serialized writes, shared caches, account/server scoping, schema migrations, managed-path checks, deletion journals, partial-file recovery and worker command ordering. Public facade calls must retain subclass dispatch where the existing API relies on it.

When a lifecycle or execution protocol is common to a family, its shared owner must enforce it. Specialized implementations provide resource-specific work through that contract. Do not distribute copies of initialization, cancellation or cleanup policy across variants and rely on each to stay synchronized. Sharing an abstraction also does not require sharing a mutable instance: bootstrap or the parent assembly still determines the correct lifetime and number of instances.

## 9. Rationale from Katiby and Phonolite

Katiby is a neighboring reference project in this workspace. Its links provide concrete examples; Phonolite has no runtime dependency on it. These rules stand on their own when that project is unavailable.

| Evidence | Architectural decision | When it applies |
| --- | --- | --- |
| Katiby's `BasePage` supplies a frame while pages implement `navbar()` and `mainContent()` | Use explicit page assembly hooks in a shared shell frame | Pages share surrounding design but assemble different views |
| Katiby's base navbar/modal owns presentation while specialized classes provide content/actions | Define extensible families with named slots and stable outer layout | Members of a known family need consistent design as their specialized content evolves |
| [KatibyNotebookList](../../katiby-app/lib/widgets/layouts/list_views/katiby_notebook_list.dart) composes a generic list and named notebook tiles | Separate page, collection and item responsibilities into ordinary files | A page or collection becomes difficult to read as one widget tree |
| Katiby groups widgets by navigation, inputs, layouts, tiles, display, decoration and modals | Use names and directories that reveal the role; group features inside their owning source area | Choosing where a new component belongs or where shared presentation should be found |
| Katiby's data objects include relevant data helpers | Allow data and tightly related construction/persistence operations to stay in the data silo | A method describes or operates on its own data, rather than coordinating an app workflow |
| Phonolite separated pages from UI and lifted destination choices into pages | Keep complete view assembly separate from the components it consumes | A reusable UI component starts importing concrete pages or constructing feature routes |
| Phonolite placed page bases in the shell and separated page toolbars from app navigation | Place an abstraction by its responsibility and keep distinct navigation owners | Shared visual design tempts unrelated controls into one broad base |
| Phonolite feature controllers share lifecycle mechanics, and server endpoint clients compose one transport | Use shared implementation owners for functional structure and policy as well as presentation | Related operations need consistent notification, session, retry or cleanup behavior |
| Phonolite audio outputs implement a shared device contract | Separate the capability contract from platform-specific implementation and runtime assembly | A capability varies by platform while consumers require a consistent API |
| Phonolite moved stream settings/events and buffers outside the audio engine tree | Give independent data and helpers their own source home outside private component trees | A split component directory starts accumulating standalone files |
| Phonolite decomposed app/audio/download/database implementations into named owners | Split coherent responsibilities while preserving facade, state and resource ownership | A large file mixes lifecycles, data definitions and technical operations |

Katiby supplies useful presentation and composition patterns. Its mixed responsibilities in `Config`, some page workflows and the broad `entities` area are not a placement rule for Phonolite. Keep the explicit controller, data and infrastructure boundaries established here when applying those patterns.

The broader lesson is the relationship between general structure and assembled specialization. Phonolite should apply that relationship across its code and UI, not stop after reproducing Katiby's page, navbar or modal bases. The responsibility boundaries determine where a shared structure belongs; the abstraction determines what remains consistent; specialized implementations and composition determine what the app actually does and displays.

## 10. Add or refactor code using these rules

1. **Name the responsibility.** Identify its inputs, outputs, mutable state and resources. Place it in the owning source area before choosing a base class or file split.
2. **Identify the family and common decisions.** Find the relevant shell, control, workflow, controller, data operation/store or technical capability. State which structure, design, rules and lifecycle must be shared, and which parts vary.
3. **Use or establish the shared owner.** Extend or compose the existing abstraction. Where the family lacks one, extract the common implementation and define explicit hooks, parameters or capability contracts. Do this before adding another copied variant.
4. **Implement the specialization and assemble it.** Supply the particular content, actions, data rules or adapter behavior, then compose named pieces into the larger responsibility. Keep small private helpers beside their operation and independent components in standalone modules.
5. **Wire dependencies explicitly.** Pass values, child widgets, callbacks or injected capabilities. Keep page destinations out of UI components and functional work out of presentation bases.
6. **Preserve lifetime and behavior.** Retain defaults, layout/scrolling, public contracts, notification ordering, resource ownership, transaction boundaries and awaitable cleanup. Move an affected family together so common policy has one implementation.
7. **Update the architecture and its references.** Maintain this guide's responsibility maps, relevant module notes, imports/exports, tests and interaction catalogs when their ownership changes.
8. **Verify the shared contract and affected variants.** Use structural checks for ownership boundaries and targeted behavioral checks for the operations, interactions and lifetimes changed. Exercise meaningful differences between implementations as well as their shared behavior.

Use `snake_case` source paths and subject/role names that help a reader find the owner. Keep established public names when a source move alone is sufficient. Keep inheritance shallow and constructor APIs clear.

File length is a signal to inspect responsibilities. The current automated boundary is 1,000 lines per `lib` Dart file. Split a long operation into named suboperations, and extract modules when they have meaningful independent responsibilities. The target is readable ownership, rather than a prescribed number of lines or one file per function.

### Review expectations

- A reader can identify the shared structure, the permitted variations and the assembly without tracing duplicated implementations.
- Every member of a family uses its shared owner. A common design or policy change propagates through that owner instead of requiring synchronized edits to copies.
- Shared implementation contains the actual common decisions; a base class, interface or wrapper that leaves those decisions duplicated is insufficient.
- Specializations supply meaningful differences. Assembly code clearly names and connects those pieces rather than rebuilding their internals.
- Source placement, UI/controller separation, data ownership and resource lifetimes remain explicit. Abstraction must preserve those boundaries.

These are review requirements across all responsibility areas. Existing automated structural checks enforce only part of this architecture; passing them does not establish that a component has the right abstractions or shared design.

### Documentation and verification policy

This file is the single expected architecture and rationale. It contains the source-area map, extension contracts, current private component boundaries and decisions for future changes. Keep README files out of the entire `lib` tree. Put supporting module documentation under `docs` and link to this guide; document local code contracts in Dart documentation comments. Do not maintain a parallel architecture or a manually enumerated file-by-file catalog.

Structural checks under `test/architecture` verify import/export acyclicity, README exclusion, documented source areas, page/component separation, base-owned toolbar/viewport assembly, presentation/I/O and controller boundaries, independent toolbar/app-navigation families, the data silo, exclusive part-component trees and source size. Widget checks exercise extension hooks, fixed/scrolling placement, overlay/keyboard clearance, callbacks, responsive layout, navigation and controller disposal. Other tests cover server clients, storage, audio, downloads and asynchronous lifetimes. Keep tests meaningful to the behavior or boundary they protect.

Static analysis, compilation and headless verification are allowed. Application/device launches and server startup remain user-controlled.
