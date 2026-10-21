# Phonolite coding standards

This specification defines how Phonolite code should read: explicit responsibilities, small recognizable pieces, controlled state, and clear assembly through shared abstractions. The [expected architecture](expected-architecture.md) defines where those responsibilities belong and which dependencies they may have. Use both documents together.

The [iOS and Swift specification](ios-swift-specification.md) applies the same principles to the native Flutter host, Apple integrations and CarPlay, with Swift-specific language and lifecycle rules.

The [Windows native C++ specification](windows-native-specification.md) defines the corresponding C++ naming, header organization, resource ownership and Flutter/Win32 integration expectations.

The [macOS native specification](macos-native-specification.md) applies the shared Swift style to AppKit and defines the native C audio, sandbox, engine-binding and build expectations for the macOS host.

The [Android native specification](android-native-specification.md) defines Kotlin naming, member order, logical spacing, shared abstractions, component lifetimes and Flutter/media integration within Android's source structure.

The [Linux native C++ specification](linux-native-specification.md) adapts these expectations to GTK/GObject, C++14, GLib resource ownership, platform channels and Linux build/package boundaries.

These are expectations for new code and code being materially refactored. Existing source contains inconsistencies; publishing this specification does not imply that every file already conforms. Apply conventions within the affected responsibility, preserve behavior, and keep unrelated formatting or renaming out of a functional change.

## 1. Strategy and evidence

The central approach is to give each concept a named owner, define common decisions once, and assemble larger responsibilities from those pieces. A reader should see the contract first, follow a readable operation or composition, and inspect implementation details only when needed.

Katiby provides concrete examples of this approach:

| Observed pattern | Reference | Phonolite expectation |
| --- | --- | --- |
| Fields expose a component's inputs before its constructor and implementation. | [Notebook tile](../../katiby-app/lib/widgets/layouts/tiles/katiby_notebook_tile.dart), [modal text input](../../katiby-app/lib/widgets/inputs/modal_inputs/katiby_modal_text_input.dart) | Put the visible contract first; use explicit, typed inputs and sensible defaults. |
| Named controls combine into mode-specific groups and final assembly hooks. | [Notebooks navbar](../../katiby-app/lib/widgets/navigation/katiby_notebooks_page_navbar.dart) | Let method and component names explain the structure. Keep final assembly readable. |
| Shared bases own a frame; specializations supply narrow hooks. | [Ribbon base](../../katiby-app/lib/widgets/layouts/document_editor_ribbons/katiby_editor_ribbon_base.dart), [base modal](../../katiby-app/lib/widgets/modals/katiby_base_modal.dart) | Share design and behavior through an explicit extension contract. |
| Objects own their data and natural operations, with controlled changes. | [NotebookPage](../../katiby-app/lib/entities/notebook_page.dart) | Keep data rules and related operations together in the data silo; expose deliberate access and mutation. |
| Small objects own recurring mechanisms. | [ExpansionCoordinator](../../katiby-app/lib/utils/expansion_coordinator.dart), [TaskQueue](../../katiby-app/lib/entities/task_queue.dart) | Give a shared rule one owner instead of repeating its steps in callers. |
| Components distinguish resources they create from resources they borrow. | [Search bar](../../katiby-app/lib/widgets/inputs/katiby_search_bar.dart), [generic list](../../katiby-app/lib/widgets/layouts/list_views/katiby_list_view.dart) | Make initialization, dependency replacement and cleanup follow ownership. |

Katiby is the rationale, not a complete mechanical style template. Its quote style, import order, accessor grouping and lifecycle placement vary. The exact ordering and formatting rules below resolve those variations deliberately. Katiby's mixed-purpose globals, duplicated implementations, mutable collection exposure and incomplete async ownership are not requirements to reproduce. Phonolite's responsibility boundaries still apply.

## 2. Files, libraries and declarations

Name files and directories in `lower_snake_case`, using the responsibility or primary type: `stream_settings.dart`, `library_controller.dart`, `base_page.dart`. A file normally has one primary public concept. Keep its small private state class, adapters or tightly coupled helpers beside it when that makes the owner easier to understand.

Order a source file as follows, omitting sections it does not need:

1. Library documentation, annotations and a `library` directive, when needed.
2. Imports: `dart:` libraries, Flutter/third-party packages, then this app's packages. Separate these groups with one blank line and alphabetize paths within each group. Test-harness imports outside `lib`, when needed, form a final relative-import group.
3. Exports, in their own sorted section.
4. `part` directives belonging to this library.
5. Closely related constants, typedefs and enums needed to describe the public contract.
6. The primary public declaration, then its private state, adapters and helpers in reading order.

Use `package:` URIs for every import and export whose target belongs to a package's `lib` directory, including files in the same directory or cohesive family. Application source uses `package:phonolite_app/...`; another package uses its declared package name. This also applies to conditional imports and exports and to application imports from tests and integration code. Keep SDK imports as `dart:` URIs. The analyzer's `always_use_package_imports` rule flags relative primary imports inside `lib`; review export and conditional target URIs explicitly as well.

