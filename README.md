# Phonolite app

Run commands from the `phonolite-app` directory. Install the Flutter SDK and Rust
(`rustup` and `cargo`), then resolve the app's dependencies:

```sh
flutter pub get
```

## Run locally

### Windows

Requires Windows and Visual Studio 2022 with **Desktop development with C++**,
including the Windows SDK and CMake tools. Use the Rust MSVC toolchain.
See [Flutter's Windows setup guide](https://docs.flutter.dev/platform-integration/windows/setup).

Debug, with hot reload:

```powershell
flutter run -d windows --debug
```

Release:

```powershell
flutter run -d windows --release
```

To compile without launching the app, use `flutter build windows --debug` or
`flutter build windows --release`. Output is under
`build\windows\x64\runner\Debug` or `Release`; keep the complete bundle together.
App update checks are disabled in debug builds.

Windows debug launches capture up to 128 accessibility updates in `debug.log` in
the configured log directory (by default `%APPDATA%\Phonolite\logs`). Entries
begin with `Windows accessibility update ` and record node IDs and parent/child
links, without UI text or field values. The capture preserves Flutter's original
updates and does not enable accessibility. Keep the log from the same launch as
the first native `accessibility_bridge.cc` error for replay and diagnosis.
See the [accessibility replay tools](tools/accessibility/README.md) for native
tree validation and the synthetic missing-descendant regression.

### iOS

Requires a Mac with Xcode, its command-line tools, CocoaPods and CMake.
See [Flutter's iOS setup guide](https://docs.flutter.dev/platform-integration/ios/setup).
Install the Rust targets used by the device and simulator builds:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

For a physical device, open `ios/Runner.xcworkspace` in Xcode and configure
**Runner > Signing & Capabilities** with your signing team and bundle identifier.
Connect the device and enable Developer Mode on it.

Find the device or simulator ID:

```sh
flutter devices
```

Replace `YOUR_IOS_DEVICE_ID` below with that ID. Debug supports a simulator or
physical device; release requires a physical device.

```sh
# Debug, with hot reload
flutter run -d YOUR_IOS_DEVICE_ID --debug

# Release, on a physical device
flutter run -d YOUR_IOS_DEVICE_ID --release
```

## Maintainer packaging and releases

Maintainers use this section to build installers and publish app updates.
Set the release version and build number in `pubspec.yaml` before packaging.
Build outputs and release uploads are managed manually.

Keep each version's changes since the previous tag in its own
`releases/<release-tag>.md` file. See [release notes](releases/README.md) for the
history and release workflow.

### Windows installer and updates

Install NSIS 3 in addition to the Windows build tools above, including Visual
Studio's C++ redistributable SDK components. Run the existing packaging script:

```powershell
.\distribution_tools\windows\build_nsis.ps1
```

It compiles a release build and creates an installer, `release.json` and
`SHA256SUMS.txt` under `build\windows_distribution\<version>\x64`. The Windows
package version uses `major.minor.patch.build`, with the build number taken from
the `+build` suffix in `pubspec.yaml`. The installer is named
`Phonolite_<version>_x64_setup.exe`.
Use `-SkipBuild` only when the existing release bundle matches the package version.

Windows publisher signing (Authenticode) is optional. If used, pass the certificate
options to `build_nsis.ps1` so signing happens before preparing the update feed.

Prepare the WinSparkle update feed with the existing Ed25519 private key that
matches the app's configured public key. Keep this key outside the repository
and reuse it across releases. Replace `<version>` below with the Windows package
version from the build output:

```powershell
.\distribution_tools\windows\prepare_update.ps1 `
    -PackagePath ".\build\windows_distribution\<version>\x64\Phonolite_<version>_x64_setup.exe" `
    -PrivateKeyPath C:\Signing\phonolite-windows-ed25519.key
```

To include that version's notes in the update feed, also pass
`-ReleaseNotesPath .\releases\<release-tag>.md`, replacing `<release-tag>` with
the tag being packaged.

The GitHub release tag comes automatically from `pubspec.yaml`, prefixed with
`v` and excluding the `+build` suffix, giving `v<major>.<minor>.<patch>`.
The installer and update comparison use the four-part Windows package version.
Increase the major, minor or patch version for each new default release tag;
changing only `+build` reuses the same tag. The default requires the installer
version to match the current pubspec version. Use `-ReleaseTag` only when
overriding the tag, such as for an older package or a build made with a different
`-PackageVersion`.

Draft a GitHub Release at that tag and the exact commit built. Upload these four
files from the version's `x64` output directory:

- `Phonolite_<version>_x64_setup.exe`
- `release.json`
- `SHA256SUMS.txt`
- `windows-appcast.xml`

Publish the complete release and mark it **Latest**. Every stable release marked
Latest must include `windows-appcast.xml`, since installed apps read that feed
to find updates. Keep the `package` and `nsis` working directories local.
The scripts prepare files; they do not create or upload a GitHub Release.

Windows release builds check the feed on startup and every two hours. Select
**Settings > Miscellaneous > App updates** to check immediately or retry a failed
check. When a newer version is found, the tile offers **Download and install**;
select it again to open the signed WinSparkle update flow. Debug builds disable
update checks.

Versions 0.2.0 and 0.3.0 inherit the music-server HTTP certificate pins for feed
requests, which reject GitHub before update discovery. They also disable the
tile until an automatic check finds an update. Those versions require a manual
installer upgrade to a release containing the dedicated HTTPS client and
click-to-check tile fix. Publishing a new feed cannot repair installed code.

### iOS IPA

On a Mac, configure the signing certificates and provisioning profiles for your
chosen export method, then build the IPA locally:

```sh
flutter build ipa --release
```

The archive is written to `build/ios/archive/` and the IPA to `build/ios/ipa/`.
The default export method is App Store. For device testing, choose
`--export-method ad-hoc` or `--export-method development` with the matching
signing/provisioning setup. See [Flutter's IPA export guide](https://docs.flutter.dev/deployment/ios#create-an-app-bundle).

There is no dedicated IPA packaging script in this repository. The existing
verification script can inspect the exported IPA without launching it:

```sh
python3 ios/Scripts/verify_release_artifact.py build/ios/ipa/*.ipa
```

Run verification on the same Mac and checkout used to build the IPA, with Python 3
installed. If the output folder contains multiple IPAs, supply the exact IPA path.
IPA building and verification do not upload or publish the app.
