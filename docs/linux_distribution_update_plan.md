# Linux packaging and update implementation plan

Deliver Phonolite Linux packages through GitHub Releases. Phonolite discovers and verifies updates, an independent coordinator requests authorization and manages shutdown/restart, and the native package manager installs the selected package. Dedicated APT, RPM and pacman repositories are outside this implementation.

Implement this work under the [expected architecture](expected-architecture.md), [coding standards](coding-standards.md) and [Linux native specification](linux-native-specification.md). Preserve the Windows WinSparkle/NSIS behavior and its existing appcast format.

The first end-to-end milestone is an x86_64 Debian-format package on the current Ubuntu development target. Complete RPM and Arch package adapters and their validation before advertising those targets. ARM64, portable self-updates and distribution-maintained repository integration are later work.

## Existing components to reuse

| Component | Existing responsibility | Planned change |
| --- | --- | --- |
| [AppUpdatesController](../lib/application/controllers/settings/app_updates_controller.dart) | Initialization, startup/two-hour checks, observable state and install coordination | Select an injected platform backend and expose the additional Linux update states |
| [AppUpdatePlatform](../lib/infrastructure/platform/app/app_update_platform.dart) | Windows method-channel boundary and installation shutdown callback | Keep the shared capability contract; separate platform implementations and add Linux |
| [AppUpdateFeed](../lib/infrastructure/updates/app_update_feed.dart) | Dedicated HTTPS client with bounded responses, redirects and timeouts | Reuse transport policy while keeping Windows appcast and Linux signed-manifest handling distinct |
| [AppUpdateRelease](../lib/data/models/updates/app_update_release.dart) | Windows appcast decoding and numeric version comparison | Preserve Windows consumers; introduce explicit Linux release, asset and target values without forcing Linux package versions into Windows comparison rules |
| [AppUpdateTile](../lib/ui/features/settings/widgets/app_update_tile.dart) | Settings presentation and delegated update actions | Add download, authorization, installation and recovery presentation through controller state |
| [DesktopSettingsController](../lib/application/controllers/settings/desktop_settings_controller.dart) and [bootstrap](../lib/bootstrap/phonolite_app.dart) | Quit coordination and application resource/storage cleanup | Supply an update-specific shutdown handshake with observable success or failure |
| [Desktop launcher installer](../distribution_tools/linux/install_desktop_entry.py) | Development bundle registration and padded logo generation | Reuse the artwork definition when producing system package metadata |

## Design contracts

- Package identity is `phonolite`; retain production application ID `com.phonoliteorg.phonolite_app`, display name `Phonolite` and the release credential namespace.
- Derive the upstream version and initial package revision from `pubspec.yaml`. For example, `0.4.0+1` maps to upstream `0.4.0` and package revision `1`; subsequent packaging-only rebuilds must increase the package revision. Test ordering with each package manager's rules, including prereleases before offering them.
- Start with the stable release channel. Record package format, target distribution/version, CPU architecture and update ownership in package-installed metadata. Verify the running executable's package ownership instead of selecting an installer solely from the host distribution name.
- Offer automatic installation only for directly distributed, supported release packages. Development bundles and unknown or externally managed installations receive an explanatory disabled state or manual-download action.
- Use a dedicated Ed25519 key for Linux update manifests and an OpenPGP identity for native RPM/Arch signatures where required. Public configuration is checked in; private keys remain external. Keep the Windows signing identity independent.
- Never rely on a checksum downloaded beside a package as proof of authenticity. A verified signature must authenticate the manifest containing that checksum.
- The user-session coordinator owns progress and relaunch. The privileged installer owns verification of protected inputs and the native package transaction. Neither the privileged installer nor package maintainer scripts launch the desktop app as root.
- Keep native installation adapters behind one narrow capability contract. Use fixed argument vectors and installed executables; do not accept arbitrary commands, shell fragments or arbitrary package names.

## Phase 1 Define distribution targets and update protocol