```dart
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/features/listening_stats/widgets/stats_presentation.dart';

export 'package:phonolite_app/ui/features/listening_stats/widgets/stats_cards_content.dart';
```

Test-only helpers under `test`, `integration_test` and `test_driver` are outside the package's `lib` namespace. Imports between those harness files may use relative URIs; their application imports still use `package:phonolite_app/...`. Keep production source independent of test harnesses, and do not import another package's private `src` implementation. See the [Dart library usage guidance](https://dart.dev/effective-dart/usage#libraries) for these language boundaries.

A part file begins with its `part of` directive; imports and exports belong to the owning library. Keep URI-based `part` and `part of` directives relative to their owning component, such as `part of 'audio_engine.dart';`. These directives join a shared library rather than importing an independent library. They retain the private-component boundary described by the architecture.

These import groups refine Dart's general directive ordering for this project. Naming and directive conventions follow [Effective Dart style](https://dart.dev/effective-dart/style); the separate app-package group is a project choice.

Use normal libraries for independently meaningful components. `part` is reserved for an implementation that deliberately shares one library's private scope. An exclusive component directory contains its owner and private parts; standalone data definitions, streams and reusable adapters belong outside that tree. See the [independent-component rules](expected-architecture.md#6-make-independent-components-standalone).

File boundaries follow responsibilities, not a requirement to put every function in its own file. Extract when a piece has a meaningful contract, independent reuse, its own state or lifecycle, or a substantial responsibility that obscures its owner. Keep a short single-owner helper local. Avoid dumping grounds such as `helpers.dart`, `common.dart` or an unrelated `utils` folder.

The existing automated boundary is 1,000 lines per `lib` Dart file. Treat approaching that boundary as a reason to inspect responsibilities, not a target size. A shorter file can still hold too many responsibilities.

## 3. Ordering members inside a type

Use the following default order. Omit empty groups; do not add section banners to mark them.

| Order | Members | Reading purpose |
| --- | --- | --- |
| 1 | Static constants and shared immutable class values | Common definitions used by this type |
| 2 | Final inputs, configuration, callbacks and injected dependencies | What an instance receives |
| 3 | Private mutable state and owned resources | What an instance manages |
| 4 | Constructors: unnamed, named, then factories | How a valid instance is created |
| 5 | Accessors, with each getter/setter pair adjacent | What consumers can observe or assign |
| 6 | Initialization, lifecycle and shutdown methods, grouped in lifecycle order | When the owner becomes usable and releases resources |
| 7 | Public operations and protected extension contracts, grouped by responsibility | What the type does or lets a specialization provide |
| 8 | Private operations and presentation helpers, from small pieces to larger groups | How the contract is implemented |
| 9 | Final `build` or equivalent top-level assembly hook | How the named pieces form the result |

Keep related behavior together rather than alphabetizing every member or separating all public methods from every private helper. A shared template's extension hooks form one contract: keep them together before its implementation, even when that mixes getters and methods. A specialization's final content/assembly hooks belong at the end, in the order their regions appear.

For common type families, apply the order this way:

- **Widget configuration:** final inputs, constructor, then `createState()` for a stateful widget. A stateless widget places helpers before its final `build` or shared-base content hook.
- **Widget state:** fields and accessors; `initState`, `didChangeDependencies`, `didUpdateWidget`, other applicable lifecycle hooks, then `dispose`; event handlers and presentation helpers; final assembly. Implement only lifecycle hooks that do work.
- **Controller or runtime owner:** dependencies and state; construction; observable access; initialization/cleanup; commands; implementation helpers. Keep one operation's workflow legible from top to bottom.
- **Data type:** fields; constructors and decoding factories; accessors; natural data operations, copying and serialization; private helpers; equality, `hashCode` and `toString` together at the end when provided. These related protocol members are an exception to the default accessor position.
- **Enum or extension:** values first where applicable, then fields/constructor and related operations. Keep a small extension's members in coherent reading order; do not manufacture empty categories.

Mutable static state needs a specific ownership reason and belongs with the state it represents. Do not add mutable globals just to simplify access. When reordering existing code, preserve field-initializer evaluation order, lazy initialization, constructor behavior and dispatch.

Constructor parameters follow the same conceptual order as the fields: Flutter `key` first, required inputs/dependencies and required callbacks, then optional configuration and optional callbacks. Keep closely related values together within those groups. Prefer named parameters for multi-input APIs; a simple one-value wrapper may use a positional parameter. At call sites, follow the same semantic order and place a primary `child`, `children` or builder last when the API permits it.

Use initializing formals and `super` parameters when they make the mapping clear. Constructors establish local invariants synchronously. Put I/O and multi-step startup behind an explicit asynchronous operation or factory. Use assertions for developer contract mistakes; validate untrusted data with runtime checks that also operate in release builds.

## 4. Formatting and spacing

Use the Dart formatter from the repository's Flutter SDK. It owns two-space indentation, wrapping, ordinary spacing and trailing-comma layout. The project configures a 120-column target with automatic trailing commas in [analysis_options.yaml](../analysis_options.yaml), allowing more method and function signatures to fit on one line. This target applies throughout the source, including calls and widget expressions; long signatures still wrap. Do not hand-align fields or force a different layout with padding or routine formatter suppression. Long strings and URLs can exceed that target. See [Dart formatting](https://dart.dev/tools/dart-format) and [formatter configuration](https://dart.dev/tools/analysis).

Keep the project formatter configuration explicit:

```yaml
formatter:
  page_width: 120
  trailing_commas: automate
```

Prefer compact method and function signatures when the formatter can fit them within this target. Let longer signatures wrap naturally; do not shorten meaningful names, remove useful types or suppress formatting to keep a declaration on one line. Automatic trailing commas allow short declarations and calls to collapse again when they fit. Do not switch to comma preservation or add per-file width overrides merely to force a different layout.

The following choices make spacing predictable:

- Use one blank line between methods, constructors and logical member groups. Keep related field declarations compact. Keep a simple getter/setter pair adjacent, with one blank line between the two declarations.
- Separate logical blocks inside an operation with one blank line, following the [vertical spacing rules](#logical-blocks-and-vertical-spacing).
- Keep documentation and annotations immediately attached to their declaration. Use one annotation per line for ordinary declarations.
- Use single-quoted strings by default. Use double quotes when they avoid escaping an apostrophe, and triple quotes for real multiline text. Do not change an established serialized value merely to satisfy a visual preference.
- Use braces for control-flow bodies, including a one-line guard return. Use an arrow body for a clear single expression or delegation.
- Use a ternary for a small, obvious choice. Replace nested ternaries with named decisions, `if` statements or a suitable `switch`.
- Let the formatter decide trailing commas and wrapping within declarations and expressions. Choose the blank lines between statement groups deliberately. Do not use repeated separators or comment banners as substitutes for names and smaller responsibilities.
- Remove trailing whitespace and finish text files with a newline.

Formatting should make the structure visible without requiring manual maintenance. Do not mix a broad formatting pass into an unrelated behavior change.

Fluent builder configuration has one deliberate layout exception: keep each configuration call on its own line. When the formatter would collapse that chain, use paired `// dart format off` and `// dart format on` comments around only the affected setup, as shown in the builder example. Keep the rest of the file formatted normally.

Run formatting from the app package root, the directory containing `pubspec.yaml`. The formatter reads the project configuration automatically:

```powershell
# Format all application source under lib.
dart format lib

# Format an individual source file.
dart format lib/ui/shell/base_page.dart

# Check formatting without changing files.
dart format --output=none --set-exit-if-changed lib
```

Format affected Dart files before completing a change. Include tests or other Dart source paths when they are part of the change. The check command returns zero when formatting is current and one when changes would be needed; use the same check in automated verification when formatting is enforced there.

Editor format-on-save is optional and must use the same Dart formatter and project configuration. In VS Code, merge this entry into the workspace `settings.json`:

```json
{
  "[dart]": {
    "editor.formatOnSave": true
  }
}
```

### Logical blocks and vertical spacing

Write statement bodies as logical paragraphs. A paragraph is a small group of statements that completes one recognizable step: validate inputs, obtain a value, prepare a request, perform an operation, update state or produce a result. Use exactly one blank line when the purpose changes. These boundaries are part of the coding standard, even when several statements would fit compactly together.

Apply these rules within methods, functions, callbacks and nested statement bodies:

| Boundary | Spacing rule |
| --- | --- |
| Local declarations | Keep declarations for the same step together. Separate that group from the next step that uses its values. A lookup and its immediate null check may stay together when they form one small obtain-and-validate step. |
| Guard clauses | Separate each independent guard from the next guard or the normal execution path. Keep a simple guard's `return`, `throw` or `continue` directly inside its body. |
| Control-flow blocks | Put a blank line between independent sibling `if`, loop, `switch` or `try` blocks, and between a completed block and the following work. Keep `else if`/`else`, `catch`/`finally` and the closing `while` of a `do` loop attached to their own construct. |
| Workflow stages | Separate preparation, execution, state updates, notifications and result assembly when they are distinct steps. Related assignments, setter calls and a notification may stay together when they complete one small state change. |
| Final result | Put a blank line before a final `return` or `throw` that follows earlier work in the same body. This does not add padding inside a simple guard or a body containing only that statement. |
| Local function definitions | Separate each local function declaration from other declarations and executable statements with one blank line before and after it, wherever there is neighboring content. |

For example, related input declarations form one paragraph, each guard forms another, and the successful result has its own boundary:

```dart
String trackLabel(String rawTitle, {String? rawArtist}) {
  final title = rawTitle.trim();
  final artist = rawArtist?.trim();

  if (title.isEmpty) {
    return 'Untitled';
  }

  if (artist == null || artist.isEmpty) {
    return title;
  }

  return '$artist — $title';
}
```

Keep the statements inside a single small step contiguous. Do not put a blank line after every assignment, add empty lines immediately inside braces or stack several blank lines. Comments belong directly above the paragraph or statement they explain; documentation and annotations stay attached to declarations. Class fields still follow their logical member groups, and separate methods and constructors still have one blank line between them.

These rules govern statement and member boundaries. Argument lists, collection literals and widget expressions retain formatter-controlled layout; use named components and helpers to reveal their larger responsibilities. If a method has many substantial paragraphs, inspect whether some steps deserve named operations rather than relying on whitespace alone.

The formatter handles layout but does not identify changes of purpose or insert all required paragraph boundaries. Review vertical spacing explicitly when changing code; a successful formatting check does not establish that logical blocks are separated clearly.

## 5. Naming, signatures and visible contracts

Use `UpperCamelCase` for types and `lowerCamelCase` for members, variables, enum values and constants. Use familiar acronyms as words: `albumId`, `httpClient`, `AudioApi`. Match a primary type's filename to its name. A private widget state is named for its owning widget, not a copied predecessor.

Names should describe domain concepts and operations: `StreamSettings`, `renamePlaylist`, `cancelDownload`, `selectedTrackIds`. Avoid vague names such as `manager`, `data`, `obj`, `handle` or `process` when a more specific responsibility is known. Use full words such as `Button` in new names rather than inventing abbreviations. Short loop variables are fine when their meaning is immediately local.

Use `is`, `has`, `can` or `should` for booleans where natural; conventional Flutter names such as `enabled` and `selected` are also clear. Name intent callbacks `onSelect`, `onRename` or `onCreatePlaylist`. Name change notifications for the result they report, such as `onTitleChanged`. Do not make a callback name imply that work has completed when it only requests an action.

Give declarations explicit parameter and return types, including private helpers. Prefer typed callbacks such as `VoidCallback`, `ValueChanged<T>` or a descriptive typedef over raw `Function`. Use `Future<void>` when callers can await completion. Avoid `dynamic` as a substitute for modeling; accept `Object?` at genuinely untyped boundaries and validate or decode it there.

Infer obvious local types and prefer `final` when a binding is not reassigned. Use `const` for values and constructors that support it. Use `late` only when delayed initialization is an actual invariant, not to silence null-safety errors. Do not use `!` to bypass uncertainty that should be modeled or checked.

Widget helpers do not all need a `_build` prefix. `_renameButton`, `_selectionActions` and `_emptyState` can describe presentation pieces directly; `_confirmRemoval` describes an action. Use a consistent convention within the family, and avoid renaming an established API purely to change its prefix.

## 6. Encapsulation and data access

Expose the smallest useful contract. Inputs and simple immutable data may be public `final` fields. Do not add a private field plus a trivial getter merely to hide a value that has no access policy. Keep mutable implementation state private when writes must enforce validation, notifications, synchronization or lifetime rules.

In Dart, a leading underscore makes a name **library-private**, not class-private. The primary file and its parts share that privacy scope. Other classes in that library can still access it. Choose library boundaries accordingly; see [Dart libraries and imports](https://dart.dev/language/libraries).

Getters are synchronous observations of state or inexpensive derived values. Keep I/O, mutation and meaningful work behind named methods. A property setter is appropriate for an ordinary assignment with a local invariant or notification. Use a command such as `renamePlaylist` when the operation can fail asynchronously or coordinates several responsibilities.

For example, a local title object can own its notification policy:

```dart
class EditableTitle {
  final void Function(String)? _onChanged;

  String _value;

  EditableTitle({required String value, void Function(String)? onChanged}) : _onChanged = onChanged, _value = value;

  String get value => _value;

  set value(String nextValue) {
    if (nextValue == _value) {
      return;
    }

    _value = nextValue;
    _onChanged?.call(nextValue);
  }
}
```

The callback is an explicit dependency; mutation and notification happen in one place. This example illustrates controlled local state, not a requirement to wrap every string in a class.

A `final List<T>` or `final Set<T>` prevents replacing the reference; it does not make the contents immutable. Do not expose a mutable backing collection accidentally. Choose deliberately between a defensive snapshot, an unmodifiable live view and a documented mutable collection owned by the caller. Remember that an unmodifiable collection can still contain mutable objects.

Data-owned serialization, copying, validation and supported open/save operations belong with the data responsibility. Controllers coordinate user-facing workflows; infrastructure supplies platform and transport mechanisms. A data method should not acquire UI context, navigate or assemble widgets. Follow the [data ownership rules](expected-architecture.md#5-keep-data-and-its-related-operations-in-one-silo).

### Models and local records

Use named model classes for domain concepts and shared contracts. Keep their natural validation, calculations and data operations on the model. Use named-field records for small local groupings and private helper results; their field names should explain each value without positional access such as `$1`. A reused domain concept belongs in a model even when it currently has only two fields. A type alias can shorten a record signature, but does not create a distinct nominal type. See [Dart records](https://dart.dev/language/records).

This shared model owns its simple derived value:

```dart
class DownloadProgress {
  final int completed;
  final int total;

  const DownloadProgress({required this.completed, required this.total});

  int get remaining => total - completed;
}
```

A presentation formatter can use a local record without adding another shared model:

```dart
String formatCompletionCounts(List<bool> outcomes) {
  final counts = (completed: outcomes.where((completed) => completed).length, total: outcomes.length);

  return '${counts.completed}/${counts.total}';
}
```

### Nullable updates

For nullable model properties, `copyWith` uses three distinct meanings: an omitted argument keeps the current value, explicit `null` clears it, and a supplied value replaces it. Non-nullable properties cannot be cleared. Keep this distinction inside the model's copying implementation rather than asking each caller to reproduce it.

```dart
import 'package:phonolite_app/data/models/library/track.dart';

List<Track> copyExamples(Track track) => [
  track.copyWith(), // Keep the current album ID.
  track.copyWith(albumId: null), // Clear the album ID.
  track.copyWith(albumId: 'album-1'), // Replace the album ID.
];
```

Use an omission sentinel or another explicit update mechanism that preserves these call semantics. A sentinel is an implementation detail; compare it with `identical` in new implementations and validate supplied values before accepting them. Keep ordinary fields and other public operations strongly typed.

Existing APIs must be migrated deliberately. `Track`, `Artist`, `AuthState` and `PlaybackState` distinguish omission from clearing for nullable fields. Callers that intend to keep missing telemetry explicitly retain the current value; callers that intend to clear an error pass `null`. Any further contract migration must include the affected callers and behavior checks.

### Equality by responsibility

Choose equality for the concept being modeled:

- Value objects compare their meaningful contents and implement `==` and `hashCode` together.
- Entities expose named identity and metadata comparisons where those are different questions, such as `hasSameIdentity` and `hasSameMetadata`. State which identifiers and scope define identity.
- Controllers, services and resource owners retain instance identity unless a specific contract requires otherwise.

For example, a closed value type can compare its complete format:

```dart
final class AudioFormat {
  final int sampleRate;
  final int channels;

  const AudioFormat({required this.sampleRate, required this.channels});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioFormat && sampleRate == other.sampleRate && channels == other.channels;

  @override
  int get hashCode => Object.hash(sampleRate, channels);
}
```

Define whether collection comparisons concern identity, ordered contents or unordered membership. Keep equality/hash inputs stable while an object is a map key or set member. Preserve existing comparisons when replacing a record with a model: records have structural equality, while a new class uses instance equality until an appropriate contract is implemented. See the [Dart equality contract](https://api.dart.dev/dart-core/Object/operator_equals.html).

## 7. Readable operations and shared behavior

An operation should read in the order its work happens: validate, obtain what it needs, perform named steps, publish the result, and release owned temporary resources. Use guard clauses to keep the successful path clear. Choose names and local values that explain the decisions instead of leaving the reader to decode long boolean expressions.

Extract a helper when it names a meaningful suboperation, isolates a policy or boundary, removes repeated decisions, or makes the parent workflow readable. Keep the overall sequence visible in the parent. Do not split every statement into a method or force one source file per function. Use a method tear-off for direct delegation when the signature fits. Keep an inline lambda for simple argument adaptation; give branching, multi-step and asynchronous event handling a named handler with a clear completion/error policy. Use explicitly typed local function declarations for meaningful named local operations.

Share a repeated **decision or responsibility**, not merely matching lines. Before creating another layout, state transition, storage sequence or cleanup mechanism, look for its existing owner. Extend that owner or introduce a focused shared abstraction when the family has a stable common rule.

A shared abstraction owns the common structure, defaults, design and behavior. Its extension contract exposes only genuine variation. Implementations provide those differences, and composition wires them together. Consumers should not repeat the base's sequence or override its entire assembly to change one detail.

Choose the smallest mechanism that expresses the contract:

- A function for a stateless transformation or operation with explicit inputs.
- A composed object for a reusable policy or capability with dependencies or state.
- A widget for a presentation concept with its own contract, reuse or lifecycle.
- An abstract base/template when variants share stable assembly and provide narrow hooks.
- A mixin for a cohesive capability that genuinely fits multiple hosts and has explicit host requirements.

Do not create an empty base class, universal manager or generic framework only to make unrelated types look uniform. Consistency means that related decisions have a shared owner; it does not require identical class shapes across unrelated responsibilities. See the architecture's [shared-structure guidance](expected-architecture.md#3-use-shared-extensible-structures).

### Named decisions and exhaustive state handling

Express a complete decision over an internal enum or sealed family through a named helper and an exhaustive switch. List the meaningful cases explicitly so a new variant exposes the places needing an update. Use ordinary `if` statements and guards for workflows. Pattern matching should make a decision clearer; keep complex nested destructuring out of final assembly.

```dart
import 'package:phonolite_app/data/models/auth/auth_state.dart';

String sessionLabel(SessionStatus status) => switch (status) {
  SessionStatus.offline => 'Offline',
  SessionStatus.checking => 'Checking connection',
  SessionStatus.serverReachable => 'Server available',
  SessionStatus.serverUnavailable => 'Server unavailable',
  SessionStatus.authenticated => 'Signed in',
};
```

Handle unknown external values explicitly while decoding them at the boundary. An intentional fallback for external input has a different purpose from a catch-all that conceals an unhandled internal state. See [Dart branches](https://dart.dev/language/branches).

### Functional collection transformations

Prefer short, pure `where`/`map` chains for filtering and projecting collections. Give the operation and callbacks meaningful names when their purpose needs explanation. Materialize the result where a snapshot is required:

```dart
import 'package:phonolite_app/data/models/library/track.dart';

List<String> likedTrackIds(Iterable<Track> tracks) =>
    tracks.where((track) => track.liked).map((track) => track.id).toList();
```

Use ordinary loops for substantial branching, mutation, side effects or sequential awaited work. A collection transformation should not conceal a workflow. Collection `if` and spreads remain useful for assembling named UI groups, such as `[...defaultActions(), if (isEditing) ...editingActions()]`; extract substantial group construction into its own component or helper.

Lazy iteration defers work and can repeat it on another iteration. Take a snapshot before mutating its source or crossing an ownership boundary that requires stable data. `toList(growable: false)` fixes the list's length while still allowing element replacement; choose an unmodifiable result when mutation must be prevented. See [Dart collections](https://dart.dev/language/collections) and [`Iterable.toList`](https://api.dart.dev/dart-core/Iterable/toList.html).

### Typed shared families

Use generics when a coherent family shares structure or behavior across different item types. The shared abstraction receives typed inputs and typed builders; a concrete feature wrapper supplies its models, content and actions. Add meaningful bounds when a type parameter requires a capability. Avoid raw types and casts that hide an incomplete contract. Use a typedef where it names a useful recurring contract, rather than introducing an alias for every callback.

The existing `CollectionSliver<T>` owns collection layout and accepts a `CollectionItemBuilder<T>` whose arguments are context, the item and list/grid mode. A small example supplies track content without rebuilding its layout:

```dart
import 'package:flutter/material.dart';

import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/ui/structures/collections/collection_sliver.dart';

Widget trackNames(List<Track> tracks) => CollectionSliver<Track>(
  items: tracks,
  isListView: true,
  itemBuilder: (context, track, isListView) => Text(track.title),
);
```

Real feature wrappers supply the appropriate shared row/card components and feature actions. Keep the generic family focused on its common responsibility. See [Dart generics](https://dart.dev/language/generics) and [type aliases](https://dart.dev/language/typedefs).

### Setters and fluent builders

Individual property setters remain valid for deliberate changes to an object. A shared builder may also provide fluent configuration methods, each returning the same builder, with calls written on separate lines and a terminal `build()` producing the result. Prefer these forms over cascades for configuration.

For an external type such as `Paint`, fluent methods can live on a builder while ordinary setters remain available on the finished object. The builder owns common defaults and construction rules. Its `build` implementation can use ordinary assignments:

```dart
import 'package:flutter/material.dart';

class PaintBuilder {
  Color? _color;
  double? _strokeWidth;

  PaintBuilder color(Color value) {
    _color = value;

    return this;
  }

  PaintBuilder strokeWidth(double value) {
    _strokeWidth = value;

    return this;
  }

  Paint build() {
    final result = Paint();
    final color = _color;
    final strokeWidth = _strokeWidth;

    if (color != null) {
      result.color = color;
    }

    if (strokeWidth != null) {
      result.strokeWidth = strokeWidth;
    }

    return result;
  }
}

PaintBuilder paint() => PaintBuilder();

// dart format off
Paint configuredPaint(Color accent) => paint()
    .color(accent)
    .strokeWidth(2)
    .build();
// dart format on

void updatePaint(Paint result, Color accent) {
  result.color = accent;
  result.strokeWidth = 2;
}
```

Builder methods may also be called as individual statements. Keep builder configuration local and synchronous; asynchronous workflows use explicit awaited steps. Give a shared builder a real configuration responsibility, and document whether repeated `build` calls return independent objects. The example preserves unspecified SDK defaults and creates a fresh `Paint` per call. Existing cascades can be migrated within relevant refactors while preserving mutation order and ownership.

## 8. Extension contracts and Dart modifiers

Document what a hook supplies, when it is called, which owner manages its resources, and whether overriding code must call `super`. Hooks intended for subclasses in other libraries must use non-underscore names. Use `@protected` for those hooks and `@override` on implementations.

Use `@nonVirtual` on implemented assembly members that specializations should not replace, and `@mustCallSuper` where correctness depends on the inherited work. These are analyzer-supported contracts, not runtime access restrictions; use structural boundaries and tests for invariants that need stronger protection. See the [`protected`](https://pub.dev/documentation/meta/latest/meta/protected-constant.html), [`nonVirtual`](https://pub.dev/documentation/meta/latest/meta/nonVirtual-constant.html) and [`mustCallSuper`](https://pub.dev/documentation/meta/latest/meta/mustCallSuper-constant.html) contracts.

Choose language modifiers intentionally within the SDK range declared in `pubspec.yaml`:

| Modifier or form | Use when |
| --- | --- |
| `abstract class` | A non-instantiable shared contract or template has incomplete behavior. |
| `abstract interface class` | Consumers should implement a capability without inheriting its implementation. |
| `base class` / `abstract base class` | External subtypes must inherit the implementation, with Dart's corresponding subtype restrictions. |
| `final class` | Subtyping outside the library is intentionally prohibited. |
| `sealed class` | A deliberately closed family of direct subtypes in the same library supports exhaustive handling. |

These modifiers control different extension permissions. Do not apply `base`, `final` or `sealed` to every type by habit or change an existing extension surface without checking its consumers. Dart's [class modifier reference](https://dart.dev/language/class-modifiers) defines the exact restrictions.

### Extension methods on external types

Put natural behavior directly on classes the project owns. Use focused Dart extension methods for useful conveniences on external types, such as SDK `Duration` or Flutter `BuildContext`. Place them with the responsibility they serve; display formatting belongs with presentation helpers.

```dart
extension PlaybackDurationFormatting on Duration {
  String toPlaybackLabel() {
    final minutes = inMinutes;
    final seconds = (inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }
}
```

Dart extension methods are statically resolved conveniences. Shared extensible structures such as `BasePage` instead use explicit inheritance/composition contracts. Keep state, dependency ownership and polymorphic hooks in their owning types. See [Dart extension methods](https://dart.dev/language/extension-methods).

Private implementations also use ordinary methods or explicit composed owners. For example, `_ListeningCounterStore` borrows its owning `_ListeningDatabase` and shares its connection and transaction boundary. Splitting this implementation must preserve that ownership; it does not call for an extension on the database class.

## 9. UI pieces and final assembly

Presentation code receives values and typed callbacks. It owns layout, visual state, focus, animation, local input and framework integration. Controllers own feature functionality and long-running application operations. A UI handler may collect input and delegate a command; it should not reproduce the command's algorithm or storage sequence.

Build recognizable pieces first, group them by purpose, then assemble the final view. A small single-owner region can be a private method. Give a reusable region or one with independent state/lifecycle a widget and an explicit contract. Avoid a large `build` full of unrelated conditions and anonymous callbacks; also avoid helpers that only rename a single obvious expression without improving understanding.

**Actively reduce excessive widget nesting through encapsulation and reuse.** When a subtree obscures the page outline, mixes several recognizable regions or embeds decisions and handlers inside layout, extract a named region or component. Keep short layout wrappers together when they express one coherent piece. A component's responsibility and reading clarity determine the boundary; there is no arbitrary maximum nesting depth. Final `build`/`pageContent` assembly should reveal the view's main regions and their relationships.

Keep multi-step callbacks in named handlers on the appropriate owner. Presentation handlers coordinate UI steps and delegate feature operations to controllers. For example, this control keeps its two UI callbacks outside its assembly:

```dart
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';

class SelectionAction extends StatelessWidget {
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const SelectionAction({super.key, required this.onSelect, required this.onClose});

  void _selectAndClose() {
    onSelect();
    onClose();
  }

  @override
  Widget build(BuildContext context) => TechButton(label: 'Open', onTap: _selectAndClose);
}
```

Use a `Future<void>` callback contract when the consumer must await completion. A closure that captures a controller, context or other resource must respect that owner's lifetime; moving it into a named handler does not change those obligations.

Use shared controls, theme tokens, surfaces and layout structures. Put recurring spacing, typography, interaction states and responsive rules in the shared design owner. Specializations select supported variants instead of restating colors, borders, dimensions or disabled behavior at every call site. Truly local layout decisions may remain local until they form a shared rule.

This small example assembles existing shared components without copying their design:

```dart
import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/tech_button.dart';
import 'package:phonolite_app/ui/shell/toolbars/library_header.dart';

class LibraryHeading extends StatelessWidget {
  final String title;
  final VoidCallback? onRename;

  const LibraryHeading({super.key, required this.title, this.onRename});

  Widget _renameButton() => TechButton(label: 'Rename', onTap: onRename);

  @override
  Widget build(BuildContext context) => LibraryHeader(title: title, trailing: _renameButton());
}
```

The order is visible inputs, construction, named control and final assembly. The example demonstrates the reading pattern; it does not require a wrapper for every use of `LibraryHeader`.

Pages use the [shared page contract](../lib/ui/shell/base_page.dart) rather than building their own frame. Supply navbar and body through `pageContent` and its `PageAssembler`, using the appropriate `PageBody.box`, `PageBody.scroll` or `PageBody.slivers` form. The base owns their assembly, fixed/scrolling toolbar placement and common framing. Form pages use their shared form-family hooks. App destination navigation stays in the shell, distinct from page toolbar actions. Do not override the common `build` to bypass those responsibilities.

## 10. Async work, errors and resource lifetime

The API must say what completion means. Await the work an operation promises to finish, return its `Future`, or explicitly document that the operation only schedules work and provide a way to observe the eventual result. Do not label a save operation complete before the required write finishes.

Use `Future<void>` for asynchronous commands; do not declare `async void` methods. An ordinary Flutter `VoidCallback` does not require an `async void` declaration: it can delegate to a separately awaitable `Future<void>` operation. When the framework does not await the callback, handle asynchronous failures at that boundary. Use `unawaited` only for deliberately detached work whose errors and lifetime are handled. It is not a replacement for required cleanup or persistence.

For state that genuinely uses streams, expose a read-only current snapshot plus a typed changes stream. One-off commands remain awaitable operations:

```dart
import 'dart:async';

import 'package:phonolite_app/data/models/downloads/offline_download_snapshot.dart';

abstract interface class DownloadStateSource {
  OfflineDownloadSnapshot get current;

  Stream<OfflineDownloadSnapshot> get changes;

  Future<void> refresh();
}
```

The current snapshot supplies immediate observation; the changes stream reports subsequent updates. This contract does not imply initial emission, replay or an atomic snapshot subscription. State whether the stream supports multiple listeners, how current-state reads relate to subscription, which errors are emitted, and who closes it. Existing `ChangeNotifier`/`ControllerBinding` feature controllers keep their notification mechanisms; this stream rule applies where a stream is the appropriate capability.

Choose sequential, latest-result or concurrent event processing according to the operation's contract. An `async` callback passed to [`listen`](https://api.dart.dev/dart-async/Stream/listen.html) does not by itself serialize future events. Use `await for` or another explicitly ordered mechanism when each event must finish before the next is processed. Cancellation, generation invalidation and timeouts have distinct meanings; ignoring stale results or applying [`Future.timeout`](https://api.dart.dev/dart-async/Future/timeout.html) does not stop the underlying work automatically.

Use `sync*` for intentionally lazy synchronous sequences and `async*` for streamed asynchronous sequences. Keep their deferred execution, errors and cancellation behavior explicit; materialize a stable snapshot when callers need one. Follow [Dart stream contracts](https://dart.dev/libraries/async/using-streams).

Catch errors where the owner can recover, translate them into a meaningful result, or report an actionable failure. Preserve useful stack traces when propagating errors. Do not silently catch every exception or return a success-shaped default after a failed required operation. A best-effort fallback must be intentional, narrowly scoped and documented where it is surprising. Keep user-facing messages in the presentation/application boundary and diagnostic details in the appropriate logging owner.

The creator owns disposal unless ownership is explicitly transferred. Borrowed controllers, focus nodes and services stay owned by their provider. Remove listeners, cancel subscriptions and timers, and release native handles when their owner ends. If a widget supports replacing a borrowed dependency, detach from the old value and attach to the new one in `didUpdateWidget` as needed.

Use `try`/`finally` or a shared ownership helper for temporary resources that must be released on success and failure. Keep cleanup idempotent where it may be requested more than once. Respect established shutdown ordering and subclass dispatch when extracting shared behavior.

Flutter [`State.dispose()`](https://api.flutter.dev/flutter/widgets/State/dispose.html) is synchronous. When shutdown requires awaited work, provide an asynchronous owner boundary and await it at the appropriate lifecycle level; a UI callback cannot make synchronous disposal wait.

After an async gap, check the relevant `BuildContext.mounted` before using that context, or `State.mounted` when using that state's own context or updating its state. A guard on a different owner does not protect the context being used. Handle stale results/cancellation according to the operation's owner. See Flutter's [`BuildContext.mounted` contract](https://api.flutter.dev/flutter/widgets/BuildContext/mounted.html) and the architecture's [runtime ownership rules](expected-architecture.md#8-preserve-runtime-and-resource-ownership).

## 11. Documentation, verification and adoption

Use `///` documentation for public contracts whose meaning is not obvious from their signature: invariants, units, ownership, completion guarantees, errors, defaults and extension hooks. Link related types and members with Dart documentation references where possible. Explain a consequential implementation decision with a short comment about why it exists.

Do not narrate obvious syntax, keep stale commented-out code, label a component as “new”, or accumulate a change history in implementation comments. Put the current contract in code documentation and project-wide expectations in these guides. Keep README files out of the entire `lib` tree; supporting module documentation belongs under `docs`.

For a new or refactored responsibility, review the following:

1. Its location, name and dependencies match the architecture; independently meaningful pieces are outside private part trees.
2. Its inputs, state, construction and operations appear in a predictable reading order; logical paragraphs visibly separate changes of purpose.
3. Its shared behavior/design has one owner, and final assembly reads through named pieces and narrow contracts.
4. Mutable state and collections have deliberate access rules; async completion and resource ownership are clear.
5. Formatting and static analysis pass for affected code, and relevant behavioral checks cover material changes.

Use the repository's Dart/Flutter SDK to format and analyze affected files. Run focused tests appropriate to the changed behavior and required architecture checks; the [test index](../test/README.md) identifies existing suites. Tests should verify meaningful behavior and contracts, not merely mirror helper extraction or member order. Documentation-only changes need link, example and consistency checks rather than an application launch.

Do not start applications, servers or background services for verification. Compilation and static verification are allowed; the user owns launching the software. Respect this rule even when a usual development workflow would start a preview.

The analyzer currently includes `flutter_lints`; it does not mechanically enforce every convention in this document. Naming, contract boundaries, assembly quality and member grouping also require review. Change lint policy separately when there is a concrete enforcement benefit, and do not suppress a warning without understanding and documenting its reason.

Apply the specification as a coherent improvement within the work being changed. Preserve public APIs and serialized formats unless a migration is part of the task. Do not move initializers, change callback timing, expose state or alter cleanup merely to make a file look ordered. The standard is successful when the code is easier to read and reuse while its responsibilities and behavior remain clear.
