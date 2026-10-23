# Windows packaging

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
is not requested. Neither packaging nor the installer's finish page launches
Phonolite.

Close Phonolite before upgrading or uninstalling. An NSIS upgrade runs the
previous NSIS uninstaller to remove its exact payload before installing the new
release. Uninstall removes packaged files and registration, preserving app data,
logs, downloaded music and unrelated files in the installation directory.

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
by downloading and running a newer NSIS installer; there is no automatic hosted
update feed in this packaging flow.

An existing MSIX installation is separate from the NSIS installation. Back up its
data before removing the MSIX version through Windows Settings, then install the
NSIS release. This installer does not migrate data out of an MSIX package.