1. Add public package/update configuration under `distribution_tools/linux`, including the GitHub repository, manifest asset names, package identity, trusted key IDs and public keys, installation layout and supported target matrix.
2. Record exact distribution versions and build baselines before publishing their packages. Treat Fedora and RHEL-compatible targets separately. Match architectures to available native Flutter, C and Rust builds.
3. Define versioned Linux release/asset/installation models under `lib/data/models/updates`, with target selection and version rules in their natural data owners. Shared update state should not contain Windows-only parser assumptions.
4. Define the signed manifest schema and shared fixtures. Include schema version, channel, release version/revision, publication/expiry information, release-note reference, and per-asset target, package name, native package version, URL, byte length and SHA-256 digest.
5. Sign the exact manifest bytes with Ed25519 using maintained cryptography libraries. Define the detached signature envelope, pinned-key lookup and an overlapping-key rotation procedure. Unknown schemas/keys, duplicate fields, malformed targets, expired metadata and incompatible assets must produce deliberate outcomes.
6. Define the coordinator protocol: correlation ID, expected installed package/version, selected asset, progress, authorization cancellation, preparation failure, ready-to-install, application-exited, transaction result and relaunch result. Give every stage an explicit owner and completion meaning.

**Acceptance:** Shared fixtures establish signature verification, target selection, package version ordering and protocol decoding. An unmatched target is reported as unsupported; equal/older releases are not offered. Invalid or stale metadata cannot authorize an install.

**Suggested commit:** `feat(updates): define Linux release and installation contracts`

## Phase 2 Produce native packages

1. Add a shared staging operation and an nFPM configuration with format-specific overrides for Debian, RPM and Arch packages. Pin the packaging toolchain and keep package creation separate from app compilation and publishing.
2. Stage the complete release bundle under `/opt/phonolite`, with `/usr/bin/phonolite` pointing to its executable. Preserve executable permissions, relative library lookup, Flutter assets and all decoder/transport/native-asset libraries.
3. Install production desktop metadata under `/usr/share/applications` and the padded icon under the system icon hierarchy. Install updater executables under `/usr/libexec` and their polkit action under `/usr/share/polkit-1/actions` once Phase 4 supplies them. Generate these paths from shared configuration.
4. Declare runtime dependencies per target, including GTK, Secret Service support, PulseAudio compatibility and the updater's authorization/cryptography requirements. Inspect all shipped ELF libraries, including libraries loaded dynamically, rather than inspecting only the main executable.
5. Build against the selected compatibility baselines. Wrapping a build from the current Ubuntu host in a different package format does not establish compatibility with that target.
6. Generate package-installed metadata describing format, architecture, target, package version and direct-update ownership. Keep user settings, credentials and downloaded music outside package-owned application files.
7. Generate required RPM and Arch native signatures and document initial public-key trust setup. Publish their OpenPGP public key and fingerprint; initial trust must be explicit, and an update cannot introduce an arbitrary new trusted key. Do not weaken native signature policy to make local updates install.
8. Account for the existing per-user development launcher, which can shadow the production launcher. Separate development registration from production package metadata and verify that development and installed instances do not capture each other's launches; preserve production storage identity.

**Acceptance:** Package contents and dependencies are validated for all three formats. Each advertised target has installation, upgrade and removal evidence from a clean test environment. Upgrading retains user data and credentials; removal leaves user-owned data intact. Packages and installation scripts do not start the app automatically.

**Suggested commit:** `feat(linux): build native Phonolite distribution packages`

## Phase 3 Add signed update discovery and downloads

1. Select update implementations at bootstrap/platform assembly rather than defaulting every installation to `WindowsAppUpdatePlatform`. Retain the existing Windows contract and behavior.
2. Add a Linux feed implementation using the dedicated HTTPS client policy. Download bounded manifest/signature responses, verify their signature before using release fields, then select the compatible asset for the verified installation descriptor.
3. Embed trusted public configuration through the native build from the same source used by the installer. Do not obtain a new trusted public key from an unverified feed.
4. Add a cancellable downloader with bounded size/time, progress and a private staging directory. Verify the final length/digest before handing the artifact to the coordinator. Clean up incomplete files and bound retained update storage.
5. Extend controller state for checking, update available, downloading, verifying, awaiting authorization, preparing shutdown, installing, failed and restart required. Preserve latest-release information where a recoverable action failure should allow retry.
6. Make shutdown/disposal ownership explicit: closing the Flutter updater must not kill a coordinator that has accepted installation responsibility. Do not restore app state from a stale callback after a new operation or shutdown generation.

