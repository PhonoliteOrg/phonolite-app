# Cross-platform feature scenarios

Each expected behavior is written once as a `FeatureScenario` and runs headlessly
on every platform profile (iOS, Android, macOS, Windows, Linux) with plain
`flutter test`. Scenarios never name a platform; they describe what a person does.

| Piece | Role | Per-platform code |
| --- | --- | --- |
| [`support/platform_profile.dart`](support/platform_profile.dart) | Target platform, screen size, player surface, input and capabilities as data | One `PlatformProfile` |
| [`support/feature_world.dart`](support/feature_world.dart) | Starting state, plus a `WorldController` that answers app commands | None |
| [`support/app_driver.dart`](support/app_driver.dart) | Launch, input, tabs, back/forward and dialogs, mapped to touch or mouse/keyboard | None (it reads the profile) |
| [`support/player_steps.dart`](support/player_steps.dart), [`support/library_steps.dart`](support/library_steps.dart), [`support/playlist_steps.dart`](support/playlist_steps.dart), [`support/settings_steps.dart`](support/settings_steps.dart) | Feature steps as `AppDriver` extensions (`openPlayer`, `openArtist`, `holdPlaylist`) | None |
| [`support/feature_scenario.dart`](support/feature_scenario.dart) | Registers each scenario × profile; inapplicable pairs show as skipped | None |
| [`player/`](player/player_scenarios.dart), [`library/`](library/library_scenarios.dart), [`playlists/`](playlists/playlist_scenarios.dart), [`settings/`](settings/settings_scenarios.dart) | Scenarios per feature | None |

The driver pumps the real [`PhonoliteAppShell`](../../lib/bootstrap/phonolite_app_shell.dart),
so layout, navigation, dialogs and shortcuts are production code. Launch also
checks that the app shows the profile's expected player surface.

```sh
flutter test test/features
flutter test test/features/player_feature_test.dart --plain-name "player.skip"
```

[`feature_catalog_test.dart`](feature_catalog_test.dart) checks that every `covers`
ID exists in the [interaction catalog](../../integration_test/catalog/INTERACTIONS.md)
and prints the scenario × platform matrix.

## Adding coverage

- **New behavior:** add a `FeatureScenario` to the feature's list. Use `requires`
  for capabilities and `surfaces` for layout-specific behavior.
- **New feature:** add `<feature>/<feature>_scenarios.dart`, a
  `<feature>_feature_test.dart` entry point, a `<feature>_steps.dart` driver
  extension if it needs new steps, and register its list in
  `feature_catalog_test.dart`.
- **New platform difference:** add a `Capability` (or profile field) and teach
  the driver how to perform the step. Do not branch on platform in a scenario.
  For example, `goBack()` is Android system back, the iOS edge swipe, or the
  desktop mouse Back button, chosen by the profile's `back` field.
- **Platform-only UI:** assert it with `expectShownExactlyWhen(capability, text)`,
  which checks presence where the profile has the capability and absence
  everywhere else (for example the Desktop settings and App updates tile).
- **Waiting:** steps call `settle()`, a bounded pump, because playing-state
  animations never let `pumpAndSettle` finish. It also gives the real event
  loop a few short turns so file I/O can complete; `waitUntil` waits longer for
  a specific condition.

## Storage and background work

Each run gets its own temporary app-support directory (`AppDriver.storage`),
answered on the `path_provider` channel, so real settings files are written
there and deleted afterwards. Work that never completes under the widget
test's fake clock stays in `WorldController` instead: the listening-statistics
SQLite isolate, and preference writes that `close()` would wait on.

Each run also builds its own settings controllers (`AppDriver.settings`) and
passes them through `PhonoliteAppShell` into
[`SettingsScope`](../../lib/ui/settings_scope.dart). Pages read display,
download, desktop and update settings from that scope, so preference state and
pending saves never carry over between scenarios. The installed app passes the
process-wide controllers (`AppSettingsControllers.shared`).

This tier proves product behavior through the real UI, without native code.
Native backends keep their own contract tests under `test/platform`, and
physical-device timing stays in `integration_test`.
