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