**Acceptance:** Headless tests cover invalid signatures, unknown keys, altered manifest/package bytes, excessive sizes, redirects, timeouts, cancellation, incompatible targets and stale callbacks. Existing Windows feed/controller tests continue to pass.

**Suggested commit:** `feat(updates): discover and verify Linux release downloads`

## Phase 4 Implement installation authorization and coordination

Add separate native coordinator and installer targets under `linux/updater`, with substantive data, infrastructure, workflow and UI responsibilities organized according to the Linux specification. Keep the privileged target independent of Flutter, application settings and desktop UI. Share its manifest validation and package adapter rules through normal native libraries.

Use a root-owned installer executable with a dedicated polkit action and `pkexec` for the initial native installation path. The action must request normal administrator authorization for this operation. PackageKit can be added behind the same capability boundary later; it is not a required dependency for the first implementation.

The accepted installation sequence is:

1. The user-session coordinator accepts the selected release request and remains alive independently of Phonolite.
2. The coordinator requests authorization for the installed helper. Cancellation leaves Phonolite running and makes the action retryable.
3. The privileged helper validates the caller/request and trusted manifest, copies the candidate into protected staging, then verifies the protected bytes and package metadata. Reject unsafe paths, unexpected package identity/architecture, downgrades, unsupported targets and substitutions after the app's earlier verification.
4. Check the installed package/version and native transaction requirements. Reject unrequested removals, forced dependency changes and signature-policy bypasses. On Arch, require system maintenance when dependencies cannot be met on the user's current system instead of initiating a partial system upgrade.
5. Report readiness to the app. The app completes its update-specific cleanup handshake; the coordinator verifies process exit and release of the single-instance registration. A timeout or cleanup failure aborts installation before files are replaced.
6. Invoke the manager with fixed arguments: `apt-get` for Debian-format packages, the tested DNF command for RPM, or `pacman -U` for Arch. Let the manager own database locks, dependency resolution and package file ownership. Never delete package-manager lock files.
7. Verify transaction completion and the resulting installed version. Write a durable result receipt; the user-session coordinator then relaunches the stable application launcher as the original user. Wait for completion of the helper before relaunch so the next app instance cannot race installation.

The privileged helper must independently validate the request even if Dart already verified it. `pkexec` authorizes execution but does not validate program arguments. Native signature checks remain enabled where applicable; the signed manifest authenticates downloaded Debian packages independently of an APT repository.

**Acceptance:** Headless native tests cover protocol validation, caller identity, unsafe paths, changed bytes, invalid package metadata, concurrent attempts, authorization outcomes, lock errors, shutdown failure and installer failure. Package-manager invocations are injected in these tests; they never modify the developer's system. Real authorization and transaction behavior is also validated in dedicated test environments.

**Suggested commit:** `feat(linux): authorize native package upgrades through updater helpers`

## Phase 5 Complete shutdown restart and settings behavior

1. Add an awaitable update-specific preparation operation that reuses the existing cleanup owners while propagating required cleanup failures. The current normal quit path logs cleanup errors and still quits; that behavior is insufficient as the installation readiness signal.
2. Expose Linux updates through the existing settings control. Render progress, authentication cancellation, dependency/lock errors and recovery actions using shared controls and typed controller actions.
3. Keep progress/error presentation available in the user-session coordinator while the main app is closed. Never start a graphical process through the privileged helper or a package maintainer script.
4. Consume the durable update receipt after relaunch. Distinguish successful upgrade, relaunch failure, failed transaction and interrupted/unknown transaction state. Re-query installed package state before retrying an interrupted operation.
5. Do not assume a failed native transaction was rolled back. Provide a clear recovery message and diagnostics when package state needs repair; do not automatically downgrade or repeat an ambiguous installation.
6. Ensure close-to-tray cannot substitute for exiting during an update. Repeated update clicks produce one installation and one relaunch. Handle another instance attempting activation while shutdown/installation is in progress.

