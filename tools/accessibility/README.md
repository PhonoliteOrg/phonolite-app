# Replay Windows accessibility updates

The debug startup capture records structural deltas using the prefix
`Windows accessibility update ` followed by JSON. The replay tool selects the
latest session containing a consecutive sequence starting at batch 1, converts
its node IDs and traversal-child lists, and can validate them with Flutter's
native accessibility tree. Use `--session` to select a particular session.

From the app directory, convert the default Windows log:

```powershell
python tools/accessibility/replay_windows_accessibility.py "$env:APPDATA/Phonolite/logs/debug.log"
```

Build the headless native replayer using source already present in the Flutter
SDK. These commands compile a test executable; they do not launch Phonolite,
create windows, or start servers:

```powershell
cmake -S tools/accessibility/native -B build/accessibility_native -G "Visual Studio 17 2022" -A x64 -DFLUTTER_ENGINE_ROOT="C:/path/to/flutter/engine/src"
cmake --build build/accessibility_native --config Release
python tools/accessibility/replay_windows_accessibility.py "$env:APPDATA/Phonolite/logs/debug.log" --native-executable build/accessibility_native/Release/native_ax_replay.exe
```

The replayer compiles the SDK's AXTree, AXNode, and portable geometry source
without modifying them. It reproduces the bridge's preliminary subtree removal
and main-update ordering. Only structural node fields are supplied, with generic
roles; this isolates tree-integrity errors and does not test screen-reader
presentation. A small local string-formatting shim replaces the SDK checkout's
missing external double-conversion dependency. No SDK source is vendored.

The native tool stops at the first rejected update and prints its batch, phase,
and native error. A successful conversion alone is not native verification.
The bridge's debug assertion for missing reparented-node data is printed as a
diagnostic, then replay continues to AXTree as in the shipped release engine.
Incomplete or out-of-order sessions are rejected or skipped with an explanation;
the tool never combines different sessions.

The two synthetic fixtures demonstrate why final-graph checks are insufficient:

```powershell
build/accessibility_native/Release/native_ax_replay.exe test/fixtures/accessibility/missing_descendant.txt
build/accessibility_native/Release/native_ax_replay.exe test/fixtures/accessibility/complete_descendant.txt
```

The first deliberately fails with `Nodes left pending by the update: 31`; the
second passes. Running the native executable without a file also runs this
positive/negative regression pair and exits successfully only when both behave
as expected.

The actual startup capture is also preserved as structural-only fixtures:

```powershell
build/accessibility_native/Release/native_ax_replay.exe test/fixtures/accessibility/windows_startup_reparent.txt
build/accessibility_native/Release/native_ax_replay.exe test/fixtures/accessibility/windows_startup_reparent_complete.txt
```

The original capture fails in batch 6 with the reported pending-node error; the
positive control resends omitted node `31` and passes all six batches.
