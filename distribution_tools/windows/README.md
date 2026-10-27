# Windows packaging for maintainers

This guide is for maintainers building installers and publishing Windows updates
through GitHub Releases. Start with the
[maintainer packaging overview](../../README.md#maintainer-packaging-and-releases)
for the release commands and upload checklist.

The application and installer share the `identityName` and `displayName` in
`scripts/package_config.json`. Native builds generate the process/media identity
from that file. The installer stamps the same AppUserModelID into its Start Menu
shortcut, registers the release's friendly Shell name/icon, and removes that
registration on uninstall. The app also repairs legacy shortcut identity on
first launch without changing an existing shortcut's executable target. Debug
builds use a separate `.Debug` identity and shortcut.

Run these commands in PowerShell from the `phonolite-app` directory. Packaging
uses NSIS 3 and produces an `.exe` installer; a signing certificate is optional.

```powershell
.\distribution_tools\windows\build_nsis.ps1
```

`build_nsis.ps1` is the packaging entry point. The `scripts` directory holds the
[installer template](scripts/installer.nsi), [package configuration](scripts/package_config.json),
shared helpers and verification tools.

The script runs `flutter build windows --release`, stages the complete x64
Flutter bundle and app-local Visual C++ runtime DLLs, and compiles the installer.
It requires the normal Flutter Windows build dependencies, Rust, Visual Studio's
C++ redistributable SDK components, and NSIS 3. It finds `makensis.exe` through
`PATH` or the standard NSIS installation directories. Supply `-NsisPath` for a
custom compiler location. The Windows SDK signing tools are needed only when
signing is requested.

The default package version comes from `pubspec.yaml`: `0.2.0` becomes
`0.2.0.0`, and `0.2.0+4` becomes `0.2.0.4`. To override it, pass
`-PackageVersion 0.2.0.4`. Each of the four numeric components must be between
0 and 65535. Existing nonempty release output is never overwritten.

To package a release that has already been compiled:

```powershell
.\distribution_tools\windows\build_nsis.ps1 -SkipBuild
```

The bundle must exist at `build\windows\x64\runner\Release`. The script rejects
missing native dependencies, binaries with the wrong architecture, symbolic
links and private-key files. Top-level compiler symbols and import libraries
are omitted from the installer.

Output under `build\windows_distribution\<version>\x64` contains:

- `Phonolite_<version>_x64_setup.exe`: the distributable installer.
- `release.json` and `SHA256SUMS.txt`: release metadata and SHA-256 checksums.
- `package` and `nsis`: staged payload and generated compiler input for inspection.

Distribute the installer, metadata and checksum file together. Keep the two
working directories local. The checksum file detects changes relative to the
published checksums; it does not authenticate an unsigned publisher.

The installer requires x64 Windows 10 build 19041 or later. It installs for the
current user under `%LOCALAPPDATA%\Programs\Phonolite`, creates a Start Menu
shortcut, and registers an uninstaller in Windows Settings. Administrator access
is not requested. Packaging and a normal manual installation do not launch
Phonolite. The explicit WinSparkle `/UPDATE` flow relaunches it after a successful
update.

Close Phonolite before upgrading or uninstalling. An NSIS upgrade runs the
previous NSIS uninstaller to remove its exact payload before installing the new
release, passing `/UPGRADE` to preserve app data during both manual upgrades and
WinSparkle updates. A normal uninstall removes packaged files, registration and
the current user's entire `%APPDATA%\Phonolite` folder, including saved settings,
listening statistics, downloaded music and logs. The uninstall confirmation
explains this deletion; silent uninstall also removes the folder. Files stored
outside that folder and unrelated files in the installation directory are
preserved. If app-data deletion fails, uninstall reports the failure and retains
its registration so it can be retried.

## Optional signing

The default build is unsigned and does not access certificate stores. Windows
may show a SmartScreen warning for unsigned downloads, and local security policy
can block them. Signing identifies the publisher but does not guarantee immediate
SmartScreen reputation. See [Microsoft's SmartScreen documentation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

To sign the outer installer with an existing PFX kept outside the app directory:

```powershell
$password = Read-Host 'PFX password' -AsSecureString
.\distribution_tools\windows\build_nsis.ps1 `
    -CertificatePath C:\Signing\phonolite.pfx -CertificatePassword $password
```

Alternatively, pass `-CertificatePasswordFile` pointing to an existing DPAPI
encrypted password file outside the app directory. The file must have been
created with `ConvertFrom-SecureString` by the same Windows account on this
computer. Passwords are never passed to child processes. The signing identity is
temporarily imported into the current user's Personal store if needed, then
removed; no trust store is changed.

For an RFC 3161 timestamp, also pass `-TimestampUrl` with your certificate
provider's HTTPS timestamp service. Without it the signature is not timestamped.
Only the outer installer is signed by this option; the embedded application
binaries and generated uninstaller retain their original signing state.

## Verification without installation

The build verifies the installer version resources, PE header, checksums and
signing state automatically. To verify the release files again:

```powershell
.\distribution_tools\windows\scripts\verify_nsis.ps1 `
    -PackagePath .\build\windows_distribution\0.2.0.0\x64\Phonolite_0.2.0.0_x64_setup.exe
```

To exercise unsigned packaging and failure cases with isolated fixture files:

```powershell
.\distribution_tools\windows\scripts\check_distribution.ps1
```

These checks compile an installer and inspect its bytes. They never execute an
installer, uninstaller or application, and require no certificate. Fixtures under
`build\windows_distribution_checks` are deliberately invalid applications and
must never be installed or distributed. For checks using a real release payload,
pass `-ReleaseBundlePath` pointing to its release directory.

## Moving from MSIX

NSIS replaces the MSIX build scripts and App Installer feed. Updates are installed
by downloading and running a newer NSIS installer, either manually or through
the WinSparkle integration described below.

An existing MSIX installation is separate from the NSIS installation. Back up its
data before removing the MSIX version through Windows Settings, then install the
NSIS release. This installer does not migrate data out of an MSIX package.

## Windows updates and manual GitHub Releases

Release and Profile Windows builds include WinSparkle 0.9.4. Debug builds show
the App updates tile with disabled controls and a release-build note, and
never start the updater. CMake retrieves the official SDK into `.dart_tool/winsparkle`
and checks the pinned SHA-256 in `scripts/winsparkle_dependency.json`; subsequent
builds reuse that verified archive. The runtime DLL and its license are included
in the app bundle and installer.

Settings > Miscellaneous contains one App updates tile. Every Release or Profile
startup quietly reads the appcast after the first frame and compares its newest
Windows version with the running build. It checks again every two hours while
the app is running, including in tray mode, and retries failed feed checks on
that interval. Checks do not overlap and stop when the app closes.
The tile is greyed out while checking,
when no newer version is available, or if the check fails. A newer release enables
the tile and shows its version. Selecting it opens WinSparkle, which checks the
feed again before offering the signed download and install. Quiet checks never
open an update dialog or start an installation. There is no automatic-check
switch, extra service or scheduled task. This updater and its tile are currently
Windows-only; iOS and Android do not initialize it, poll the feed, or show the
tile. Their distribution and update flows remain separate.

The stable feed URL is derived from `scripts/updates_config.json`:

```text
https://github.com/PhonoliteOrg/phonolite-app/releases/latest/download/windows-appcast.xml
```

The startup probe downloads this small RSS/XML file over HTTPS and compares its
four-part numeric version with the running app. WinSparkle uses the same feed
when the tile is selected. Neither check watches commits, scrapes GitHub,
or calls the GitHub API. The feed points to a version-specific installer URL in
the same public repository. No GitHub account or access token is required by app
users. Keep `windows-appcast.xml` in every stable release marked Latest, including
releases that also contain other platforms. Drafts and prereleases are not the
stable update channel. Until the first complete release is published, the feed
will leave the tile disabled with a check-failed message; ordinary playback is unaffected.

### One-time signing setup

The checked-in configuration contains the public Ed25519 verification key. Keep
the matching private key outside this app repository and back it up securely.
An existing installed app trusts that key: do not generate a new one per release.
For a new project setup, or to configure a restored copy of the same private key:

```powershell
.\distribution_tools\windows\initialize_updates.ps1 `
    -PrivateKeyPath C:\Signing\phonolite-windows-ed25519.key
```

The script refuses to replace an already configured key with a different one.
It never uploads or prints the private key. An optional `-Repository owner/name`
changes the public release repository; rebuild the app after changing that value.
Update signatures are separate from optional Authenticode publisher signing.

### For each release

1. Increase the app version/build number in `pubspec.yaml`, then build manually:

   ```powershell
   .\distribution_tools\windows\build_nsis.ps1
   ```

2. If using optional Authenticode signing, pass the certificate options to
   `build_nsis.ps1` in step 1 so the package checksums cover the signed installer.
   Then create the update feed. For example, after building version `0.2.1+0`:

   ```powershell
   .\distribution_tools\windows\prepare_update.ps1 `
       -PackagePath .\build\windows_distribution\0.2.1.0\x64\Phonolite_0.2.1.0_x64_setup.exe `
       -PrivateKeyPath C:\Signing\phonolite-windows-ed25519.key
   ```

   `-ReleaseNotesPath` optionally reads a UTF-8 text file for the update dialog.
   The release tag defaults to `v` plus the version in `pubspec.yaml`, excluding
   the `+build` suffix: both `0.2.1` and `0.2.1+4` use `v0.2.1`. Increase the
   major, minor or patch version for each new default release tag. The installer
   version must match the current pubspec version when using this default.
   Pass `-ReleaseTag` to override it, including when preparing an older package
   or one built with a different `-PackageVersion`. The resulting tag must be
   the tag you create on GitHub.
   The script verifies the existing package, signs its final bytes, verifies that
   signature, and writes `windows-appcast.xml` beside the three release files.

3. In GitHub, manually draft a release at that tag and the exact commit built.
   Upload the versioned `.exe`, `release.json`, `SHA256SUMS.txt`, and
   `windows-appcast.xml`. Publish the complete release and mark it Latest.
   Retain each version's installer; the feed uses its version-specific URL.
   Only these four files are distribution artifacts. Never upload private keys,
   SDK files, or the `package`/`nsis` working directories.

The website's Windows card opens this repository's Releases page. Visitors can
download the versioned installer from the release's Assets list. Publishing a new
release does not require changing the website.

Neither script creates a GitHub release or uploads anything. No Actions workflow
is required. Existing installations without WinSparkle need one manual upgrade
to the first updater-enabled version.

After an update download, WinSparkle verifies its EdDSA signature using the public
key compiled into the app. It starts the installer with `/UPDATE`, then requests
graceful app shutdown through the native platform channel and the existing
desktop Quit workflow. This flushes storage and exits even if tray mode is on.
Update mode waits up to 60 seconds for the old executable to close before making
changes, skips the welcome/license/finish pages, shows installation progress,
and restarts Phonolite only after success. A normal manual install retains its
existing close-first behavior. Failed updates can be retried using the release's
installer; this flow does not promise transactional rollback.

### Verification without launching the app

```powershell
.\distribution_tools\windows\scripts\check_updates.ps1
.\distribution_tools\windows\scripts\check_distribution.ps1
```

The signing checks use disposable keys and non-executable fixture bytes. Native
updater transport tests inject a fake service. These checks do not start the
updater, fetch an appcast, execute an installer, or launch Phonolite. UI and live
installation checks remain manual.
