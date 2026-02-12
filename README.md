# phonolite_app

Phonolite Flutter client.

## Setup

1. Clone and init submodules:

```bash
git submodule update --init --recursive
```

2. Install packages:

```bash
cd phonolite_app
flutter pub get
```

## Native FFI Libraries
1. `phonolite_quic` builds from Rust during platform builds.
2. Android builds require `cargo-ndk` and the Android NDK installed.
3. iOS/macOS builds require Xcode command line tools.
4. Windows/Linux builds require the Rust toolchain in `PATH`.

## Build / Run

Android (macOS/Windows/Linux):
```bash
flutter run -d android
flutter build apk
```

iOS (macOS only, requires Xcode + CocoaPods):
```bash
flutter run -d ios
flutter build ios --release
```

macOS:
```bash
flutter run -d macos
flutter build macos
```

Windows:
```bash
flutter run -d windows
flutter build windows
```

Linux:
```bash
flutter run -d linux
flutter build linux
```

## Deploy (TestFlight)

The deploy script requires App Store Connect credentials exported in your shell.

Option A: App Store Connect API key
```bash
export APPSTORE_API_KEY_ID="ABC123XYZ"
export APPSTORE_API_ISSUER_ID="00000000-0000-0000-0000-000000000000"
```

Option B: Apple ID + app-specific password
```bash
export APPLE_ID="you@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Then run:
```bash
./deploy/upload_testflight.sh
```

If you use the App Store Connect API key flow, `altool` expects the private key
file named `AuthKey_<API_KEY_ID>.p8` to live in one of these locations:

- `~/Desktop/phonolite-app/private_keys`
- `~/private_keys`
- `~/.private_keys`
- `~/.appstoreconnect/private_keys` (recommended)

Example setup:
```bash
mkdir -p ~/.appstoreconnect/private_keys
cp /path/to/AuthKey_<API_KEY_ID>.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_<API_KEY_ID>.p8
```
