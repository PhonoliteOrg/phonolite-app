# Phonolite project profile

This profile records Phonolite's concrete values for the [Flutter standards](FLUTTER-STANDARDS.md). The standards define how any Flutter application is structured and written; this document says where those rules land in this repository. Its layout follows [section 2.11](FLUTTER-STANDARDS.md#211-project-profile).

## Project

Phonolite is a Flutter application with native hosts for iOS, macOS, Android, Windows and Linux. The music server and command-line tools are separate Rust projects outside the scope of the standards. Rust inside this repository's native packages follows [4.6](FLUTTER-STANDARDS.md#46-other-languages).

Languages in use: Dart, Swift, Kotlin, C++, C and Rust in native packages.

## Source areas

Every Dart source file except `lib/main.dart` belongs to one of these area directories:

| Directory | Area |
| --- | --- |
| `lib/bootstrap/` | Bootstrap |
| `lib/pages/` | Pages |
| `lib/ui/` | UI |
| `lib/application/` | Application |
| `lib/data/` | Data |
| `lib/infrastructure/` | Infrastructure |

Additional application folders: `lib/application/presentation/` holds application-facing labels and helpers, and `lib/ui/shared/music/` holds shared music presentation.

## Native hosts

| Host | Location | Area folders in use |
| --- | --- | --- |
| iOS | `ios/Runner/` | PascalCase: `Bootstrap/`, `Data/`, `Application/`, `Infrastructure/`, `Pages/`, `UI/` |
| macOS | `macos/Runner/` | PascalCase: `Bootstrap/`, `Data/`, `Infrastructure/` |
| Shared Apple sources | `native/apple/` | PascalCase: `Data/`, `Infrastructure/`, compiled into both Apple targets |
| Android | `android/app/src/main/kotlin/com/phonoliteorg/phonolite_app/` | Lowercase subpackages: `bootstrap`, `data`, `application`, `infrastructure`, `ui` |
| Windows | `windows/runner/` (`.h`/`.cpp`) | `lower_snake_case`: `bootstrap/`, `data/`, `infrastructure/`, `ui/` |
| Linux | `linux/runner/` (`.h`/`.cc`) | `lower_snake_case`: `bootstrap/`, `data/`, `infrastructure/`, `ui/` |

Each host adds other areas, using the same naming, only when real work for them appears ([2.4](FLUTTER-STANDARDS.md#24-platform-hosts)). Native FFI packages live under `packages/` and keep their own build integration and ABI.

## Tools and configuration

| Language | Tool | Configuration |
| --- | --- | --- |
| Dart | `dart format` and `flutter analyze` from the repository's Flutter SDK; `flutter_lints` plus `always_use_package_imports` and the async and error-handling rules of [4.1](FLUTTER-STANDARDS.md#41-dart-and-flutter) | `analysis_options.yaml` |
| Swift | `swift-format` | `ios/.swift-format`, `macos/.swift-format` |
| Kotlin | ktlint | `android/.editorconfig` |
| C++ | clang-format | `windows/.clang-format`, `linux/.clang-format` |
| C | clang-format | `macos/.clang-format` |

The Android `.editorconfig` disables ktlint's `package-name` rule for the established `phonolite_app` package prefix; new package segments are still lowercase words.

## Limits and enforcement

- Dart files under `lib/` must stay within 1,000 lines; structural tests enforce this.
- Structural checks live under `test/architecture/`. They cover dependency direction, documented source areas (parsed from the table above), private component trees and per-host layout. The [test index](test/README.md) lists all suites.
- [`AGENTS.md`](AGENTS.md) stays within 100 lines ([5.6](FLUTTER-STANDARDS.md#56-agent-instructions)).

## Release readiness

Checklists for [2.12](FLUTTER-STANDARDS.md#212-host-release-readiness). Check every item for a host before its release build.

| Host | Checklist |
| --- | --- |
| Android | Release builds sign with the key from `android/key.properties` and fail without it. `allowBackup` and `fullBackupContent` are off and `data_extraction_rules.xml` excludes every domain from cloud backup and device transfer. Only the components that must be exported are, and the media browse service limits callers. The media service returns `START_NOT_STICKY` and every foreground start reaches `startForeground`. Audio focus leaves ducking to the system and resumes after transient losses |
| iOS | `ios/Runner/PrivacyInfo.xcprivacy` declares every required-reason API in use and is in the Runner target's resources. Launch sets the audio session category without activating it. Permission usage strings cover every requested permission |
| macOS | `macos/Runner/PrivacyInfo.xcprivacy` declares every required-reason API in use. Release builds are signed and notarized for distribution |
| Windows | The installer and updater point at the published release artifacts, and release binaries are signed when a signing identity is available |
| Linux | Packages contain only the files listed for distribution, and secure storage errors are reported rather than crashing |

## Commit vocabulary

- `Changelog:` categories match the section headings of the release notes in `changelog/`: `Added`, `Changed`, `Fixed`, `Compatibility`, `Maintenance` or `None`.
- `Platforms:` values: `all`, `android`, `ios`, `macos`, `windows`, `linux`. Use `all` for shared Dart behavior.
- Integration branch: `main`. Contributors fork the repository; feature branches are optional, and every change merges into `main`.
