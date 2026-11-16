# Phonolite engineering standards

This is the single standard for how Phonolite source is structured and written. It covers the Flutter application under `lib/` and the handwritten native hosts for iOS, macOS, Android, Windows and Linux. It describes how code should be organized and how it should read. It does not describe what the app does.

The standard applies to new code and to code being materially refactored. Existing source does not all conform yet. Apply the standard within the responsibility you are changing, preserve behavior, and keep unrelated formatting or renaming out of a functional change.

**What does not belong here:** feature behavior, protocol details, thresholds, timings, current class inventories, migration notes and change history. Those belong in feature or protocol documents under `docs/`, in Dart/Swift/Kotlin/C++ documentation comments, or in version control. If a paragraph would become wrong when a feature changes, it belongs somewhere else. Examples in this document are illustrative and self-contained; they do not name real application types.

The document has five parts:

1. [Principles](#part-1-principles): the rule everything else follows.
2. [Structure](#part-2-structure): where responsibilities live and what they may depend on.
3. [Code](#part-3-code): how files, types and operations read, in any language.
4. [Language conventions](#part-4-language-conventions): Dart, Swift, Kotlin, C++ and C specifics.
5. [Process](#part-5-process): applying, reviewing and verifying changes.

---

## Part 1. Principles

### 1.1 Abstraction, specialization and assembly

**Shared abstractions define the general structure, design and behavior. Specialized implementations supply the parts that vary. Composition assembles those pieces into larger responsibilities.** This applies everywhere: UI, controllers, workflows, data operations, storage, runtime integration and native hosts.

| Role | Owns | Consumers supply |
| --- | --- | --- |
| Shared abstraction | The common structure, rules, design, behavior and extension contract of a coherent family | Only the inputs and variation points that family allows |
| Specialized implementation | A particular responsibility within that structure | Its content, actions, data rules or platform-specific operations |
| Assembly | Selection, wiring and composition of pieces into a larger component or workflow | Explicit dependencies, values, children and callbacks |

These roles repeat at every scale. A section assembles controls, a page assembles sections, and the shell assembles pages, the player and app navigation. A controller assembles workflows and data capabilities. A connection assembles endpoint clients around one shared transport. An assembled component can itself become a building block.

Consistency must come from shared code. Copying a layout, algorithm or lifecycle and keeping the copies aligned by convention does not satisfy this standard. A common interface alone does not remove duplicated policy; behavior that implementations must share needs a shared implementation owner.

### 1.2 Every concept has a named owner

Each piece of data, state, policy, resource and design decision has exactly one owner that a reader can name. Mutable state, timers, streams, workers, native handles, connections and transactions each have a single clear owner. Recurring mechanisms get small dedicated owners rather than being repeated in callers.

### 1.3 Code reads from the outside in

A reader sees the contract first, follows a readable operation or composition, and opens implementation details only when needed. Types present their inputs before their implementation. Operations read in the order their work happens. Final assembly reveals the main regions and how they relate, and names its pieces.

---

## Part 2. Structure

### 2.1 Source areas

Every codebase in the app, Dart and native, uses the same responsibility areas. A directory identifies an owner or kind of work; a file identifies a coherent component within it. Inheritance, file size and a helper's first consumer do not decide where it lives.

| Area | Owns | Boundary |
| --- | --- | --- |
| Bootstrap | Dependency construction, startup sequence, framework entry points, root setup and shutdown | Connects the other areas. Nothing else imports or locates bootstrap |
| Pages | Final view assembly, controller binding, page-scoped visual state and concrete destinations | Uses UI components and controller APIs; delegates functional work |
| UI | Presentation components, shared frames, design system, visual interaction | Supplies building blocks to pages; never imports pages |
| Application | Controllers, shared workflows and application lifecycles | Provides functionality without owning widgets, routes, dialogs or native views |
| Data | Data definitions and the operations that naturally belong to them | One silo, independent of application and presentation |
| Infrastructure | Runtime execution, protocols, workers, native resources, platform adapters and transport | Implements technical capabilities using standalone data definitions |

Create a directory only when it has a meaningful responsibility and real contents. A feature needs only the subdirectories it uses. Abstraction, specialization and assembly happen within these areas; they are not extra top-level directories.

### 2.2 Dependency direction

| Owner | May depend on | Must not depend on |
| --- | --- | --- |
| Bootstrap | Every area it assembles | — |
| Pages | UI, application APIs, data values/projections, destination pages | Infrastructure, concrete data I/O |
| UI | Other UI, application APIs, data values/projections | Pages, bootstrap, infrastructure, concrete stores, repositories, file operations or storage configuration |
| Shared frames, toolbars, navigation | Generic UI and configuration supplied by consumers | Concrete feature controllers or widgets; toolbar and app-navigation families stay independent of each other |
| Application | Other application modules, data, infrastructure capabilities | Pages, widgets, routes, dialogs, `BuildContext`, `Navigator`, `setState`, visual controllers |
| Data | Other data modules and necessary technical libraries; repositories may use infrastructure clients | Application, pages, UI, bootstrap |
| Infrastructure | Data definitions, technical libraries, other technical adapters | Application, pages, UI |

Avoid cycles between concrete libraries. A client that a facade constructs receives narrow callbacks for the facade's capabilities rather than importing the facade. Bind those callbacks to the facade's methods so overrides still dispatch normally. Controllers may use `package:flutter/foundation.dart` for notifications and nothing else from Flutter.

### 2.3 Flutter application layout

Every Dart source file except `lib/main.dart` belongs to one of these area directories:

| Directory | Area |
| --- | --- |
| `lib/bootstrap/` | Bootstrap |
| `lib/pages/` | Pages |
| `lib/ui/` | UI |
| `lib/application/` | Application |
| `lib/data/` | Data |
| `lib/infrastructure/` | Infrastructure |

```text
lib/
  main.dart                    # Thin entry point; delegates to bootstrap
  bootstrap/
  pages/<feature>/
  application/
    controllers/<feature>/     # Feature controllers
    controllers/shared/        # Shared controller mechanisms
    app/                       # Application facade and its private workflows
    workflows/                 # Reusable workflow mechanisms
    <subject>/                 # Named application modules
    presentation/              # Application-facing labels and helpers
  data/
    models/<subject>/          # Definitions, enums, parsing, copying, small value helpers
    projections/<subject>/     # Prepared or grouped snapshots and their construction
    queries/<subject>/         # Searching, matching and selection
    rules/<subject>/           # Pure comparison, accounting and progress rules, no I/O
    structures/<subject>/      # Containers with mutation/query methods, caches, buffers
    configuration/<subject>/   # Data configuration and opening its store
    storage/<subject>/         # Locations, schemas, migrations, persistence, CRUD
    files/                     # Reusable file-data operations
    repositories/              # Shared data access, scoped caches, reconciliation
  ui/
    shell/                     # Page frames, page body/scroll contracts, adaptive scaffold
      toolbars/                # Page-level toolbars and actions
      navigation/              # App-wide destination surfaces
    structures/                # Modal, section and collection frames
    features/<feature>/        # widgets/, sections/, dialogs/ as needed
    shared/
      design_system/           # Theme, tokens, controls, surfaces, layout, icons
      <domain>/                # Shared domain presentation
    navigation/                # History, transitions and input helpers
  infrastructure/
    <capability>/              # audio, downloads, server, platform, security, ...
```

### 2.4 Native host layout

Native hosts use the same areas inside each platform's required project structure. Folder naming follows the platform's language conventions.

| Host | Area folders | Example path |
| --- | --- | --- |
| iOS, macOS (Swift) | PascalCase: `Bootstrap/`, `Data/Models/`, `Application/Controllers/`, `Infrastructure/`, `Pages/`, `UI/` | `Runner/Infrastructure/Flutter/<Name>ChannelAdapter.swift` |
| Shared Apple sources | The same PascalCase areas under `native/apple/` | `native/apple/Data/Models/<Subject>/<Name>.swift` |
| Android (Kotlin) | Lowercase subpackages under the app package: `bootstrap`, `data.models`, `application.controllers`, `infrastructure`, `pages`, `ui` | `.../infrastructure/flutter/<Name>ChannelAdapter.kt` |
| Windows, Linux (C++) | `lower_snake_case` under `runner/`: `bootstrap/`, `data/models/`, `infrastructure/`, `ui/shell/`, `application/`, `pages/` | `runner/infrastructure/shell/<name>_launcher.cpp` |

Rules shared by every host:

- **Native code supports the Dart application.** Flutter owns application pages, navigation and domain workflows. A native action requests work through the existing Flutter boundary. It does not reimplement queue selection, library filtering, authentication or other Dart business rules. A native controller may own the loading, cancellation and selection state its native view needs.
- **Application and Pages exist only when real native work exists.** Calling a platform API does not need a controller. A system-rendered surface such as a media notification or a vehicle browse tree is UI presentation, not a page. Do not create a native copy of a Dart controller to fill the tree.
- **Framework entry points stay thin.** Application delegates, activities, services, scene delegates and window procedures forward lifecycle events to composed owners. Dependencies are passed in at assembly, never located by searching windows or reaching through a global application delegate from feature code.
- **Data has no resources.** A native data value holds no window, view, channel, messenger, queue, mutex, callback, COM interface or independently released handle. A `struct` that holds those is a resource implementation and lives with its infrastructure or UI owner.
- **Tool-owned files stay tool-owned.** Generated registrants, Flutter-managed build glue, ephemeral output, package caches and vendored sources keep their tool or upstream ownership and style.
- **Build membership is explicit.** Xcode file references and build phases, CMake source lists, Gradle source sets and Android manifests are executable contracts. A file move updates its build registration, include paths, component names and resource references together.
- **Native packages keep their boundary.** FFI packages keep their C ABI, exported symbol names, calling conventions, integer widths, units, opaque handles and matching release functions. Shared native implementation stays in its package rather than being moved into a host.

### 2.5 Pages, presentation and functionality

| Responsibility | Owner |
| --- | --- |
| Read field text, manage focus, animate, track drag or scroll position | Page or UI component |
| Validate input, filter results, decide which items are selected | Feature controller |
| Present a confirmation and display its result | Page or UI component |
| Execute the approved deletion, save or playback action | Application controller or workflow |
| Describe an action result, destination or data snapshot | Data model or projection |
| Construct a route to a concrete page | Page |

**Pages** assemble complete views. Every tab root, detail screen, settings subpage, home view and splash view is a page, whatever its class-name suffix. A page selects components, binds their data and callbacks, presents confirmations and chooses concrete destinations. Components it uses do not know which page implements a destination; the page supplies callbacks.

**UI components** receive values, state, children and typed callbacks. They own layout, animation, hover, focus, Flutter text/scroll/animation controllers, drag state, modal presentation and dismissal. A component may deserve its own file even when one page uses it, if it has a recognizable responsibility.

**Controllers** own validation, loading and errors, functional selection, filtering, pagination, debouncing, asynchronous commands, request generations and stale-result guards. For example, a widget owns its scroll controller and reports the remaining extent; the controller decides whether to load more. Controller results describe values or destinations, never widgets or routes. A page controller must not create another instance of an application-wide runtime such as an engine, library or download manager.

An event handler may collect input, present a confirmation, call a controller, check that it is still mounted and perform a visual response. It delegates data access and the functional operation.

### 2.6 Shared structures

A shared structure owns the stable arrangement or execution protocol of a family and names the parts that vary. Keep hierarchies short and inputs visible. Choose the mechanism that expresses the relationship:

| Mechanism | Use it for | Ownership |
| --- | --- | --- |
| Base class with named hooks | A stable assembly or execution sequence with specialized steps | The base owns the sequence and invariants; subclasses implement permitted differences |
| Parameterized component or function | Variations expressible as values, children or callbacks | Consumers configure one implementation |
| Shared collaborator or strategy | A policy used across otherwise independent components | Consumers delegate common work and inject what varies |
| Interface with adapters | Interchangeable implementations of a capability, such as platform output | The interface defines the contract; a shared collaborator owns common execution policy |
| Composition | Building a larger responsibility from existing pieces | The assembly wires pieces; each keeps its own rules and lifecycle |

| Situation | Expected choice |
| --- | --- |
| A known family has a common frame or sequence with identifiable variation points | Establish or extend its shared structure before implementing variants; migrate existing members together |
| A new member belongs to an established family | Use that family's contract; add a meaningful extension point if needed |
| Independent components need the same policy or data operation | Extract a shared collaborator in the owning area and compose it into each |
| A capability has alternative platform or technical implementations | Define its contract, isolate the variants, share common execution policy |
| An existing component already exposes the needed slots | Compose it directly instead of subclassing |
| A recognizable presentation region makes a page easier to read | Extract a standalone UI component, even for one consumer |
| A small private helper supports one operation | Keep it beside that operation |
| Behavior coordinates application capabilities or functional state | Extract a controller or named workflow |
| An operation constructs, queries, transforms, opens or saves data | Place it with the data or its store |
| A parser, worker or native resource has its own lifecycle | Give it an infrastructure module with explicit ownership |

Do not wait for several copies before sharing: a known family can start with its shared structure and first consumer. Do not create an empty base class, universal manager or generic framework to make unrelated types look alike. Abstractions live in the area of their responsibility, never in a general-purpose `base/` or `common/` directory.

**Shared design has levels.** Theme and tokens define visual values. Controls own consistent rendering and interaction. Section, modal and shell structures own common arrangements. Use every applicable level. Passing the same colors to several separately rebuilt controls does not make their structure or interaction shared. A design change should flow from its owning abstraction to every member of the family.

**The shell owns the page frame.** `ui/shell` provides the shared page base. Pages supply their toolbar and body through its assembly hook and choose a body form (bounded box, scrolling box or slivers) and a toolbar placement (scrolling or fixed). The base owns page-level scaffolding, scroll views, padding, safe areas and overlay clearance. A page does not build its own page-level scaffold or scroll view and does not override the base's `build`. Scrollable regions inside a content component remain legitimate. Page toolbars (`ui/shell/toolbars`) and app-wide destination navigation (`ui/shell/navigation`) are separate families that do not import each other.

Reactive pages keep their stream or listenable builder around the assembly call and produce both toolbar and body from one snapshot, instead of subscribing twice.

### 2.7 Data and its operations

All application and technical data definitions live in the data silo: entities, immutable values, enums, settings, response records, controller-facing results, worker messages, native ABI records and mutable containers. Widget configuration, visual tokens and purely visual state stay in UI.

Data may construct, parse, serialize, copy, validate, derive, query, mutate, open and save itself. Keep a small helper on its data type; give substantial persistence or shared access a named store or repository. Application-dependent preparation stays in a controller, which supplies the values to a result or snapshot constructor. A result model never reaches back into the controller or runtime that consumes it. A data method never acquires a UI context, navigates or assembles widgets.

Related stores share persistence and transaction mechanisms. Recurring parsing, comparison and mutation rules with the same meaning have one shared helper or container. Each definition has one physical source home; a facade may re-export a type but not duplicate it. Necessary technical dependencies are explicit: ABI records may use `dart:ffi`, and worker messages may carry ports.

### 2.8 Independent components and private component trees

A file boundary represents a responsibility someone can name. Independent models, parsers, buffers, adapters, controls and helpers are ordinary libraries with normal imports. A component's first consumer does not own the modules it uses.

A private component tree exists when one cohesive library deliberately shares private scope (Dart `part` files). Such a component has an exclusive directory holding its entry point and only its own private parts. Independent source stays outside that entire tree.

```text
data/models/<subject>/<value>.dart          # Standalone data
data/structures/<subject>/<buffer>.dart     # Standalone container
infrastructure/<capability>/protocol/       # Standalone parsing
infrastructure/<capability>/engine/
  <engine>.dart                             # Component entry point
  <responsibility>/                         # Its private parts only
```

Splitting a file into parts only separates text. It does not create a reusable abstraction or remove duplication. A reusable policy needs its own responsibility and contract outside the private tree. A policy shared only by private parts of one library may stay a private owner there. Forwarding mixins that preserve a facade's calls carry no behavior of their own.

### 2.9 Runtime and resource ownership

| Boundary | Ownership |
| --- | --- |
| Server access | Endpoint clients share one transport that owns session, authentication, trust, retry and request policy; payload records live in data |
| Workers | The parent owns communication and recovery; the worker owns its active session; the session owns its output handles and cancellation |
| Persistence | Stores share their database connection and transaction boundary; splitting source never opens extra connections or splits an atomic operation |
| Views | Pages and components own their visual controllers and the feature controllers they bind; application-wide state keeps its application owner |
| Native host | The process host owns process-wide services; an engine binding owns channels for one messenger; a scene or window owns its presentation; a request owns its cancellation and completion |

- Constructors establish local invariants synchronously and perform no externally visible I/O. Explicit initialization starts workers and I/O.
- Create private state owners with their parent before subscriptions when scheduling order depends on construction.
- The creator owns disposal unless ownership is explicitly transferred. Borrowed resources stay owned by their provider.
- Cleanup is idempotent and awaitable where the resource requires it.
- When a lifecycle or execution protocol is common to a family, its shared owner enforces it. Variants supply resource-specific work through that contract; they do not each carry a copy of initialization, cancellation or cleanup policy.
- Sharing an abstraction does not mean sharing a mutable instance. Bootstrap or the parent assembly decides lifetime and instance count.
- Reorganization preserves initialization order, request generations, stale-result guards, serialized writes, scoping, migrations, cancellation and worker command ordering.

### 2.10 Platform boundaries

Channels between Dart and native code follow one pattern on every host:

- **The adapter owns the wire.** Channel and method names, codec values, untyped maps, result objects, error envelopes and unknown-method handling live in the channel adapter. It decodes once into typed values and delegates to typed capabilities. Capabilities never construct codec values or reply objects.
- **Wire names stay exact.** Channel names, method names, keys and discriminator values are contracts. A native method may be named idiomatically while its wire method keeps its spelling.
- **Every incoming call is answered exactly once,** including on failure, cancellation, unknown methods, shutdown and when the owning object has been released.
- **Completion meaning is stated.** Accepting a request is not the same as finishing it: requesting a permission does not mean it was granted, and launching a file browser does not mean it finished displaying.
- **Attachment is idempotent per binding.** Handlers are unregistered explicitly while their messenger is still valid, before the captured owner is destroyed. Replacing an engine is an explicit detach and rebind.
- **Threads have owners.** UI mutation and outbound channel calls happen on the platform main thread. Work from other threads is delivered through an explicit dispatcher with defined lifetime and relevance rules. A reply callback's threading permission is not permission to mutate UI.
- **Shared mechanics are extracted when a family exists.** Once several adapters share registration, invocation, reply and teardown decisions, a shared channel collaborator owns them. Each adapter keeps its own methods and decoding.
- **Realtime paths stay lean.** Audio callbacks and render paths receive no logging, main-thread hops, channel messages or general task scheduling.

Dart platform adapters mirror this: they decode channel methods into typed requests, encode typed responses, and keep method strings out of application workflows. Their contracts live in data.

---

## Part 3. Code

These rules apply in every language. Part 4 states how each language expresses them.

### 3.1 Files

- Name files for their responsibility or primary type. A file has one primary public concept. Its small private state class, adapters and tightly coupled helpers may sit beside it.
- File boundaries follow responsibilities, not one-function-per-file. Extract a piece when it has a meaningful contract, independent reuse, its own state or lifecycle, or a substantial responsibility that obscures its owner.
- No dumping grounds: no `helpers`, `common`, `utils` or `misc` files or folders.
- Approaching 1,000 lines is a signal to inspect responsibilities, not a target. A short file can still hold too many responsibilities. The limit is enforced automatically for Dart files in `lib`.
- Order a file as: documentation and annotations, imports (grouped and sorted), exports, part/inclusion directives, closely related constants and type aliases, the primary declaration, then its private helpers in reading order.

### 3.2 Member order

Use this order within a type, omitting empty groups. Do not add section banners.

| Order | Members | Reading purpose |
| --- | --- | --- |
| 1 | Static constants and shared immutable values | Common definitions |
| 2 | Final inputs, configuration, callbacks and injected dependencies | What an instance receives |
| 3 | Private mutable state and owned resources | What an instance manages |
| 4 | Constructors: primary, named or secondary, then factories | How a valid instance is created |
| 5 | Accessors, with each getter/setter pair adjacent | What consumers observe or assign |
| 6 | Initialization, lifecycle and shutdown, in lifecycle order | When it becomes usable and releases resources |
| 7 | Public operations and extension contracts, grouped by responsibility | What it does or lets a specialization provide |
| 8 | Private operations and presentation helpers, small pieces to larger groups | How the contract is implemented |
| 9 | Final `build` or equivalent assembly hook | How the named pieces form the result |

Keep related behavior together rather than alphabetizing or splitting all public from all private members. A template's extension hooks form one contract and stay together. A specialization's content hooks go at the end, in the order their regions appear.

| Type family | Order |
| --- | --- |
| Widget or view configuration | Inputs, constructor, then state creation or helpers before final assembly |
| Widget or view state | Fields and accessors; lifecycle hooks in framework order ending with disposal; handlers and presentation helpers; final assembly. Implement only hooks that do work |
| Controller or runtime owner | Dependencies and state; construction; observable access; initialization and cleanup; commands; helpers. One operation's workflow reads top to bottom |
| Data type | Fields; constructors and decoding factories; accessors; data operations, copying and serialization; private helpers; equality, hash and description together at the end |
| Enum or extension | Values first, then fields, constructor and operations |

Reordering never changes behavior. Preserve field-initializer evaluation order, lazy initialization, constructor and superclass behavior, callback registration and dispatch. In languages where declaration order is lifetime order (C++), lifetime wins over layout preference.

Constructor parameters follow field order: framework key first, required inputs and dependencies, required callbacks, then optional configuration and optional callbacks. Use named parameters for multi-input APIs where the language supports them. At call sites, follow the same order and put a primary child, children or builder last.

### 3.3 Formatting and logical paragraphs

Every language uses its pinned formatter with two-space indentation, a 120-column target and at most one consecutive blank line. Compact signatures stay on one line when they fit; longer ones wrap naturally. Do not shorten names, drop useful types, hand-align columns or suppress the formatter to force a layout. Long strings and URLs may exceed the target. Do not mix a broad formatting pass into a behavior change.

The formatter does not find changes of purpose, so paragraphs are a deliberate part of the standard. **Write statement bodies as logical paragraphs:** a small group of statements that completes one step, such as validating input, obtaining a value, preparing a request, performing an operation, updating state or producing a result. Use exactly one blank line when the purpose changes.

| Boundary | Rule |
| --- | --- |
| Local declarations | Keep declarations for one step together; separate them from the step that uses them. A lookup and its immediate null check may stay together |
| Guard clauses | Separate each independent guard from the next guard and from the main path. A simple guard's `return`, `throw` or `continue` stays directly inside it |
| Control-flow blocks | Blank line between independent sibling `if`, loop, `switch` or `try` blocks, and after a completed block. `else`, `catch`, `finally` and a `do` loop's `while` stay attached |
| Workflow stages | Separate preparation, execution, state updates, notifications and result assembly. Related assignments and their notification may stay together |
| Final result | Blank line before a final `return` or `throw` that follows earlier work. Not inside a simple guard or a single-statement body |
| Local functions | One blank line before and after each local function declaration |

```text
label(rawTitle, rawArtist):
  title  = trim(rawTitle)
  artist = trim(rawArtist)

  if title is empty:
    return "Untitled"

  if artist is missing or empty:
    return title

  return artist + " — " + title
```

Do not put a blank line after every statement, inside braces or in stacks. Comments sit directly above the paragraph they explain. Documentation and annotations stay attached to their declaration. If a method has many substantial paragraphs, some of them probably deserve named operations.

Other layout rules:

- One blank line between members and logical member groups; related fields stay compact.
- Braces on every control-flow body, including one-line guards. Arrow or expression bodies for a clear single expression or delegation.
- A ternary only for a small obvious choice. Replace nested ternaries with named decisions, `if` statements or a `switch`.
- Builder configuration: one configuration call per line, terminal `build()` last.
- No trailing whitespace; files end with a newline.

### 3.4 Naming and visible contracts

- Names describe domain concepts and operations: `StreamSettings`, `renamePlaylist`, `cancelDownload`, `selectedTrackIds`. Avoid `manager`, `data`, `obj`, `handle`, `process` and invented abbreviations when a specific responsibility is known. Short loop variables are fine when local.
- Booleans read as questions: `is`, `has`, `can`, `should`, or a conventional framework name such as `enabled`.
- Intent callbacks are named for the request (`onSelect`, `onRename`). Change notifications are named for the result (`onTitleChanged`). A callback name never implies completed work when it only requests it.
- A private state or helper type is named for its owner, not for a copied predecessor.
- Declarations have explicit parameter and return types, including private helpers. Obvious local types are inferred. Use typed callbacks or a descriptive type alias, never a raw function type or untyped dictionary as an internal contract.
- Bindings are immutable unless reassigned. Delayed initialization is used only when it is a real invariant. Forced unwrapping is not used to bypass uncertainty that should be modeled or checked.
- External names stay exact: framework overrides, selectors, generated entry points, exported C symbols and wire keys.

### 3.5 Encapsulation, data and equality

- Expose the smallest useful contract. Inputs and simple immutable data may be public read-only fields. Do not add a private field plus a trivial getter when there is no access policy.
- Keep mutable state private when writes must enforce validation, notification, synchronization or lifetime rules. Expose observable mutable state read-only with owner-controlled writes.
- Getters are synchronous, inexpensive observations. I/O, mutation and meaningful work go behind named methods. A setter suits an ordinary assignment with a local invariant or notification; a command suits work that can fail, awaits or coordinates several owners.
- Read-only references do not make collection contents immutable. Choose deliberately between a defensive snapshot, an unmodifiable live view and a documented caller-owned collection. Never expose a mutable backing collection by accident.
- Named models represent domain concepts and shared contracts, even with two fields. Tuples and records suit small local groupings with named fields; never rely on positional access across files.
- **Nullable updates have three meanings.** For a nullable property, a copy or patch operation distinguishes *omitted* (keep), *explicit null* (clear) and *a value* (replace). The model's copy implementation owns that distinction; callers do not reproduce it. Preserve each boundary's existing missing-versus-null behavior when decoding.
- **Equality follows responsibility.** Value objects compare meaningful contents and implement equality and hashing together. Entities expose named identity and metadata comparisons and state what defines identity. Controllers, services and resource owners keep reference identity. State whether collection comparisons concern identity, order or membership. Keep equality inputs stable while an object is a map key or set member.
- Data that owns its serialization, copying, validation and open/save operations keeps them with the data. Controllers coordinate workflows; infrastructure supplies mechanisms.

### 3.6 Readable operations

- An operation reads in the order its work happens: validate, obtain, perform named steps, publish the result, release temporaries. Guard clauses keep the successful path clear. Named local values explain long conditions.
- Extract a helper when it names a meaningful suboperation, isolates a policy or boundary, removes a repeated decision or makes the parent readable. Keep the overall sequence visible in the parent. Do not split every statement into a method.
- Use a method reference for direct delegation. Keep an inline closure for simple argument adaptation. Give branching, multi-step and asynchronous event handling a named handler with a clear completion and error policy.
- Share a repeated **decision or responsibility**, not merely matching lines. Before writing another layout, state transition, storage sequence or cleanup, look for its existing owner.
- Express a complete decision over an owned enum or closed family as a named helper with an exhaustive switch that lists every case, so a new variant reveals where updates are needed. Handle unknown external values explicitly at the decoding boundary. A fallback for external input is different from a catch-all hiding an unhandled internal state.
- Short pure filter/map chains suit collection projection. Use ordinary loops for substantial branching, mutation, side effects or sequential awaited work. Take a snapshot before mutating a lazily iterated source or crossing an ownership boundary.
- Use generics for a coherent family that shares structure across item types, with meaningful bounds and typed builders. Avoid raw types and casts that hide an incomplete contract.
- Property setters stay valid for deliberate changes. A builder is introduced only for a real configuration family; it owns defaults, keeps configuration synchronous and local, and documents whether repeated `build` calls return independent objects. Do not wrap every constructor in a builder or turn asynchronous workflows into fluent chains.
- Put natural behavior on types the project owns. Extensions on external types are focused conveniences placed with the responsibility they serve. They do not add stored state, replace a composed collaborator, or split an owned type across files.

### 3.7 Extension contracts

- Document what a hook supplies, when it is called, who owns resources it creates, and whether an override must call the parent.
- Mark hooks intended for subclasses as protected where the language allows; mark implemented assembly members that must not be replaced as non-overridable; mark parent work that overrides must call.
- Concrete owners are closed to subclassing unless subclassing is an intended contract. Do not apply closing modifiers by habit to existing extension surfaces without checking their consumers.
- Prefer protocols, interfaces and composition over required hooks whose default is a fatal error.

### 3.8 UI pieces and final assembly

- Presentation receives values and typed callbacks. A UI handler collects input and delegates a command; it does not reproduce the command's algorithm or storage sequence.
- Build recognizable pieces, group them by purpose, then assemble. A small single-owner region can be a private method. A reusable region or one with its own state or lifecycle becomes a component with an explicit contract.
- **Actively reduce excessive nesting through encapsulation and reuse.** When a subtree obscures the outline, mixes regions or embeds decisions and handlers inside layout, extract a named region or component. There is no fixed depth limit; responsibility and clarity decide. Avoid helpers that only rename one obvious expression.
- Keep multi-step callbacks in named handlers on the right owner. Use an awaitable callback contract when the consumer must wait for completion.
- Use shared controls, theme tokens, surfaces and layout structures. Recurring spacing, typography, interaction states and responsive rules live in the shared design owner. Specializations pick supported variants rather than restating colors, borders, dimensions or disabled behavior. Read responsive breakpoints through the shared layout owner rather than comparing raw window sizes.
- Enabled click targets use the hand cursor on desktop; disabled controls keep the arrow, text inputs the text cursor, and passive surfaces advertise no action. Shared controls own this.

### 3.9 Async work, errors and resource lifetime

- An API states what completion means. Await what an operation promises to finish, return its future, or document that it only schedules work and provide a way to observe the result. A save is not complete before its write finishes.
- Asynchronous commands return an awaitable type. Fire-and-forget work is deliberate, named as such, and has handled errors and lifetime; it never replaces required cleanup or persistence.
- For genuinely streamed state, expose a read-only current snapshot plus a typed change stream. State whether it supports multiple listeners, replays, which errors it emits and who closes it. One-off commands stay awaitable operations.
- Choose sequential, latest-result or concurrent event processing explicitly. Asynchronous listener callbacks do not serialize events by themselves. Cancellation, generation invalidation and timeouts are different things; ignoring a stale result or timing out does not stop the underlying work.
- After a suspension point, re-check relevance: mounted state, request generation, scene or engine identity, cancellation. Isolation alone does not establish relevance.
- Catch errors where the owner can recover, translate them into a meaningful result, or report an actionable failure. Preserve stack traces. Never silently catch everything or return a success-shaped default after a failed required operation. A best-effort fallback is intentional, narrow and documented. User-facing messages belong to presentation; diagnostics belong to the logging owner. Never log credentials, tokens or proofs.
- Remove listeners, cancel subscriptions and timers, and release native handles when their owner ends. Release temporaries on success and failure (`try`/`finally`, `defer`, RAII, scoped cleanup). When a borrowed dependency can be replaced, detach from the old one and attach to the new one.
- Synchronous disposal cannot wait for asynchronous work. Provide an explicit asynchronous shutdown boundary and await it at the right lifecycle level.
- Weak captures are for real cycles or borrowed lifetimes. A released owner must still complete any outstanding obligation such as a channel reply.

### 3.10 Documentation and comments

- Document public contracts whose meaning is not obvious from the signature: invariants, units, ownership, completion guarantees, errors, defaults and extension hooks. Link related declarations with the language's documentation references.
- Comment consequential implementation decisions with a short *why*.
- Do not narrate syntax, keep commented-out code, label a component as new, use decorative banners, or accumulate change history in comments.
- No README files in source trees (`lib/`, native runner folders). Project-wide expectations live in this document; feature and protocol contracts live in their own documents under `docs/`.

---

## Part 4. Language conventions

### 4.1 Dart

**Files and imports**

- Files and directories are `lower_snake_case`, matching the primary type: `stream_settings.dart`.
- Import groups, separated by one blank line and alphabetized within each: `dart:` libraries; Flutter and third-party packages; this app's packages. Test-harness relative imports, when needed, form a final group.
- Every import and export of a file under a package's `lib/` uses a `package:` URI, including same-directory files, conditional imports and imports from tests. The analyzer's `always_use_package_imports` rule enforces this for imports; review exports and conditional targets explicitly.
- Exports have their own sorted section after imports. Prefer importing a role-specific owner over a broad export facade.
- `part` and `part of` directives are relative to their owning library. A part file starts with `part of`; imports belong to the owner. `part` is used only for an intentional shared private implementation (see [2.8](#28-independent-components-and-private-component-trees)).
- Production source never imports test harnesses or another package's `src/` implementation.

**Language rules**

- A leading underscore is **library-private**, not class-private: a library and its parts share it. Choose library boundaries with that in mind.
- `lowerCamelCase` for members, variables, enum values and constants; acronyms as words (`albumId`, `httpClient`).
- Prefer `final` locals and `const` constructors and values. `late` only for a real delayed-initialization invariant. Do not use `!` to bypass uncertainty.
- Avoid `dynamic`; accept `Object?` at untyped boundaries and decode there.
- Prefer `VoidCallback`, `ValueChanged<T>` or a descriptive `typedef` over `Function`.
- Asynchronous commands return `Future<void>`; never declare `async void`. A `VoidCallback` can delegate to a separate awaitable operation, and the boundary that does not await handles its errors. Use `unawaited` only for deliberately detached, error-handled work.
- Use `sync*` and `async*` for intentionally lazy sequences and keep their deferred errors and cancellation explicit.
- Records use named fields and serve local groupings and private helper results; a reused concept becomes a model class. A type alias does not create a nominal type. Records compare structurally; a class replacing one compares by identity until it implements equality.
- Implement the nullable tri-state in `copyWith` with an omission sentinel compared by `identical`.
- Widget helpers need not use a `_build` prefix; `_renameButton` and `_emptyState` describe their pieces. Be consistent within a family.
- Extension methods give focused conveniences to external types (`Duration`, `BuildContext`). Shared extensible structures use real inheritance or composition.

**Modifiers and annotations**

| Form | Use when |
| --- | --- |
| `abstract class` | A non-instantiable contract or template has incomplete behavior |
| `abstract interface class` | Consumers implement a capability without inheriting implementation |
| `base class` / `abstract base class` | External subtypes must inherit the implementation |
| `final class` | Subtyping outside the library is intentionally prohibited |
| `sealed class` | A deliberately closed family supports exhaustive handling |

Hooks for subclasses in other libraries use non-underscore names with `@protected`; implementations use `@override`. Use `@nonVirtual` on assembly members such as shared frames' `build`, and `@mustCallSuper` where inherited work is required. These are analyzer contracts, not runtime protection.

**Flutter lifecycle**

- Pages extend the shared page frame and supply content through its assembly hook; they never override its `build`.
- Feature controllers extend the shared controller base, keep construction inert and put startup in its initialization hook. The shared view binding initializes, observes and disposes controllers a view owns.
- `State.dispose()` is synchronous. Asynchronous shutdown happens at an owner boundary that can be awaited.
- After an async gap, check `BuildContext.mounted` before using that context, or `State.mounted` before updating that state. A guard on a different owner does not protect the context in use.

**Formatter**

Configured in `analysis_options.yaml`:

```yaml
formatter:
  page_width: 120
  trailing_commas: automate
```

Run from the package root: `dart format lib` to apply, `dart format --output=none --set-exit-if-changed lib` to check. Do not switch to trailing-comma preservation or add per-file width overrides. The one permitted suppression is paired `// dart format off` and `// dart format on` around a fluent builder chain, so each configuration call keeps its own line.

### 4.2 Swift (iOS and macOS)

**Files and modules**

- `UpperCamelCase.swift` filenames matching the primary type; PascalCase responsibility folders that match Xcode groups.
- File order: imports, tightly related contract declarations, primary type, then focused same-file conformance extensions and tightly coupled supporting types.
- Imports name modules, not paths. Group Apple and standard modules, then Flutter and other dependencies, then project modules; sort within groups; import only what the file uses. A folder inside a target is not a module. Introduce a separate framework or package only when reuse or a compiler-enforced boundary justifies it.
- Moving a file updates its Xcode target membership, build phases, and any plist, entitlement, storyboard, nib or bridging-header references. Nib and storyboard class and module names are contracts.

**Types and access**

- Member order is the shared order in [3.2](#32-member-order). Superclass lifecycle overrides stay on the primary declaration. Keep equality, hashing and description together near the end.
- `lowerCamelCase` members with meaningful argument labels: `loadArtists(scope:)`, `openDirectory(at:)`. Swift initialisms are fine (`artworkURL`, `deviceID`); wire keys keep their exact spelling.
- `private` for implementation state, `private(set)` for owner-controlled observable state, default `internal` within a target. `public` and `open` only for a real module boundary. Swift has no protected level.
- Mark concrete owners `final` unless subclassing is intended. Use `@objc`, `NSObject` inheritance and selectors only where the framework requires them.
- Ordinary behavior lives on the owning type. Extensions are mainly for protocol conformance and external-type conveniences. A `Type+Feature.swift` file does not provide shared private scope and cannot add stored properties; extract a composed owner instead of widening state.
- Prefer protocols and composition over base classes with `fatalError` defaults. Use a base class only for a real superclass-owned sequence.

**Values and operations**

- Structs and enums for values; classes for identities, delegates and resource owners. A struct holding references is not deeply immutable or automatically `Sendable`.
- A reusable patch API represents unchanged, cleared and replaced explicitly; a plain optional cannot carry all three.
- Use `Equatable` and `Hashable` when content equality belongs to the value; define entity identity explicitly.
- Prefer `let`, early `guard` exits and typed results. Avoid force unwraps and casts, `try!`, nested ternaries and blanket error swallowing. Handle owned enums exhaustively and evolving framework enums with a meaningful `@unknown default`.
- Use explicit `return` in multi-step operations; concise single-expression bodies only when the intent is obvious.
- Check availability only for APIs newer than the deployment minimum; omit branches the target already guarantees.

**Concurrency and lifetime**

- Give every mutable owner one documented isolation domain. UIKit, AppKit and CarPlay presentation and outbound Flutter calls run on the main thread.
- Prefer explicit `@MainActor` and actors within a deliberate concurrency change, against the verified toolchain and language mode. Do not add `Task` wrappers to every callback, unchecked `Sendable` conformances or a language-mode change to reorganize source.
- `await` allows interleaving: re-check generation, identity and cancellation afterwards.
- Use `defer` for synchronous scope cleanup and an explicit awaitable stop for asynchronous shutdown; `deinit` cannot await.
- Keep timing-sensitive C or Objective-C audio paths separate from Swift orchestration.

**Formatter**

`swift-format` with `.swift-format` in each Apple host folder:

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

Format handwritten Swift only, including shared Apple sources. Pin the formatter version on the Apple build environment before enforcing it.

### 4.3 Kotlin (Android)

**Packages and files**

- Lowercase dot-separated packages matching folders; PascalCase files and types; `lowerCamelCase` members; `UPPER_SNAKE_CASE` constants. XML resources keep Android's lowercase underscore names and qualifier folders.
- File order: package, imports, related contract declarations, primary type, tightly coupled private helpers. Explicit imports, no wildcards, alphabetical as the formatter orders them. Avoid fully qualified names in bodies.
- Subpackages organize but do not isolate: `internal` is module-wide and there is no package-private level. Use private state and review; add a Gradle module only for a real reuse, build or enforcement need.
- Keep Android's source sets and resource layout. Moving a manifest-declared component updates the manifest, explicit `Intent` and class references together. The namespace and application ID do not change with folder moves.

**Types**

Member order adapts [3.2](#32-member-order):

1. Primary-constructor inputs, callbacks, configuration and dependencies.
2. Companion constants and immutable definitions.
3. Private state and owned resources, in safe initialization order.
4. `init` blocks and secondary constructors.
5. Accessors, getter/setter pairs together.
6. Lifecycle, attachment and shutdown.
7. Public operations and extension contracts.
8. Private operations and presentation pieces.
9. Final assembly.

- Property initializers and `init` blocks run in declaration order; preserve it. Keep companion objects focused and free of hidden mutable process state.
- Prefer `val`, private backing state and `private set`. Classes are final by default; add `open` or `abstract` only for a real extension contract.
- Data classes for value contracts; ordinary classes for identity and resource owners; enums or sealed types for closed alternatives. `copy` expresses the nullable tri-state directly. Generated equality and copying are shallow, and arrays such as `ByteArray` need an explicit content policy.
- Named models over `Pair` and `Triple` across files.
- An Elvis return suits a missing local value; a normal `if` block suits a substantive guard. Expression bodies for obvious single expressions; block bodies with explicit returns for workflows. Nested scope-function chains (`let`, `apply`, `also`, `run`) become named values. Use safe casts at untyped boundaries and exhaustive `when` over owned alternatives.
- Use KDoc for contracts with units, lifetime, failures or completion meaning.

**Android lifetimes**

- Framework components initialize composed dependencies in their lifecycle callbacks. Ordinary collaborators receive dependencies through their constructors.
- Process-wide owners use `applicationContext`. Never keep `Activity` or `View` references in process objects, companions, channel closures or workers.
- `Application.onTerminate` is not a shutdown mechanism; define explicit cleanup for sessions, services and requests, and keep durable state separate from ephemeral resources.
- Coroutines need an explicit owner, dispatcher and cancellation contract. No `GlobalScope`, unowned executors, or `lifecycleScope` for process-lifetime work.
- Volatile fields, concurrent maps, atomics and locks each solve different problems; none alone makes a compound workflow safe. Preserve lock order and do not wait for a worker while holding a lock it needs.

**Formatter**

ktlint with `android/.editorconfig`:

```editorconfig
root = true

[*.{kt,kts}]
charset = utf-8
indent_style = space
indent_size = 2
max_line_length = 120
insert_final_newline = true
ktlint_code_style = android_studio
```

The established app package keeps its underscore through a scoped `package-name` exception; new package segments are lowercase words.

### 4.4 C++ (Windows and Linux)

**Naming**

| Item | Convention | Example |
| --- | --- | --- |
| Files and directories | `lower_snake_case` (`.h` with `.cpp` on Windows, `.cc` on Linux) | `infrastructure/shell/directory_launcher.cpp` |
| Types and aliases | `PascalCase` | `DirectoryLauncher` |
| Functions, methods, parameters, locals | `snake_case` | `open_directory`, `folder_path` |
| Namespaces, scoped enum values | `snake_case` | `phonolite`, `Status::accepted` |
| Private members | `snake_case_` | `owner_window_` |
| Constants | Descriptive `snake_case`, `constexpr` where suitable | `default_window_width` |

External API names, generated entry points, framework override names, callback signatures and calling conventions stay exact.

**Headers and includes**

- Headers are self-contained, guarded and include what they use; prefer forward declarations where an incomplete type suffices.
- A class holding `std::unique_ptr` to a forward-declared type defines its destructor, and constructors where cleanup paths require it, out of line.
- Substantial implementation goes in the source file; short value operations may be inline.
- Include order in a source file: its own header, then standard library, platform SDK, Flutter and third-party, then app headers, each group sorted. Document any required ordering exception.
- App headers are included from the configured project include root (`"runner/data/models/..."`), never through `../../` chains or absolute paths. Flutter headers use their published names.
- No `using namespace` in headers; keep aliases local. Small private helpers go in an unnamed namespace. Never include `.cpp` files to share private scope.

**Types and layout**

- Headers present the public contract first: related types and constants, construction and special members, observation, lifecycle, commands. Protected hooks follow for a real base family. Private dependencies and state come next, then private operations.
- **Declaration order is lifetime order.** Members initialize in declaration order and destroy in reverse. Declare a dependency before anything that borrows it and mirror that in initializer lists. This overrides any layout preference.
- Implementation files order construction and destruction, lifecycle, public operations, private helpers, then final assembly.
- Concrete owners are `final` unless subclassing is intended. Prefer private state and named commands over protected mutable fields.

**Operations and data**

- `const` locals and `const` observer methods. `auto` when the type is obvious; explicit types where units, signedness, status family or ownership matter.
- References for required borrowed dependencies, nullable pointers for optional borrowed objects, values for ownership by copy or move.
- `nullptr`, scoped enums and typed constants. `static_cast` for ordinary conversions; `reinterpret_cast` only for real API or ABI conversions, commented when consequential. Narrowing and text-encoding conversions are explicit.
- A string view is borrowed and may not be null-terminated: do not retain it across callbacks or pass its data to an API that needs a terminator.
- Plain `struct`s with direct fields for simple values; classes when invariants need controlled mutation. Define only the comparisons a concept needs. Resource owners are non-copyable unless copying has a defined meaning.
- Use named result types for shared outcomes, and `std::optional` or `std::variant` where the host's language standard provides them. Use the host's configured language standard; changing it is a separate build change.
- Keep platform status families distinct (`HRESULT`, last-error codes, Shell results, `GError`). Preserve native error values that callers need.
- Exceptions never cross C callbacks, Flutter boundaries or exported C ABI functions. Keep the host's exception configuration.

**Resources**

- Value members and `std::unique_ptr` for sole ownership, created with `std::make_unique`. `std::shared_ptr` only for real shared lifetime, never to make asynchronous captures convenient. Follow the rule of zero; define or delete copy and move deliberately for resource owners.
- RAII pairs a resource with its matching release, invalid value, thread and transfer rules. A raw handle value does not establish ownership. Release every allocation with its matching function and never across allocators.
- Explicit lambda captures. Capturing `this` does not extend its lifetime. No detached threads, broad `[&]` captures or work that outlives the engine.
- Destroying a channel object does not necessarily unregister its handler; unregister explicitly while the messenger is valid.

**Windows specifics**

- COM initialization belongs to a thread and apartment; balance every successful initialization, including `S_FALSE`, on the same thread, and keep COM-dependent objects inside that lifetime.
- The native frame owns its top-level window lifecycle; a hosted child window is borrowed.

**GTK and GObject specifics (Linux)**

- GObject types keep GObject naming and registration conventions (`MyType`, `my_type`, `MY_TYPE`, `parent_instance`). Do not place macro-generated declarations in a C++ namespace without checking linkage.
- A GObject instance is allocated through GType, not C++ construction. Do not embed non-trivial C++ members in an instance struct; hold a pointer to an explicitly constructed C++ owner and destroy it through the GObject lifecycle.
- `dispose` may run more than once: detach handlers and signals while dependencies are valid, clear owned pointers, chain to the parent. `finalize` handles remaining storage and chains.
- Use `g_autoptr` and `g_autofree` at scope boundaries. Widget destruction and reference release are different operations. Copy a `GError` message before freeing it.
- A signal connection does not extend its user data's lifetime. Own and disconnect handler IDs. Avoid channel → callback → owner → channel cycles.
- Do not add empty lifecycle overrides just to match a template.

**Formatter**

clang-format with `.clang-format` in each C++ host folder:

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

Format an explicit list of handwritten host and test files. Exclude generated, Flutter-managed, vendored and package code.

### 4.5 C (native audio facades)

- `lower_snake_case` files, functions, fields and locals; PascalCase named types. Header guards and ABI macros keep their established form.
- A public header presents includes, C-linkage guards, opaque and value declarations, then operations in lifecycle order. Implementation-only declarations stay as local `static` helpers or in a focused internal header.
- The exported facade is a stable ABI: function names, integer widths, pointer types, opaque handles, visibility and retention do not change during reorganization.
- Resource internals (buffers, queues, mutexes) stay with their owning module. An independently meaningful capability gets its own header and source pair. Never include `.c` files to share scope.
- Allocation pairs, CoreFoundation ownership and buffer ownership are explicit. A borrowed pointer does not escape the call that received it. A callback context is not freed until its callback boundary has finished.
- Format with clang-format: LLVM style, two-space indentation, 120 columns, attached braces and right-aligned pointers.

### 4.6 Other languages

Rust in native packages and the server, build scripts, CMake, Gradle and XML follow their own language conventions and formatters (for example `rustfmt`). The principles in Parts 1–3 still apply: named owners, shared abstractions, explicit lifetimes and readable assembly. Vendored code keeps its upstream style.

### 4.7 Formatter summary

| Language | Tool | Configuration |
| --- | --- | --- |
| Dart | `dart format` from the repository's Flutter SDK | `analysis_options.yaml` |
| Swift | `swift-format` | `ios/.swift-format`, `macos/.swift-format` |
| Kotlin | ktlint | `android/.editorconfig` |
| C++ | clang-format | `windows/.clang-format`, `linux/.clang-format` |
| C | clang-format | `macos/.clang-format` |

Every configuration targets two-space indentation, 120 columns and at most one blank line. Pin each tool version where it runs, and upgrade tools as their own change.

---

## Part 5. Process

### 5.1 Applying the standard

1. **Name the responsibility.** Identify its inputs, outputs, state and resources. Place it in its source area before choosing a base class or file split.
2. **Find the family.** Identify the relevant shell, control, workflow, controller, data operation or capability. State what must be shared and what varies.
3. **Use or establish the shared owner.** Extend or compose the existing abstraction, or extract one with explicit hooks before adding another copied variant.
4. **Implement and assemble.** Supply the specialized content, actions, rules or adapter behavior, then compose named pieces. Keep small helpers beside their operation and independent components standalone.
5. **Wire dependencies explicitly.** Pass values, children, callbacks or capabilities. Keep destinations out of components and functional work out of presentation.
6. **Preserve behavior and lifetime.** Keep defaults, public APIs, serialized formats, wire contracts, notification order, resource ownership, transaction boundaries and awaitable cleanup. Move an affected family together so common policy has one implementation.
7. **Verify.** Check the shared contract and the meaningful differences between variants.

Keep established public names when a source move alone is enough. Do not move initializers, change callback timing, expose state or alter cleanup just to make a file look ordered. Correctness fixes discovered during a refactor are separate, visible changes.

### 5.2 Review checklist

1. Location, name and dependencies match the source areas and dependency rules. Independent pieces are outside private component trees.
2. Inputs, state, construction and operations appear in the standard order. Logical paragraphs visibly separate changes of purpose.
3. Every member of a family uses its shared owner. A common design or policy change would propagate through that owner rather than through synchronized edits to copies.
4. The shared implementation holds the actual common decisions; it is not a base, interface or wrapper that leaves them duplicated.
5. Final assembly reads through named pieces and narrow contracts, without rebuilding the internals of what it composes.
6. Mutable state and collections have deliberate access rules. Async completion, error handling and resource ownership are clear.
7. Platform boundaries decode once, keep wire names exact and answer every call exactly once.
8. Formatting and static analysis pass for affected files, and behavioral checks cover material changes.

### 5.3 Verification

- Format and analyze affected files with each language's configured tools.
- Run focused tests for the changed behavior and the structural checks under `test/architecture`. The [test index](../test/README.md) lists the suites. Tests verify behavior and contracts, not helper extraction or member order. Structural checks enforce only part of this standard; passing them does not show the abstractions are right.
- The analyzer and formatters do not enforce naming, contract boundaries, assembly quality or member grouping; those need review. Change lint policy separately when there is a concrete enforcement benefit, and never suppress a warning without understanding and documenting why.
- Native hosts are verified by compilation and headless contract checks with injected capabilities. These do not exercise rendered windows, devices or system services.
- **Do not start the application, simulators, emulators, servers or background services for verification.** Compilation, static analysis and headless tests are allowed. The user owns launching software and device checks.
- Documentation-only changes need link, example and consistency checks, not a build.

### 5.4 Commits

Commit history is the source for release changelogs under `changelog/`, so every commit should explain itself to someone writing release notes.

**Scope**

- One logical change per commit. Keep refactors, formatting passes, dependency or toolchain upgrades and behavior changes in separate commits.
- A commit leaves the project formatting, analyzing and passing its relevant checks.

**Message structure**

```text
<Summary line>

<What changed, from the user's or developer's point of view.>

<Why it changed: the problem, cause or motivation.>

<Notable details: affected platforms, migrations, compatibility,
follow-up work or known limits.>

Changelog: <Added | Changed | Fixed | Compatibility | Maintenance | None>
Platforms: <all | android, ios, macos, windows, linux, server>
```

- **Summary line:** imperative mood, sentence case, no trailing period, at most 72 characters. Name the effect, not the activity: `Fix crash on deleted playlist detail page`, not `fixed stuff` or `playlist changes`.
- **Body:** wrap at 72 columns. Describe what changed and why in plain language that could be adapted into a changelog entry. Mention user-visible behavior first, then the important technical points. Omit the body only for trivial changes such as typo fixes.
- **`Changelog:` trailer:** the release-note section the change belongs to. These match the `changelog/` headings: `Added` for new capabilities, `Changed` for altered behavior, `Fixed` for bug fixes, `Compatibility` for platform, format or migration impact, and `Maintenance` for internal work worth noting. Use `None` for changes that should not appear in release notes.
- **`Platforms:` trailer:** where the change applies, so platform-specific notes can be grouped. Use `all` for shared Dart behavior.
- Call out breaking changes, data migrations and changed defaults explicitly in the body.

**Authorship**

- Commits are authored and committed by the developer's own git identity, as configured in the repository or global git configuration. Do not override author or committer with `--author`, environment variables or per-command configuration.
- Commit messages, trailers and branch names contain no tool, model or assistant attribution: no `Co-Authored-By` lines for tools, no "Generated with" lines, no product names.

**Coding agents and LLM tools**

When a coding agent or LLM tool makes changes in this repository:

- After completing a coherent set of changes, offer to commit them and wait for explicit approval. Never commit, amend, rebase, force-push or push without that approval.
- When approved, commit with the configured git identity and a message that follows the structure above. Do not set or change `user.name` or `user.email`. If no identity is configured, stop and ask the developer to configure one rather than inventing one.
- The message describes the change itself. It never mentions that an agent, LLM or tool produced it.
- Do not bypass hooks or signing.

### 5.5 Keeping this document healthy

- This is the only document that defines structure and coding standards. Do not maintain a parallel architecture guide, a per-platform style guide or a file-by-file catalog.
- Add a rule here only when it holds regardless of which feature is being built. Feature behavior, protocol contracts and platform integration details go in their own documents under `docs/` and link here.
- When a rule changes, change it here and update the code that it governs in the same piece of work, or note that adoption is incremental.
