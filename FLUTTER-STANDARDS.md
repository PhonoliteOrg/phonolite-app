# Flutter standards

This document is a portable standard for how a Flutter application's source is structured and written. It covers the Dart application code, the native platform hosts that embed it, and the native packages it calls. It is not a general standard for other kinds of project; a server, CLI or library outside the Flutter application follows its own standard. It describes how code is organized and how it reads, not what the software does.

It contains no facts about any particular project. Each project that adopts it keeps those facts in a separate [project profile](PROJECT-PROFILE.md): its source directories, hosts, tools, limits, release checklists and commit vocabulary ([2.11](#211-project-profile)). A project developed with coding agents also keeps agent instructions that turn this standard into a working procedure ([5.6](#56-agent-instructions)). To adopt the standard in another Flutter application, copy this file unchanged, remove the language sections for hosts and packages it does not have, and write a new profile and agent instructions.

The standard applies to new code and code being materially refactored. Existing source may not conform yet. Apply the standard within the responsibility you are changing, preserve behavior, and keep unrelated formatting or renaming out of a functional change.

**What does not belong here:** feature behavior, protocol details, thresholds, timings, class inventories, migration notes and change history. Those belong in feature or protocol documents, in documentation comments, or in version control. If a paragraph would become wrong when a feature changes, it belongs somewhere else. Examples are illustrative and self-contained.

1. [Principles](#part-1-principles): the rule everything else follows.
2. [Structure](#part-2-structure): where responsibilities live and what they may depend on.
3. [Code](#part-3-code): how files, types and operations read, in any language.
4. [Language conventions](#part-4-language-conventions): per-language specifics.
5. [Process](#part-5-process): applying, reviewing, verifying and committing changes.

---

## Part 1. Principles

### 1.1 Abstraction, specialization and assembly

**Shared abstractions define the general structure, design and behavior. Specialized implementations supply the parts that vary. Composition assembles those pieces into larger responsibilities.** This applies everywhere: UI, controllers, workflows, data operations, storage, runtime integration and platform hosts.

| Role | Owns | Consumers supply |
| --- | --- | --- |
| Shared abstraction | The common structure, rules, design, behavior and extension contract of a coherent family | Only the inputs and variation points that family allows |
| Specialized implementation | A particular responsibility within that structure | Its content, actions, data rules or platform-specific operations |
| Assembly | Selection, wiring and composition of pieces into a larger component or workflow | Explicit dependencies, values, children and callbacks |

These roles repeat at every scale. A section assembles controls, a page assembles sections, and the shell assembles pages and app-wide surfaces. A controller assembles workflows and data capabilities. A connection assembles endpoint clients around one shared transport. An assembled component can itself become a building block.

Consistency must come from shared code. Copying a layout, algorithm or lifecycle and keeping the copies aligned by convention does not satisfy this standard. A common interface alone does not remove duplicated policy; behavior that implementations must share needs a shared implementation owner.

### 1.2 Every concept has a named owner

Each piece of data, state, policy, resource and design decision has exactly one owner that a reader can name. Mutable state, timers, streams, workers, native handles, connections and transactions each have a single clear owner. Recurring mechanisms get small dedicated owners rather than being repeated in callers.

### 1.3 Code reads from the outside in

A reader sees the contract first, follows a readable operation or composition, and opens implementation details only when needed. Types present their inputs before their implementation. Operations read in the order their work happens. Final assembly reveals the main regions and how they relate, and names its pieces.

### 1.4 Verify, don't assume

A change relies only on behavior it has confirmed. Before using a framework, library, platform or operating-system API in a way that matters, confirm from its documentation or source:

- what its defaults are, and what an omitted or null argument means;
- whether it copies or borrows, and who owns what it returns;
- whether it blocks, and which thread or isolate it calls back on;
- what failure looks like: an exception, a sentinel value, an error reply or silence;
- whether stopping a wait (a timeout, a cancelled listener, a dropped reference) also stops the underlying work.

When a consequential decision rests on such a fact, state it in a short comment beside the code. A plausible name, a familiar pattern or code copied from elsewhere is not confirmation.

---

## Part 2. Structure

### 2.1 Source areas

Source is divided into responsibility areas. A directory identifies an owner or kind of work; a file identifies a coherent component within it. Inheritance, file size and a helper's first consumer do not decide where it lives.

| Area | Owns | Boundary |
| --- | --- | --- |
| Bootstrap | Dependency construction, startup sequence, framework entry points, root setup and shutdown | Connects the other areas. Nothing else imports or locates bootstrap |
| Pages | Final view assembly, controller binding, page-scoped visual state and concrete destinations | Uses UI components and controller APIs; delegates functional work |
| UI | Presentation components, shared frames, design system, visual interaction | Supplies building blocks to pages; never imports pages |
| Application | Controllers, shared workflows and application lifecycles | Provides functionality without owning widgets, routes, dialogs or native views |
| Data | Data definitions and the operations that naturally belong to them | One silo, independent of application and presentation |
| Infrastructure | Runtime execution, protocols, workers, native resources, platform adapters and transport | Implements technical capabilities using standalone data definitions |

Create a directory only when it has a meaningful responsibility and real contents. A feature needs only the subdirectories it uses. Abstraction, specialization and assembly happen within these areas; they are not extra top-level directories. The profile maps each area to its directory.

### 2.2 Dependency direction

| Owner | May depend on | Must not depend on |
| --- | --- | --- |
| Bootstrap | Every area it assembles | — |
| Pages | UI, application APIs, data values/projections, destination pages | Infrastructure, concrete data I/O |
| UI | Other UI, application APIs, data values/projections | Pages, bootstrap, infrastructure, concrete stores, repositories, file operations or storage configuration |
| Shared frames, toolbars, navigation | Generic UI and configuration supplied by consumers | Concrete feature controllers or widgets; toolbar and app-navigation families stay independent of each other |
| Application | Other application modules, data, infrastructure capabilities | Pages, widgets, routes, dialogs, view contexts, navigation, visual controllers |
| Data | Other data modules and necessary technical libraries; repositories may use infrastructure clients | Application, pages, UI, bootstrap |
| Infrastructure | Data definitions, technical libraries, other technical adapters | Application, pages, UI |

Avoid cycles between concrete libraries. A client that a facade constructs receives narrow callbacks for the facade's capabilities rather than importing the facade. Bind those callbacks to the facade's methods so overrides still dispatch normally.

### 2.3 Subdividing the areas

Within each area, group by subject or feature, then by role where it helps. A typical shape:

```text
<source root>/
  <entry point>                # Thin; delegates to bootstrap
  bootstrap/
  pages/<feature>/
  application/
    controllers/<feature>/     # Feature controllers
    controllers/shared/        # Shared controller mechanisms
    app/                       # Application facade and its private workflows
    workflows/                 # Reusable workflow mechanisms
    <subject>/                 # Named application modules
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
    shell/                     # Page frames, body/scroll contracts, adaptive layout
      toolbars/                # Page-level toolbars and actions
      navigation/              # App-wide destination surfaces
    structures/                # Modal, section and collection frames
    features/<feature>/        # widgets/, sections/, dialogs/ as needed
    shared/
      design_system/           # Theme, tokens, controls, surfaces, layout, icons
      <domain>/                # Shared domain presentation
    navigation/                # History, transitions and input helpers
  infrastructure/
    <capability>/              # Transport, storage engines, platform adapters, workers
```

### 2.4 Platform hosts

When the application runs inside native hosts (mobile, desktop or embedded), each host uses the same areas inside the platform's required project structure. Folder naming follows the host language's conventions (Part 4). The profile lists the hosts and their folders.

- **Hosts support the application; they do not duplicate it.** The application owns its pages, navigation and domain workflows. A native action requests work through the existing boundary. It does not reimplement business rules. A native controller may own the loading, cancellation and selection state its native view needs.
- **Application and Pages exist only when real native work exists.** Calling a platform API does not need a controller. A system-rendered surface such as a notification, widget or vehicle browse tree is UI presentation, not a page. Do not create native copies of application controllers to fill the tree.
- **Framework entry points stay thin.** Application delegates, activities, services, scene delegates and window procedures forward lifecycle events to composed owners. Dependencies are passed in at assembly, never located by searching windows or reaching through a global application object from feature code.
- **Data has no resources.** A native data value holds no window, view, channel, messenger, queue, mutex, callback, COM interface or independently released handle. A `struct` that holds those is a resource implementation and lives with its infrastructure or UI owner.
- **Tool-owned files stay tool-owned.** Generated registrants, framework-managed build glue, ephemeral output, package caches and vendored sources keep their tool or upstream ownership and style.
- **Build membership is explicit.** IDE project file references and build phases, build-system source lists, source sets and manifests are executable contracts. A file move updates its build registration, include paths, component names and resource references together.
- **Native packages keep their boundary.** Packages exposing a C ABI keep their exported symbol names, calling conventions, integer widths, units, opaque handles and matching release functions. Shared native implementation stays in its package rather than being moved into a host.

### 2.5 Pages, presentation and functionality

| Responsibility | Owner |
| --- | --- |
| Read field text, manage focus, animate, track drag or scroll position | Page or UI component |
| Validate input, filter results, decide which items are selected | Feature controller |
| Present a confirmation and display its result | Page or UI component |
| Execute the approved deletion, save or other action | Application controller or workflow |
| Describe an action result, destination or data snapshot | Data model or projection |
| Construct a route to a concrete page | Page |

**Pages** assemble complete views. Every tab root, detail screen, settings subpage, home view and splash view is a page, whatever its class-name suffix. A page selects components, binds their data and callbacks, presents confirmations and chooses concrete destinations. Components it uses do not know which page implements a destination; the page supplies callbacks.

**UI components** receive values, state, children and typed callbacks. They own layout, animation, hover, focus, framework text/scroll/animation controllers, drag state, modal presentation and dismissal. A component may deserve its own file even when one page uses it, if it has a recognizable responsibility.

**Controllers** own validation, loading and errors, functional selection, filtering, pagination, debouncing, asynchronous commands, request generations and stale-result guards. For example, a widget owns its scroll controller and reports the remaining extent; the controller decides whether to load more. Controller results describe values or destinations, never widgets or routes. A page controller must not create another instance of an application-wide runtime such as an engine, cache or job manager.

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

**The shell owns the page frame.** The shell provides the shared page base. Pages supply their toolbar and body through its assembly hook and choose a body form (bounded box, scrolling box or lazy list) and a toolbar placement (scrolling or fixed). The base owns page-level scaffolding, scroll views, padding, safe areas and overlay clearance. A page does not build its own page-level scaffold or scroll view and does not override the base's assembly. Scrollable regions inside a content component remain legitimate. Page toolbars and app-wide destination navigation are separate families that do not import each other.

Reactive pages keep their stream or observable builder around the assembly call and produce both toolbar and body from one snapshot, instead of subscribing twice.

### 2.7 Data and its operations

All application and technical data definitions live in the data silo: entities, immutable values, enums, settings, response records, controller-facing results, worker messages, native ABI records and mutable containers. Widget configuration, visual tokens and purely visual state stay in UI.

Data may construct, parse, serialize, copy, validate, derive, query, mutate, open and save itself. Keep a small helper on its data type; give substantial persistence or shared access a named store or repository. Application-dependent preparation stays in a controller, which supplies the values to a result or snapshot constructor. A result model never reaches back into the controller or runtime that consumes it. A data method never acquires a UI context, navigates or assembles widgets.

Related stores share persistence and transaction mechanisms. Recurring parsing, comparison and mutation rules with the same meaning have one shared helper or container. Each definition has one physical source home; a facade may re-export a type but not duplicate it. Necessary technical dependencies are explicit: ABI records may use FFI types, and worker messages may carry ports or channels.

### 2.8 Independent components and private component trees

A file boundary represents a responsibility someone can name. Independent models, parsers, buffers, adapters, controls and helpers are ordinary modules with normal imports. A component's first consumer does not own the modules it uses.

When several pieces serve the same feature, identify who assembles them. If callers select or compose two pieces independently and each has a distinct responsibility, give each its own file in the feature directory. Keep a private implementation detail beside the component that owns it. Apply this rule when extracting or moving existing code as well as when adding new code.

A private component tree exists when one cohesive module deliberately shares private scope across several files (for example Dart `part` files). Such a component has an exclusive directory holding its entry point and only its own private parts. Independent source stays outside that entire tree.

```text
data/models/<subject>/<value>                 # Standalone data
data/structures/<subject>/<buffer>            # Standalone container
infrastructure/<capability>/protocol/         # Standalone parsing
infrastructure/<capability>/engine/
  <engine entry point>                        # Component entry point
  <responsibility>/                           # Its private parts only
```

Splitting a file into private parts only separates text. It does not create a reusable abstraction or remove duplication. A reusable policy needs its own responsibility and contract outside the private tree. A policy shared only by private parts of one module may stay a private owner there. Forwarding layers that preserve a facade's calls carry no behavior of their own.

### 2.9 Runtime and resource ownership

| Boundary | Ownership |
| --- | --- |
| Remote services | Endpoint clients share one transport that owns session, authentication, trust, retry and request policy; payload records live in data |
| Device preferences | One application-wide preferences owner loads remembered choices, publishes their current values and changes, and coordinates saves through typed stores. Features request changes through that owner and apply them to their runtime. Preserve account scoping and storage transactions when a preference shares a record with other state. |
| Application session | One owner publishes read-only session status and account identity and coordinates sign-in, restoration, sign-out, and credential writes. Features report discovered identity with its session revision. The owner verifies that revision before accepting it. |
| Workers | The parent owns communication and recovery; the worker owns its active session; the session owns its handles and cancellation |
| Persistence | Stores share their database connection and transaction boundary; splitting source never opens extra connections or splits an atomic operation |
| Views | Pages and components own their visual controllers and the feature controllers they bind; application-wide state keeps its application owner |
| Platform host | The process host owns process-wide services; an engine or runtime binding owns its channels; a scene or window owns its presentation; a request owns its cancellation and completion |

- Give features an account scope for account-owned data and a session revision for checking asynchronous results. Keep remembered identity available during temporary loss of connectivity. Bind credentials to authenticated requests in the transport that sends them, including native transports.
- Constructors establish local invariants synchronously and perform no externally visible I/O. Explicit initialization starts workers and I/O.
- Create private state owners with their parent before subscriptions when scheduling order depends on construction.
- The creator owns disposal unless ownership is explicitly transferred. Borrowed resources stay owned by their provider.
- Cleanup is idempotent and awaitable where the resource requires it.
- When a lifecycle or execution protocol is common to a family, its shared owner enforces it. Variants supply resource-specific work through that contract; they do not each carry a copy of initialization, cancellation or cleanup policy.
- Sharing an abstraction does not mean sharing a mutable instance. Bootstrap or the parent assembly decides lifetime and instance count.
- Reorganization preserves initialization order, request generations, stale-result guards, serialized writes, scoping, migrations, cancellation and worker command ordering.
- **Anything started answers four questions.** A worker, request, stream, timer, subscription or native handle has a defined answer to: who stops it, what bounds it in time, what happens to its waiters if it dies, and what still runs if one cleanup step fails.
- **Supervise every worker.** A spawned worker, isolate, process or thread has error and exit observation from the moment it starts. When it exits, every pending request fails and the parent forgets it, so the next request starts a fresh one. Children are bound to their parent's lifetime explicitly; runtimes generally do not stop children when a parent dies. A failed spawn releases what it allocated.
- **A command failure does not kill its worker.** A worker's command loop contains each command's failure and reports it. Replies the parent waits for are sent from a `finally` path.
- **Native resources have a safety net.** An object owning native memory or handles registers a finalizer bound to the native release function and detaches it on explicit close. A finalizer never blocks: it does not join threads or wait for I/O.

### 2.10 Cross-language boundaries

Message channels between the application and native code (platform channels, IPC, bridges) follow one pattern on every side:

- **The adapter owns the wire.** Channel and method names, codec values, untyped maps, result objects, error envelopes and unknown-method handling live in the channel adapter. It decodes once into typed values and delegates to typed capabilities. Capabilities never construct codec values or reply objects.
- **Wire names stay exact.** Channel names, method names, keys and discriminator values are contracts. A native method may be named idiomatically while its wire method keeps its spelling.
- **Every incoming call is answered exactly once,** including on failure, cancellation, unknown methods, shutdown and when the owning object has been released.
- **Completion meaning is stated.** Accepting a request is not the same as finishing it: requesting a permission does not mean it was granted, and launching a file browser does not mean it finished displaying.
- **Attachment is idempotent per binding.** Handlers are unregistered explicitly while their messenger is still valid, before the captured owner is destroyed. Replacing an engine is an explicit detach and rebind.
- **Threads have owners.** UI mutation and outbound channel calls happen on the platform main thread. Work from other threads is delivered through an explicit dispatcher with defined lifetime and relevance rules. A reply callback's threading permission is not permission to mutate UI.
- **Shared mechanics are extracted when a family exists.** Once several adapters share registration, invocation, reply and teardown decisions, a shared channel collaborator owns them. Each adapter keeps its own methods and decoding.
- **Realtime paths stay lean.** Audio, video and render callbacks receive no logging, main-thread hops, channel messages or general task scheduling.
- **Failures never cross a boundary as crashes.** Panics, exceptions and aborts are caught at every exported entry point and converted to the boundary's error convention. A handle that faulted is marked unusable.
- **A missing native library fails loudly.** Loading checks for an expected symbol and reports the path it expected. It never falls back silently to a process-wide lookup that fails later with an unrelated error.
- **Return values are checked before use.** Every native result's failure sentinel is checked before the value is used, especially before arithmetic on sizes and counts held in unsigned types.
- **Secrets and allocators are handled deliberately.** Secrets copied into native memory are zeroed before they are freed. Memory is freed with the allocator that allocated it.
- **Handlers re-check their owner.** Every message handler or callback that can run after teardown checks that the window, engine or controller it uses still exists. Delivery thread is confirmed from the platform's documentation, never assumed.

Adapters on the application side mirror this: they decode channel methods into typed requests, encode typed responses, and keep method strings out of application workflows. Their contracts live in data.

### 2.11 Project profile

The same separation of general rules from specific values applies to the project's own documentation. **This standard is the shared abstraction; the project profile is the specialization.** Every project keeps one profile document, `PROJECT-PROFILE.md` at the repository root, beside this standard and the agent instructions. The profile states how the project instantiates the standard and adds no new rules.

The profile has these sections, in this order. Omit a section only when it does not apply.

| Section | Contents |
| --- | --- |
| Project | What the project is, its targets (apps, hosts, services, libraries), the languages in use, and any neighboring projects outside the standard |
| Source areas | A table mapping each source area ([2.1](#21-source-areas)) to its directory, plus any project-specific subdivisions |
| Native hosts | Each host's location, source extensions and the area folders it currently uses |
| Tools and configuration | Formatter, analyzer and linter for each language, with the location of each configuration file and any documented rule exceptions |
| Limits and enforcement | File-size limits, the agent instructions' length limit and other measurable limits, and where structural checks and test indexes live |
| Release readiness | Each host's release checklist ([2.12](#212-host-release-readiness)) |
| Commit vocabulary | The `Changelog:` categories and `Platforms:` values that commits use ([5.4](#54-commits)) |

Rules for keeping the two documents apart:

- A statement that would stay true in another project belongs in the standard. A statement that names this project's paths, hosts, tools, versions or vocabulary belongs in the profile.
- When the profile would need a rule, generalize it into the standard first. The profile then records only the value.
- Tools that read project structure, such as structural tests, read the profile's tables rather than the standard.
- Feature behavior and protocol contracts belong in neither document.

### 2.12 Host release readiness

Platform defaults are often wrong for a shipped application, and nothing fails until release, store review or a user's device. Every host has a release-readiness checklist in the project profile. Each checklist covers, where the platform has them:

- **Signing.** Release builds use release credentials and fail rather than fall back to development keys.
- **Backup and transfer.** An explicit policy for whether local data, downloads and credentials are backed up or moved to a new device. Encrypted data whose keys do not travel with it is excluded.
- **Privacy declarations.** Required privacy manifests, required-reason API declarations, permission usage strings and data-collection disclosures.
- **Exposure.** Which components are exported to other applications and which callers they accept.
- **Background behavior.** Service start and restart policy, and every obligation a background start creates, such as posting a notification in time.
- **Shared system resources.** Behavior toward other applications: audio session category and activation, audio focus, ducking and interruption handling.

A change that adds or changes a host capability updates that host's checklist in the same piece of work.

---

## Part 3. Code

These rules apply in every language. Part 4 states how each language expresses them.

### 3.1 Files

- Name files for their responsibility or primary type. A file has one primary public concept. Its small private state class, adapters and tightly coupled helpers may sit beside it.
- File boundaries follow responsibilities, not one-function-per-file. Extract a piece when it has a meaningful contract, independent reuse, its own state or lifecycle, or a substantial responsibility that obscures its owner.
- No dumping grounds: no `helpers`, `common`, `utils` or `misc` files or folders.
- File length is a signal to inspect responsibilities, not a target. The profile sets the review limit. A short file can still hold too many responsibilities.
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
label(rawTitle, rawOwner):
  title = trim(rawTitle)
  owner = trim(rawOwner)

  if title is empty:
    return "Untitled"

  if owner is missing or empty:
    return title

  return owner + " — " + title
```

Do not put a blank line after every statement, inside braces or in stacks. Comments sit directly above the paragraph they explain. Documentation and annotations stay attached to their declaration. If a method has many substantial paragraphs, some of them probably deserve named operations.

Other layout rules:

- One blank line between members and logical member groups; related fields stay compact.
- Braces on every control-flow body, including one-line guards. Arrow or expression bodies for a clear single expression or delegation.
- A ternary only for a small obvious choice. Replace nested ternaries with named decisions, `if` statements or a `switch`.
- Builder configuration: one configuration call per line, terminal `build()` last.
- No trailing whitespace; files end with a newline.

### 3.4 Naming and visible contracts

- Names describe domain concepts and operations: `ExportSettings`, `renameProject`, `cancelUpload`, `selectedItemIds`. Avoid `manager`, `data`, `obj`, `handle`, `process` and invented abbreviations when a specific responsibility is known. Short loop variables are fine when local.
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
- **Search before writing a mechanism.** Never hand-write an encoder, escaper, query-string builder, enum-name parser, byte accumulator, retry loop, serial queue, request generation or text truncation when the language, framework or an existing project owner provides one. Writing a new one requires a stated reason the existing ones do not fit.
- **Model distinct states distinctly.** One value never carries two meanings, such as what the user intends and what an engine is currently doing. Do not infer one state from another that merely correlates with it. When two sources can disagree, keep two values and name both.
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
- On pointer-driven platforms, enabled click targets use the hand cursor; disabled controls keep the arrow, text inputs the text cursor, and passive surfaces advertise no action. Shared controls own this.
- **Shared controls own accessibility.** An interactive control gets focus, keyboard activation, a visible focus state, its semantic role, a label and any toggle state from the shared control layer. An icon-only control requires a label. Never build an interactive control from a raw gesture recognizer alone. Do not announce a label twice through nested semantics or tooltips.
- **Respect user settings.** Animations honor the platform's reduced-motion setting. A region containing text has a minimum size that grows with text scaling, never a fixed height. Credential fields declare autofill hints and commit them only after a successful sign-in.
- **Keep the tree's shape stable.** A component returns the same structure on both sides of a breakpoint or mode change and toggles behavior through parameters. Swapping subtrees discards their state.
- **Read values inside the listener that keeps them current.** A callback that captures observable state is created inside the builder that listens to that state.
- **Navigation discipline.** Choose the navigator explicitly and use the same one for every adaptive form of a modal. After an awaited action, close a route only if it is still the current route. Back handling goes through the route's pop disposition, never an unconditional pop. Routes that navigation compares are named.
- **Animate paint, not layout.** Frequently changing visuals are painted inside a repaint boundary without changing layout. Components depend on the narrowest aspect of inherited data they read. Images are decoded at their display size. Large payloads are decoded once, away from the UI thread.

### 3.9 Async work, errors and resource lifetime

- An API states what completion means. Await what an operation promises to finish, return its future or promise, or document that it only schedules work and provide a way to observe the result. A save is not complete before its write finishes.
- Asynchronous commands return an awaitable type. Fire-and-forget work is deliberate, named as such, and has handled errors and lifetime; it never replaces required cleanup or persistence.
- For genuinely streamed state, expose a read-only current snapshot plus a typed change stream. State whether it supports multiple listeners, replays, which errors it emits and who closes it. One-off commands stay awaitable operations.
- Choose sequential, latest-result or concurrent event processing explicitly. Asynchronous listener callbacks do not serialize events by themselves. Cancellation, generation invalidation and timeouts are different things; ignoring a stale result or timing out does not stop the underlying work.
- After a suspension point, re-check relevance: mounted state, request generation, scene or engine identity, cancellation. Isolation alone does not establish relevance.
- Catch errors where the owner can recover, translate them into a meaningful result, or report an actionable failure. Preserve stack traces. Never silently catch everything or return a success-shaped default after a failed required operation. A best-effort fallback is intentional, narrow and documented. User-facing messages belong to presentation; diagnostics belong to the logging owner. Never log credentials, tokens or proofs.
- **Catch-all handlers justify themselves.** A handler that catches everything either rethrows, records the failure through the logging owner, or carries a comment saying why the failure does not matter. An empty catch body is never acceptable. Failed is not empty: a failed load does not return an empty list.
- **Error messages keep their cause.** A message names one cause and carries the underlying error. Never replace a specific failure with a message that covers several possible causes.
- **Every wait on I/O is bounded, and a timeout stops the work.** Network reads use an idle timeout that restarts on progress, so half-open connections are detected. On timeout, abort the underlying request or connection, not only the wait. Error bodies and other untrusted responses are read up to a size limit and decoded leniently.
- **Independent cleanup steps are isolated.** In teardown and shutdown each release runs even if an earlier one failed. Shutdown cancels in-flight work first, then waits with a bound.
- **Chained work isolates failures.** A queue or promise chain never lets one failure skip later work or leave errors unhandled on its tail. Return to a caller only the outcome that caller asked for, not a shared in-flight operation whose failure belongs to another caller.
- **Fire-and-forget calls handle their own errors** where they are issued.
- **Global error reporting is installed before the UI starts.** Uncaught synchronous, asynchronous and framework errors go to the logging owner. A startup failure shows a recoverable screen rather than rethrowing before the UI exists.
- Remove listeners, cancel subscriptions and timers, and release native handles when their owner ends. Release temporaries on success and failure (`try`/`finally`, `defer`, RAII, scoped cleanup). When a borrowed dependency can be replaced, detach from the old one and attach to the new one.
- Synchronous disposal cannot wait for asynchronous work. Provide an explicit asynchronous shutdown boundary and await it at the right lifecycle level.
- Weak captures are for real cycles or borrowed lifetimes. A released owner must still complete any outstanding obligation such as a channel reply.

### 3.10 Documentation and comments

- Document public contracts whose meaning is not obvious from the signature: invariants, units, ownership, completion guarantees, errors, defaults and extension hooks. Link related declarations with the language's documentation references.
- Comment consequential implementation decisions with a short *why*.
- Do not narrate syntax, keep commented-out code, label a component as new, use decorative banners, or accumulate change history in comments.
- No README files inside source trees. Project-wide expectations live in this document; feature and protocol contracts live in their own documents.

### 3.11 Text, locale and identity

- Text length, truncation and cursor positions count user-perceived characters (grapheme clusters), never code units or bytes. Limits on editable text use the framework's input-limiting mechanism, so input-method composition is not interrupted.
- Case folding, trimming and normalization used for identity comparison happen in one owner, with Unicode-aware rules, on both sides of the comparison. Do not split a comparison between a database function and application code.
- Dates, times and numbers shown to users are formatted through the locale-aware formatter for the user's region, with the framework's localizations registered.

### 3.12 Durable data

- A file that must survive a crash is written to a uniquely named temporary file in the same directory and renamed over its target. Writes to one file are serialized through a single owner.
- A multi-statement migration or backfill runs in one transaction together with its completion marker. A statement inside a loop is prepared once.
- A live database is copied with the engine's own snapshot mechanism into a temporary file, then renamed into place. Never copy its files directly.
- **Destructive cleanup acts only on confirmed absence.** "Not readable right now" (an unmounted drive, a locked keystore, a transient I/O error) is not "gone" and never deletes user data, references or credentials. When a stored item cannot be decrypted or parsed, distinguish a permanent failure from a transient one before resetting anything.
- A deferred delete checks that nothing references its path again before it runs, because deterministic paths are reused.
- Untrusted or corrupt stored data produces an error result, never a crash.

---

## Part 4. Language conventions

Dart and Flutter (4.1) is the core of this part. The other sections cover the languages a Flutter application uses in its native platform hosts and native packages, and they apply only to that code. Remove the sections for hosts and packages a project does not have. Add a section only for a language that becomes a significant part of the application's hosts or native packages. Each section restates Parts 1–3 only where the language needs a specific form.

### 4.1 Dart and Flutter

**Files and imports**

- Files and directories are `lower_snake_case`, matching the primary type: `export_settings.dart`.
- Import groups, separated by one blank line and alphabetized within each: `dart:` libraries; Flutter and third-party packages; this package's own libraries. Test-harness relative imports, when needed, form a final group.
- Every import and export of a file under a package's `lib/` uses a `package:` URI, including same-directory files, conditional imports and imports from tests. Enable the analyzer's `always_use_package_imports` rule; review exports and conditional targets explicitly.
- Exports have their own sorted section after imports. Prefer importing a role-specific owner over a broad export facade.
- `part` and `part of` directives are relative to their owning library. A part file starts with `part of`; imports belong to the owner. `part` is used only for an intentional shared private implementation (see [2.8](#28-independent-components-and-private-component-trees)).
- Production source never imports test harnesses or another package's `src/` implementation.

**Language rules**

- A leading underscore is **library-private**, not class-private: a library and its parts share it. Choose library boundaries with that in mind.
- `lowerCamelCase` for members, variables, enum values and constants; acronyms as words (`itemId`, `httpClient`).
- Prefer `final` locals and `const` constructors and values. `late` only for a real delayed-initialization invariant. Do not use `!` to bypass uncertainty.
- Avoid `dynamic`; accept `Object?` at untyped boundaries and decode there.
- Prefer `VoidCallback`, `ValueChanged<T>` or a descriptive `typedef` over `Function`.
- Asynchronous commands return `Future<void>`; never declare `async void`. A `VoidCallback` can delegate to a separate awaitable operation, and the boundary that does not await handles its errors. Use `unawaited` only for deliberately detached, error-handled work.
- Use `sync*` and `async*` for intentionally lazy sequences and keep their deferred errors and cancellation explicit.
- Records use named fields and serve local groupings and private helper results; a reused concept becomes a model class. A type alias does not create a nominal type. Records compare structurally; a class replacing one compares by identity until it implements equality.
- Implement the nullable tri-state in `copyWith` with an omission sentinel compared by `identical`.
- Widget helpers need not use a `_build` prefix; `_renameButton` and `_emptyState` describe their pieces. Be consistent within a family.
- Extension methods give focused conveniences to external types (`Duration`, `BuildContext`). Shared extensible structures use real inheritance or composition.
- Application-area code may import `package:flutter/foundation.dart` for notifications and nothing else from Flutter.

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
- Feature controllers extend a shared controller base, keep construction inert and put startup in its initialization hook. A shared view binding initializes, observes and disposes controllers a view owns.
- `State.dispose()` is synchronous. Asynchronous shutdown happens at an owner boundary that can be awaited.
- After an async gap, check `BuildContext.mounted` before using that context, or `State.mounted` before updating that state. A guard on a different owner does not protect the context in use.
- A dismissed route stays mounted through its exit animation; `mounted` alone does not show that a route may still be popped. Check `ModalRoute.isCurrent`.
- Install `FlutterError.onError` and `PlatformDispatcher.onError` before `runApp`. Observe the app lifecycle with `AppLifecycleListener` rather than mixing in `WidgetsBindingObserver`.

**Known traps**

These are confirmed instances of [1.4](#14-verify-dont-assume) for Dart and Flutter. Add to the list when review finds another.

| Trap | Use instead |
| --- | --- |
| A Material 3 `ColorScheme.dark`/`light` built from a few roles leaves the rest at Material 2 defaults | `ColorScheme.fromSeed`, then override the roles the design specifies |
| `Future.timeout` stops waiting but leaves the request running | An abortable request whose abort trigger completes on timeout; `Stream.timeout` on body streams |
| Isolates spawned without ports die silently; children outlive their parent; an `async` listener in an `errorsAreFatal` isolate dies on any throw | `onError` and `onExit` ports, an exit listener on the parent, and a guarded command loop |
| `MediaQuery.of` rebuilds on every change, including each keyboard animation frame | `MediaQuery.sizeOf`, `paddingOf` and the other aspect accessors |
| `SelectableText` runs its own selection and does not join a `SelectionArea` | Plain `Text` inside the area |
| Passing both target dimensions to `instantiateImageCodec` forces that size and upscales | `instantiateImageCodecWithSize`; `cacheWidth`/`ResizeImage` for list images |
| Truncating text with `substring` in a controller listener splits characters and breaks IME composition | `LengthLimitingTextInputFormatter` and `package:characters` |
| `http.Response.body` decodes the whole body on every read | Decode `bodyBytes` once with a fused UTF-8 and JSON decoder, inside `Isolate.run` for large bodies |
| `sublist` already copies; wrapping it copies again | Use the result directly |
| A `List<int>` used as a byte buffer stores each byte as a full element | `BytesBuilder` |
| Hand-written enum-name parsing | A cached `values.asNameMap()` |
| `Timeline.startSync` spans held across `await` overlap and close each other | `Timeline.timeSync` for synchronous work, `TimelineTask` across awaits |
| `dart:io` `Platform` checks cannot be overridden in tests and fail on the web | `defaultTargetPlatform` |
| A wrapper defaulting `autofillHints` to `null` disables autofill | Default to an empty list, as `TextField` does |
| A runtime font loader for fonts already bundled registers a second copy and loads it asynchronously | Name the bundled families directly |
| A package used directly but resolved transitively | Declare it in `pubspec.yaml` |

**Analyzer rules.** Enable the rules that mechanically check parts of [3.9](#39-async-work-errors-and-resource-lifetime): `empty_catches`, `avoid_catches_without_on_clauses`, `unawaited_futures`, `discarded_futures`, `use_build_context_synchronously`, `cancel_subscriptions` and `close_sinks`. Fix their findings rather than suppressing them wholesale; adopting them is its own change ([5.3](#53-verification)).

**Formatter**

In `analysis_options.yaml`:

```yaml
formatter:
  page_width: 120
  trailing_commas: automate
```

Run from the package root: `dart format lib` to apply, `dart format --output=none --set-exit-if-changed lib` to check. Do not switch to trailing-comma preservation or add per-file width overrides. The one permitted suppression is paired `// dart format off` and `// dart format on` around a fluent builder chain, so each configuration call keeps its own line.

### 4.2 Swift

**Files and modules**

- `UpperCamelCase.swift` filenames matching the primary type; PascalCase responsibility folders that match Xcode groups.
- File order: imports, tightly related contract declarations, primary type, then focused same-file conformance extensions and tightly coupled supporting types.
- Imports name modules, not paths. Group Apple and standard modules, then third-party dependencies, then project modules; sort within groups; import only what the file uses. A folder inside a target is not a module. Introduce a separate framework or package only when reuse or a compiler-enforced boundary justifies it.
- Moving a file updates its Xcode target membership, build phases, and any plist, entitlement, storyboard, nib or bridging-header references. Nib and storyboard class and module names are contracts.

**Types and access**

- Member order is the shared order in [3.2](#32-member-order). Superclass lifecycle overrides stay on the primary declaration. Keep equality, hashing and description together near the end.
- `lowerCamelCase` members with meaningful argument labels: `loadItems(scope:)`, `openDirectory(at:)`. Swift initialisms are fine (`imageURL`, `deviceID`); wire keys keep their exact spelling.
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

- Give every mutable owner one documented isolation domain. UIKit and AppKit presentation and outbound bridge calls run on the main thread.
- Prefer explicit `@MainActor` and actors within a deliberate concurrency change, against the verified toolchain and language mode. Do not add `Task` wrappers to every callback, unchecked `Sendable` conformances or a language-mode change to reorganize source.
- `await` allows interleaving: re-check generation, identity and cancellation afterwards.
- Use `defer` for synchronous scope cleanup and an explicit awaitable stop for asynchronous shutdown; `deinit` cannot await.
- Keep timing-sensitive C or Objective-C media paths separate from Swift orchestration.

**Formatter**

`swift-format` with a `.swift-format` file per Swift project:

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

Format handwritten Swift only. Pin the formatter version on the build environment before enforcing it.

### 4.3 Kotlin

**Packages and files**

- Lowercase dot-separated packages matching folders; PascalCase files and types; `lowerCamelCase` members; `UPPER_SNAKE_CASE` constants. Android XML resources keep lowercase underscore names and qualifier folders.
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

ktlint with an `.editorconfig`:

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

### 4.4 C++

**Naming**

| Item | Convention | Example |
| --- | --- | --- |
| Files and directories | `lower_snake_case`, with the host's established source extension (`.cpp` or `.cc`) | `infrastructure/shell/directory_launcher.cpp` |
| Types and aliases | `PascalCase` | `DirectoryLauncher` |
| Functions, methods, parameters, locals | `snake_case` | `open_directory`, `folder_path` |
| Namespaces, scoped enum values | `snake_case` | `app`, `Status::accepted` |
| Private members | `snake_case_` | `owner_window_` |
| Constants | Descriptive `snake_case`, `constexpr` where suitable | `default_window_width` |

External API names, generated entry points, framework override names, callback signatures and calling conventions stay exact.

**Headers and includes**

- Headers are self-contained, guarded and include what they use; prefer forward declarations where an incomplete type suffices.
- A class holding `std::unique_ptr` to a forward-declared type defines its destructor, and constructors where cleanup paths require it, out of line.
- Substantial implementation goes in the source file; short value operations may be inline.
- Include order in a source file: its own header, then standard library, platform SDK, framework and third-party, then project headers, each group sorted. Document any required ordering exception.
- Project headers are included from a configured include root (`"runner/data/models/..."`), never through `../../` chains or absolute paths. Framework headers use their published names.
- No `using namespace` in headers; keep aliases local. Small private helpers go in an unnamed namespace. Never include source files to share private scope.

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
- Use named result types for shared outcomes, and `std::optional` or `std::variant` where the configured language standard provides them. Changing the language standard is a separate build change.
- Keep platform status families distinct (`HRESULT`, last-error codes, Shell results, `GError`). Preserve native error values that callers need.
- Exceptions never cross C callbacks, framework boundaries or exported C ABI functions. Keep the configured exception policy.

**Resources**

- Value members and `std::unique_ptr` for sole ownership, created with `std::make_unique`. `std::shared_ptr` only for real shared lifetime, never to make asynchronous captures convenient. Follow the rule of zero; define or delete copy and move deliberately for resource owners.
- RAII pairs a resource with its matching release, invalid value, thread and transfer rules. A raw handle value does not establish ownership. Release every allocation with its matching function and never across allocators.
- Explicit lambda captures. Capturing `this` does not extend its lifetime. No detached threads, broad `[&]` captures or work that outlives the engine or runtime.
- Destroying a channel object does not necessarily unregister its handler; unregister explicitly while the messenger is valid.

**Win32 and COM**

- COM initialization belongs to a thread and apartment; balance every successful initialization, including `S_FALSE`, on the same thread, and keep COM-dependent objects inside that lifetime.
- The native frame owns its top-level window lifecycle; a hosted child window is borrowed.

**GTK and GObject**

- GObject types keep GObject naming and registration conventions (`MyType`, `my_type`, `MY_TYPE`, `parent_instance`). Do not place macro-generated declarations in a C++ namespace without checking linkage.
- A GObject instance is allocated through GType, not C++ construction. Do not embed non-trivial C++ members in an instance struct; hold a pointer to an explicitly constructed C++ owner and destroy it through the GObject lifecycle.
- `dispose` may run more than once: detach handlers and signals while dependencies are valid, clear owned pointers, chain to the parent. `finalize` handles remaining storage and chains.
- Use `g_autoptr` and `g_autofree` at scope boundaries. Widget destruction and reference release are different operations. Copy a `GError` message before freeing it.
- A signal connection does not extend its user data's lifetime. Own and disconnect handler IDs. Avoid channel → callback → owner → channel cycles.
- Do not add empty lifecycle overrides just to match a template.

**Formatter**

clang-format with a `.clang-format` file per C++ project:

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

Format an explicit list of handwritten files. Exclude generated, framework-managed, vendored and package code.

### 4.5 C

- `lower_snake_case` files, functions, fields and locals; PascalCase named types. Header guards and ABI macros keep their established form.
- A public header presents includes, C-linkage guards, opaque and value declarations, then operations in lifecycle order. Implementation-only declarations stay as local `static` helpers or in a focused internal header.
- An exported facade is a stable ABI: function names, integer widths, pointer types, opaque handles, visibility and retention do not change during reorganization.
- Resource internals (buffers, queues, mutexes) stay with their owning module. An independently meaningful capability gets its own header and source pair. Never include `.c` files to share scope.
- Allocation pairs, platform reference-counting ownership and buffer ownership are explicit. A borrowed pointer does not escape the call that received it. A callback context is not freed until its callback boundary has finished.
- Format with clang-format: LLVM style, two-space indentation, 120 columns, attached braces and right-aligned pointers.

### 4.6 Other languages

Other languages inside the application (for example Rust in native packages, build scripts, CMake, Gradle and XML) follow their own conventions and formatters. Parts 1–3 still apply: named owners, shared abstractions, explicit lifetimes and readable assembly, and native packages keep the boundary rules in [2.10](#210-cross-language-boundaries). Vendored code keeps its upstream style. Add a section here when such a language becomes a significant part of the application's hosts or native packages.

### 4.7 Formatter baseline

Every formatter configuration targets two-space indentation, 120 columns and at most one blank line. Pin each tool version where it runs and upgrade tools as their own change. The profile lists where each configuration lives.

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

**Diagnose before changing.** For a defect that cannot be explained from the code, first reproduce it or add instrumentation that separates the candidate causes. Do not commit speculative fixes. If an attempt does not confirm the cause, revert it before trying the next.

**Fix the class, not the instance.** When a defect is found, name the mistake that caused it, search the codebase for every other occurrence of that mistake, and fix them together or list the remaining ones in the commit body.

**Measure performance changes.** A change motivated by performance states the measurement that motivated it and the measurement after it, on the affected hardware class.

### 5.2 Review checklist

1. Location, name and dependencies match the source areas and dependency rules. Independent pieces are outside private component trees.
2. Inputs, state, construction and operations appear in the standard order. Logical paragraphs visibly separate changes of purpose.
3. Every member of a family uses its shared owner. A common design or policy change would propagate through that owner rather than through synchronized edits to copies.
4. The shared implementation holds the actual common decisions; it is not a base, interface or wrapper that leaves them duplicated.
5. Final assembly reads through named pieces and narrow contracts, without rebuilding the internals of what it composes.
6. Mutable state and collections have deliberate access rules. Async completion, error handling and resource ownership are clear.
7. Cross-language boundaries decode once, keep wire names exact and answer every call exactly once.
8. Formatting and static analysis pass for affected files, and behavioral checks cover material changes.
9. API behavior the change relies on is confirmed ([1.4](#14-verify-dont-assume)); everything started has an owner, a bound and an exit path; failures are neither swallowed nor turned into empty results.
10. A fix addresses every occurrence of its mistake and has a regression test that fails without it.

### 5.3 Verification

- Format and analyze affected files with each language's configured tools.
- Run focused tests for the changed behavior and the project's structural checks (see the profile). Tests verify behavior and contracts, not helper extraction or member order. Structural checks enforce only part of this standard; passing them does not show the abstractions are right.
- Analyzers and formatters do not enforce naming, contract boundaries, assembly quality or member grouping; those need review. Change lint policy separately when there is a concrete enforcement benefit, and never suppress a warning without understanding and documenting why.
- Native hosts are verified by compilation and headless contract checks with injected capabilities. These do not exercise rendered windows, devices or system services.
- **Tests exercise behavior, not source text.** A test must fail when the behavior breaks and keep passing through a harmless refactor. Tests do not read source files and assert that they contain or omit particular strings. The one exception is a build or packaging contract that cannot be executed headlessly, such as exported symbols or manifest entries, and such a test parses the structure rather than matching substrings.
- **Every fix ships a regression test that fails without the fix.**
- **A rule that keeps being broken gets a mechanical check.** When review finds a rule of this standard broken more than once, add or enable an analyzer rule, lint or structural test for it.
- **Do not start the application, simulators, emulators, servers or background services for verification.** Compilation, static analysis and headless tests are allowed. The developer owns launching software and device checks. For anything only a running application can show (layout, focus, scrolling, large text, reduced motion, device changes), the author lists the specific checks the developer should perform.
- Documentation-only changes need link, example and consistency checks, not a build.

### 5.4 Commits

Commit history is the source for release changelogs, so every commit should explain itself to someone writing release notes.

**Scope**

- One logical change per commit. Keep refactors, formatting passes, dependency or toolchain upgrades and behavior changes in separate commits.
- A commit leaves the project formatting, analyzing and passing its relevant checks.
- Build outputs, native target directories and generated caches are ignored before the first build of a new component.
- A dependency change regenerates every affected lockfile in the same commit. Toolchain minimums required by a framework upgrade are raised in the same change as the upgrade.

**Message structure**

```text
<Summary line>

<What changed, from the user's or developer's point of view.>

<Why it changed: the problem, cause or motivation.>

<Notable details: affected platforms, migrations, compatibility,
follow-up work or known limits.>

Changelog: <category from the profile, or None>
Platforms: <scope from the profile>
```

- **Summary line:** imperative mood, sentence case, no trailing period, at most 72 characters. Name the effect, not the activity: `Fix crash when opening a deleted item`, not `fixed stuff` or `item changes`.
- **Body:** wrap at 72 columns. Describe what changed and why in plain language that could be adapted into a changelog entry. Mention user-visible behavior first, then the important technical points. Omit the body only for trivial changes such as typo fixes.
- **`Changelog:` trailer:** the release-note section the change belongs to, using the categories listed in the profile. Use `None` for changes that should not appear in release notes. Projects without their own categories use `Added`, `Changed`, `Fixed`, `Removed`, `Compatibility` and `Maintenance`.
- **`Platforms:` trailer:** where the change applies, using the values listed in the profile, so platform-specific notes can be grouped. Projects with one target may omit it.
- Call out breaking changes, data migrations and changed defaults explicitly in the body.

**Authorship**

- Commits are authored and committed by the developer's own git identity, as configured in the repository or global git configuration. Do not override author or committer with `--author`, environment variables or per-command configuration.
- Commit messages, trailers and branch names contain no tool, model or assistant attribution: no `Co-Authored-By` lines for tools, no "Generated with" lines, no product names.
- Do not bypass hooks or signing.

**Branches**

- The project has one integration branch, named in the profile. Every change lands there; a release is cut from it.
- External contributors work in their own fork. Branches in a fork or the main repository are optional and short-lived, and all of them merge back into the integration branch.
- Work happens on the current branch unless the developer chooses another. A branch is created, switched or deleted only on the developer's request.

How coding agents obtain approval and commit is defined by the agent instructions ([5.6](#56-agent-instructions)).

### 5.5 Keeping this document healthy

- This standard, the project profile and the agent instructions are the only documents that define structure, coding standards and the development procedure. Do not maintain a parallel architecture guide, a per-platform style guide, a file-by-file catalog or a second agent instructions file.
- This document contains only rules that hold for any project adopting it. Project facts belong in the profile ([2.11](#211-project-profile)). Feature behavior, protocol contracts and platform integration details go in their own documents.
- When a rule changes, change it here and update the code that it governs in the same piece of work, or note that adoption is incremental.

### 5.6 Agent instructions

Every project developed with coding agents keeps one agent instructions file, `AGENTS.md`, at the repository root. Tool-specific instruction files point to it rather than repeating it.

**Purpose.** This standard defines the rules, the project profile records the project's facts, and the agent instructions define the working procedure that makes an agent apply both. Agents read the file at the start of every session, so it is short and procedural. It tells an agent when to stop and consult a rule, what evidence to leave that it did, and what to check before finishing. It adds no rules and restates none.

| Document | Answers | Read |
| --- | --- | --- |
| Standard | What good code is | Consulted as reference |
| Project profile | Where things are and which tools and values the project uses | Consulted as reference |
| Agent instructions | How an agent works so the result meets the standard | Every session, in full |

**Sections, in this order.** Omit a section only when it does not apply.

| Section | Contents |
| --- | --- |
| Sources | Links to this standard and the profile, and the instruction to read both before changing code |
| Before starting | How to begin a task. A defect is explained from the code, or reproduced or instrumented to separate the candidate causes, before behavior changes ([5.1](#51-applying-the-standard)) |
| Triggers | A table of situations an agent can recognize while working. Each row links to the rule it invokes and names the evidence the agent leaves |
| Evidence | Where evidence goes: code comments for confirmed API facts, commit bodies for causes, searches and regression tests, and the final report for measurements and manual checks |
| Self-review | The named questions the agent applies to its own diff before reporting the work as finished, including the review checklist ([5.2](#52-review-checklist)) |
| Verification limits | What the agent may and may not run, and the list of manual checks it gives the developer for anything it cannot exercise ([5.3](#53-verification)) |
| Commits and approval | When to offer a commit and the approval requirement, linking to [5.4](#54-commits) for the message format and authorship |

**Writing triggers.**

- A trigger names a situation the agent can recognize at the moment it occurs, not a quality to aim for. Write "When you add a timeout to an operation", not "Handle timeouts correctly".
- Each trigger links to the section of this standard whose rule it invokes. If no rule backs it, generalize the rule into this standard first; the agent instructions then add only the trigger and its evidence.
- Each trigger names evidence a reviewer can find: a comment, a commit-body statement, a test or an entry in the final report. A check that leaves no trace cannot be reviewed.
- Triggers come from observed failures. When review finds the same rule broken more than once, add a trigger for it, a mechanical check, or both. Remove a trigger once a mechanical check fully enforces its rule.

**Writing the file.**

- Keep it short enough to read in full every session; the profile sets the line limit. Every line gets similar weight, so each line must earn its place.
- Write in the imperative and address the agent directly.
- Link to rules; never paraphrase them. Two wordings of one rule drift apart.
- Project facts stay in the profile and feature behavior stays in feature documents; the agent instructions link to both.
- Name no tool, model or vendor unless an instruction depends on that tool's behavior.

**Approval and commits.** The agent instructions require that an agent:

- offers to commit after a coherent set of changes and waits for explicit approval, and never commits, amends, rebases, force-pushes or pushes without it;
- commits with the configured git identity, never sets or changes it, and asks the developer to configure one when none exists;
- writes a message that describes the change itself and never mentions that an agent or tool produced it.

**Maintenance.** A change to a rule updates the triggers that link to it in the same piece of work. A trigger whose linked section no longer exists is a defect.

An illustrative skeleton:

```markdown
# Agent instructions

## Sources
Read FLUTTER-STANDARDS.md and PROJECT-PROFILE.md before changing code.

## Before starting
For a defect, explain the cause from the code, or reproduce or instrument it to
separate the candidate causes, before changing behavior (standard 5.1).

## Triggers
| When you… | Apply | Leave as evidence |
| --- | --- | --- |
| rely on how an API behaves | 1.4 | A comment stating the confirmed fact, where consequential |
| are about to write an encoder, parser, retry or queue | 3.6 | The existing owner used, or why none fits |
| fix a defect | 5.1 | The mistake, the search for other occurrences, the regression test |

## Self-review
Check the diff against every trigger above and the review checklist (5.2).

## Verification limits
Format, analyze and run headless tests. Do not launch the app. List the manual
checks the developer should run.

## Commits and approval
Offer a commit and wait for approval. Follow 5.4.
```