**Acceptance:** Controller/widget tests cover the full observable state flow. Dedicated session tests demonstrate that the coordinator survives app exit, the app is relaunched as the user, updates do not reopen an old instance, and declined authorization leaves the app usable.

**Suggested commit:** `feat(updates): coordinate Linux shutdown restart and recovery`

## Phase 6 Prepare GitHub release assets

1. Add Linux key-initialization, package-validation and update-preparation scripts following the separation used by the Windows distribution tools. Key initialization refuses to overwrite an established identity; signing uses an explicit external private-key path and verifies the resulting signature.
2. Generate packages, native signatures where required, release metadata, the Linux manifest, its detached signature and checksums from the same tagged commit and version configuration. Verify that signed target/version/hash/length values match actual package contents.
3. Upload all supported target assets to the same draft GitHub release as the Windows artifacts. Verify completeness before publishing it as Latest. Keep `windows-appcast.xml` and the Linux feed distinct, so adding Linux does not change installed Windows clients.
4. Keep package/build/signing steps independently executable. Start with scripts that prepare and validate artifacts for manual upload, matching the current Windows workflow; automated publishing can reuse them later.
5. Retain a documented public-key rotation and manual recovery procedure. Keep installer versions needed by supported client/protocol versions available.

Expected Linux assets include the target-specific `.deb`, `.rpm` and `.pkg.tar.zst` files, required native signature files, `linux-updates.json`, `linux-updates.json.sig`, release metadata and `SHA256SUMS.txt`. Final filenames must identify version, target and architecture without collisions between assets on the shared release.

**Acceptance:** Offline artifact verification rejects an incomplete release, mismatched signing key, altered package, incompatible asset declaration or metadata from a different build. No private key appears in the repository, application bundle or uploaded assets.

**Suggested commit:** `build(linux): prepare signed GitHub release updates`

## Phase 7 Validate targets and release the feature

Run the shared protocol/signature fixtures against both the Dart and native implementations. Extend existing update feed/platform/controller/widget suites and Linux architecture checks; compile the actual native helpers and runner against their real SDKs. Keep source registration explicit and generated Flutter files tool-owned.

For each advertised target, retain evidence for initial install, upgrade from the previous package, dependency failure, authorization cancellation, concurrent package transaction, application shutdown failure, interrupted installation, successful relaunch and removal. Check package ownership, launcher/icon metadata, credential continuity, preserved downloads and reported version. Validate Windows update behavior after shared-contract changes.

