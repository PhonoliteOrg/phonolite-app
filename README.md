# Phonolite app

Run commands from the `phonolite-app` directory. Install the Flutter SDK and Rust
(`rustup` and `cargo`), then fetch the bundled Opus source and resolve the app's
dependencies:

```sh
git submodule update --init --recursive
flutter pub get
```

## Run locally

### Linux

Requires Flutter 3.47 / Dart 3.13 or later, Rust (`rustup` and `cargo`), CMake 3.16 or later, and
the initialized Opus submodule from the setup commands above. On Ubuntu, install
the native build tools and plugin development dependencies:

```sh
sudo apt update
sudo apt install build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev libjsoncpp-dev libx11-dev libxi-dev libpulse0
```

See [Flutter's Linux setup guide](https://docs.flutter.dev/platform-integration/linux/setup).
The first build also needs access to Cargo dependencies and the SQLite source
download. A desktop Secret Service, normally GNOME Keyring, is required for
secure storage at runtime. GNOME needs AppIndicator support to display the tray.
The tray uses StatusNotifierItem directly and no longer links the deprecated
libayatana-appindicator library. Playback needs a running desktop PulseAudio
service or PipeWire with its PulseAudio compatibility service (`pipewire-pulse`).

Compile without launching:

```sh
flutter build linux --debug
flutter build linux --release
```

The executable is `build/linux/<architecture>/<mode>/bundle/phonolite_app`,
where architecture is `x64` or `arm64`. Keep its complete `data` and `lib`
directories together. To launch a debug build with hot reload, run
`flutter run -d linux --debug`.

Register a debug bundle as **Phonolite (Development)** in the application menu and dock:

```sh
python3 distribution_tools/linux/install_desktop_entry.py build/linux/x64/debug/bundle
```

This writes the current user's desktop launcher and an icon with a small transparent
inset so the logo fits comfortably in the dock. The launcher uses absolute executable
and icon paths and a separate development application ID. Run it again after moving
the debug bundle. Release packages install their launcher system-wide. If an older
per-user `com.phonoliteorg.phonolite_app.desktop` entry shadows the packaged app,
move that old entry out of `~/.local/share/applications` and repin the system entry.

Linux currently provides the desktop host, file selection, secure storage,
tray/window integration, autostart, native decoders, QUIC and 16/32-bit PCM
playback through the system default audio output. Native output-device enumeration
and MPRIS media integration remain unfinished. Linux native packaging and the
signed GitHub updater are implemented with production rollout gated on signing
setup and target/session validation. See the
[Linux support and build checks](docs/linux-native-specification.md).

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

### macOS

Requires Flutter 3.47 / Dart 3.13 or later, macOS 13 or later, Xcode,
CMake and Rust. Install both native targets for Intel and Apple Silicon:

```sh
rustup target add x86_64-apple-darwin aarch64-apple-darwin
flutter pub get
flutter build macos --debug
flutter build macos --release
```

Flutter build hooks compile and bundle the Opus, local-audio and QUIC frameworks
for each requested architecture with the selected macOS SDK and deployment
target. Other plugins use Swift Package Manager. Secure storage uses a local
packaging fork of version 3.1.3 with unchanged Dart and Keychain implementations.
Keep the complete app bundle, including its Frameworks and Resources, together.
See [native build hooks](packages/phonolite_native_build/README.md) for details.

macOS includes CoreAudio output/device selection, decoding, QUIC, menu-bar and
window integration, launch at login, system Now Playing information and media
commands. Artwork bytes use the existing authenticated Dart loader. Custom
storage locations use a native folder chooser and persistent sandbox bookmarks;
permissions are restored before storage opens at startup.

Before the first certificate-signed build, open `macos/Runner.xcworkspace` in
Xcode, select the Runner target's Signing & Capabilities tab, enable
Automatically manage signing and select your development team. Build once in
Xcode to create the Mac development provisioning profile, or allow Xcode to
manage it from the command line:

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -derivedDataPath build/macos \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

The registration flag lets Xcode register this Mac with the selected development
team when it is not already included in that team's development devices.
Then repeat the Flutter build. Flutter's macOS build command does not pass
`-allowProvisioningUpdates`, so automatic signing in the project alone cannot
create a missing profile during that build. Keep certificate-based signing and
the Keychain entitlements enabled so secure credential storage remains available.

The iOS and macOS bundle ID is `com.adamuremek.phonolite`, matching the existing
Phonolite App Store Connect record. Add macOS to that record for the shared
listing. Select the correct Apple development team in `macos/Runner.xcworkspace`,
then archive, validate and upload through Xcode. The Mac App Store manages app
updates.
See the [macOS native specification](docs/macos-native-specification.md) for
build checks and the remaining user-controlled runtime checks.

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

### Linux packages and updates

The Linux tools build `.deb`, `.rpm` and `.pkg.tar.zst` packages from a complete
release bundle. The app checks signed GitHub metadata and uses an independent
user-session coordinator plus a polkit-authorized native installer. Package
managers own installation; no dedicated package repository is required.

Production key creation remains manual. No private key is checked in, and all
targets currently have `validated: false`, so automatic installation and release
publishing remain gated. The configured candidates are Ubuntu 26.04, Fedora 44,
RHEL 10.0 and Arch rolling on x86_64. Build each on its matching baseline; packages
wrapped on another distribution are inspection artifacts only.

See the [Linux release operations and acceptance checks](docs/linux_distribution_update_plan.md#release-operations)
for key setup, nFPM pinning, packaging, verification, manual GitHub upload, rotation
and recovery commands. Windows continues to use its existing appcast and installer.

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