During agent implementation, run static analysis, compilation, artifact inspection and foreground headless tests. The [repository verification policy](expected-architecture.md#documentation-and-verification-policy) leaves native application launches, authentication dialogs and service startup user-controlled. Validate real desktop installation/restart flows through explicit user runs or dedicated release test infrastructure.

Update the app README and Linux specification with release commands, target support, initial signing-key setup, update ownership, diagnostics and recovery. Enable Linux update checks in published packages only when their matching signed artifacts and required runtime components are ready.

**Acceptance:** The current Ubuntu `.deb` flow passes first; RPM and Arch follow through the same contracts. A target becomes supported only after its package and update/restart checks pass. Standard system upgrades do not discover GitHub-only updates; the app's update screen communicates that it manages these directly distributed releases.

**Suggested commit:** `test(linux): validate packaged update and restart flows`

## Delivery order and release gates

Implement Phase 1 before packaging/signing consumers. Complete the Debian package path in Phase 2, then Phases 3 through 5 for the first end-to-end updater. Expand the package adapters to RPM and Arch, complete release preparation, and pass Phase 7 for every supported target before public rollout.

Phase 1 must settle the exact distro/version matrix, minimum ABI requirements, cryptography dependencies and native signing trust setup. The privileged helper is a release gate: it must validate protected package bytes independently and must never become a general command runner. The restart gate is a real session check showing that the new version starts under the original desktop user after the old instance has exited.

## Implementation references

- [Flutter Linux distribution requirements](https://docs.flutter.dev/platform-integration/linux/building): complete bundles and system library dependencies.
- [nFPM configuration](https://nfpm.goreleaser.com/docs/configuration/): shared package definitions with format-specific metadata.
- [Debian package management](https://www.debian.org/doc/manuals/debian-reference/ch02): local package installation and dependency handling.
- [DNF installation commands](https://dnf.readthedocs.io/en/latest/command_ref.html#install-command-label) and [local package signature policy](https://dnf.readthedocs.io/en/latest/conf_ref.html#localpkg-gpgcheck).
- [pacman package operations](https://man.archlinux.org/man/pacman.8.en#OPERATIONS), [signature configuration](https://man.archlinux.org/man/pacman.conf.5.en#PACKAGE_AND_DATABASE_SIGNATURE_CHECKING) and [Arch system upgrade policy](https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported).
- [pkexec authorization and argument handling](https://polkit.pages.freedesktop.org/polkit/pkexec.1.html).
- [PackageKit local package installation](https://www.freedesktop.org/software/PackageKit/doc/dbus-org.freedesktop.packagekit1.Transaction.html): an optional future installation adapter.

## Implementation status

The package builders, public configuration/key initializer, shared OpenSSL/JSON-GLib
verifier, Linux discovery/downloader, polkit installer, independent GTK coordinator,
strict shutdown path and release preparation/verification tools are implemented.
The existing Windows updater contract and appcast remain in place. Linux checks are
available only to a package-owned installation with a configured signing key and a
matching validated target; debug, portable and externally managed builds explain why
automatic updates are unavailable.

Production key creation is deliberately manual. All candidate targets currently remain
`validated: false`. Headless checks and artifact construction do not satisfy the real
installation, authorization, dependency, interruption and relaunch acceptance gates.
Do not mark a target validated until those checks have evidence from its own baseline.

## Release operations

### Toolchain and keys

Normal Flutter builds retain the build dependencies in the app README. Packaging the
standalone helpers additionally requires CMake 3.19+, Python 3.10+, OpenSSL development
headers, JSON-GLib development headers, GTK development headers and `readelf`. On
Ubuntu, the additional packages are `libssl-dev libjson-glib-dev binutils`; polkit's
`pkexec` is a runtime dependency. Native release verification needs `rpm`/`rpmkeys` on
RPM build hosts, and `bsdtar`, `gpg` and pacman tools on Arch hosts.

Install nFPM **2.48.0** from its official release. The Linux x86_64 archive SHA-256 is
pinned in `distribution_tools/linux/config.json`; verify it before extracting. Pass
the executable explicitly with `--nfpm`. The packager never installs system tools.

Create the production Linux manifest identity manually on a trusted maintainer machine:

```sh
python3 distribution_tools/linux/initialize_updates.py \
  --private-key /secure/external/phonolite-linux-ed25519.pem --key-id linux-2026
```

The initializer refuses an existing destination or established key ID. Commit the
resulting **public** configuration and securely back up the external private key.
Private keys must be outside this repository with owner-only permissions. Never copy
private material into the bundle or release directory. Windows retains its own key.

RPM/Arch additionally need an independently managed OpenPGP signing identity. Create
that identity manually, set its complete uppercase primary fingerprint in
`native_signing_fingerprint`, and export its public key for release upload. Supply
an external exported secret key to `--rpm-signing-key` when building RPMs; nFPM reads
its passphrase from `NFPM_RPM_PASSPHRASE`. Arch packages receive a detached `.sig`:

```sh
gpg --local-user FULL_NATIVE_FINGERPRINT --detach-sign \
  build/linux/packages/phonolite_VERSION-REVISION_arch-rolling-amd64.pkg.tar.zst
```

Before the first RPM/Arch installation, the administrator must independently check
the public fingerprint and establish trust through the native tools (`rpm --import`
or `pacman-key --add` plus `pacman-key --lsign-key`). The app never imports an arbitrary
new native signing key from a feed. No APT repository key setup is necessary for this
GitHub-only model: the signed manifest authenticates the exact Debian package bytes.

### Build and inspect packages

Build from the release source on each configured target's actual baseline. For a
packaging-only rebuild, increase `--revision` consistently in all packaging and update
preparation commands. The stable version mapping is `major.minor.patch+build` to
`major.minor.patch-revision`; prerelease updates are intentionally unsupported.

```sh
flutter build linux --release
python3 distribution_tools/linux/package_app.py \
  --bundle build/linux/x64/release/bundle --target ubuntu-26.04-amd64 \
  --nfpm /path/to/nfpm
```

Use `fedora-44-amd64`, `rhel-10.0-amd64` or `arch-rolling-amd64` on the corresponding
baseline. RPM signing adds `--rpm-signing-key /secure/external/native-secret.asc`.
The builder compiles/tests the helpers, stages the complete bundle and emits the
package plus `.build.json` containing source/configuration identity and every ELF's
dynamic dependency listing. Flutter records the bundle's source identity at install
time. Production packaging requires a clean matching checkout, production desktop
identity and validated baseline. Source-identity records are provenance checks for
this workflow, not a substitute for trusted build infrastructure.

For inspection or dedicated validation environments, add `--development`. This permits
a dirty checkout, unvalidated target or foreign host for package-format inspection;
the resulting metadata is explicitly non-publishable. To exercise an update in a test
VM, use an external test configuration with temporary keys and that test target enabled,
build both package versions against it, and sign the test manifest with that temporary
identity. Never upload these artifacts or reuse a test identity for production.

All packages use `/opt/phonolite`, `/usr/bin/phonolite`, `/usr/libexec` and system desktop,
icon and polkit locations. They contain no app-starting maintainer script and no
user-owned settings, credentials or downloaded music. The icon preserves the two-pixel
inset at 48 pixels. Debug registration uses `com.phonoliteorg.phonolite_app.devel`;
release packages keep the production ID and credential namespace. Remove or move an
old per-user production `.desktop` entry if it shadows the packaged launcher.

### Prepare the GitHub release

Commit the public key/target configuration and release code before the final clean
build, tag the source, and collect only that release's packages and `.build.json`
records into one output directory. Ensure native RPM/Arch signatures are already
present and trusted on the release verification host. Build the standalone native
verifier against the same public configuration:

```sh
cmake -S linux/updater -B build/linux/updater -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux/updater --parallel
ctest --test-dir build/linux/updater --output-on-failure
python3 distribution_tools/linux/prepare_updates.py \
  --directory build/linux/packages --target ubuntu-26.04-amd64 \
  --private-key /secure/external/phonolite-linux-ed25519.pem --key-id linux-2026 \
  --native-verifier build/linux/updater/phonolite-update-coordinator
```

Repeat `--target` for each validated target included in the release. Add
`--native-public-key /path/to/native-public.asc` for releases with RPM/Arch assets.
`--tag` overrides the default `vVERSION`; `--valid-days` defaults to 90 and is capped
at 366. Expired metadata fails closed, so publish refreshed signed metadata before
expiry even when the package version stays the same.

The tool verifies package identity, source/configuration agreement and signature,
then writes `linux-updates.json`, its `.sig` envelope, `linux-release.json` and
`linux-SHA256SUMS.txt`. The Linux checksum filename avoids collision with Windows'
`SHA256SUMS.txt`. RPM/Arch releases also include their native public key/fingerprint;
Arch packages include `.pkg.tar.zst.sig`. Checksums are inspection aids; authenticity
comes from the Ed25519-signed manifest and native signature policy.

Verify the collected assets again before manual upload:

```sh
python3 distribution_tools/linux/prepare_updates.py --verify-only \
  --directory build/linux/packages \
  --native-verifier build/linux/updater/phonolite-update-coordinator
```

Upload the Linux artifacts to the **same draft GitHub release** as Windows. Check all
asset names against the manifest before publishing it as Latest. Keep
`windows-appcast.xml` unchanged. Ordinary system upgrades do not discover these
GitHub-only updates; directly distributed Linux packages use Phonolite's App updates
control. A distribution repository can take update ownership in a separate future
integration; do not enable both mechanisms for an externally managed installation.

### Protocol, rotation and recovery

Manifest schema 1 contains stable channel/package identity, version/revision,
Unix-second publication/expiry times, release notes and unique target assets with
format, architecture, native version, HTTPS URL, byte length and lowercase SHA-256.
The `.sig` envelope contains schema 1 and up to eight `{key_id, signature}` records.
Signatures are canonical base64 Ed25519 proofs over the **exact manifest bytes**;
public keys are raw 32-byte base64 values. Metadata is capped at 1 MiB and the
signature envelope at 8 KiB. Packages are capped at 2 GiB. Unknown schemas/keys,
duplicate fields/targets, expired metadata and incompatible targets fail closed.

To rotate keys, first ship a release embedding both public identities. Keep signing
with the old key while introducing the new one; add
`--additional-private-key NEW_KEY_ID=/secure/external/new.pem` for overlapping proofs.
Maintain the old proof while supported clients may still lack the new public key.
Remove the old identity only after the overlap/retirement policy permits it. A
compromised signing key requires an independently trusted manual recovery path;
fetching a replacement key from the compromised feed does not establish trust.

The private request directory contains only fixed filenames: `request.json`,
`manifest.json`, `manifest.sig`, `candidate` and optional `candidate.sig`. Request
schema 1 carries a random correlation ID, PID/start ticks and expected installed
version. Dedicated pipes carry readiness with the same correlation. Successful app
preparation emits `prepared`; failure or EOF aborts. The coordinator sends `install`
to the authorized helper only after this acknowledgement; the helper independently
waits for the original process to exit. The root helper never accepts arbitrary
commands or package names. Administrator authorization precedes application cleanup.

Transaction receipts live at `/var/lib/phonolite-updates/receipt-UID.json`.
`interrupted` is persisted before invoking the manager, followed by `succeeded` or
`failed`. The user coordinator records relaunch separately under
`$XDG_STATE_HOME/phonolite/update-result.json` (default `~/.local/state/phonolite`).
The new app acknowledges its matching installed version after startup; a missing
acknowledgement leaves visible manual-relaunch guidance. Neither root nor package
scripts start the desktop app. The original desktop account owns the coordinator
and the restarted process.

Authorization cancellation and preparation failure leave installation unstarted.
After a failed/interrupted transaction, inspect native package state and the manager's
logs before retrying; a rollback is never assumed. On Debian, begin with
`dpkg --audit`; on RPM/Arch use their native verification and transaction history.
Repair dependencies or package state through normal administrator tools. Never delete
native manager lock files, force a downgrade or initiate `pacman -Sy` as update recovery.
The coordinator window remains available after Flutter exits. Committed native
transactions are awaited rather than terminated on an updater deadline. Root-protected staging
is deleted on normal completion/error; an abrupt helper/system kill can leave a
`/var/lib/phonolite-updates/work-*` directory. An administrator may remove orphaned
staging only after confirming no native transaction is active.

### Release acceptance evidence

Foreground checks available without launching the app:

```sh
flutter test test/platform/linux_app_updates_test.dart \
  test/platform/app_update_feed_test.dart test/platform/app_update_platform_test.dart \
  test/architecture/app_updates_controller_test.dart test/architecture/desktop_settings_test.dart \
  test/widgets/app_update_tile_test.dart test/architecture/linux_architecture_test.dart
ctest --test-dir build/linux/updater --output-on-failure
PHONOLITE_NATIVE_TEST="$PWD/build/linux/updater/phonolite-updater-tests" \
  python3 -m unittest discover -s distribution_tools/linux/tests -v
```

For each exact target, retain clean-environment evidence for initial install,
upgrade/revision ordering, removal with user data retained, native public-key trust,
invalid signatures, cancelled authentication, dependency failure, concurrent package
transactions, failed cleanup, interruption and successful relaunch as the user.
Verify the production launcher/icon and credential/download continuity under the
actual desktop session. Fedora and RHEL require separate evidence. Only then enable
that target in public configuration, rebuild cleanly and prepare production artifacts.
