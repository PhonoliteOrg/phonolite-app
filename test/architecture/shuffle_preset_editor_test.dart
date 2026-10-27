import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/application/controllers/playback/shuffle_preset_editor_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';

import '../support/shuffle_preset_test_helpers.dart';

void main() {
  test('editing and cancelling never changes applied rules or writes a preset', () async {
    final app = PresetTestApp();
    final editor = ShufflePresetEditorController(app, preset: app.shufflePresets.single);
    addTearDown(app.close);
    await editor.initialize();

    editor.toggleArtist('beta');
    editor.toggleGenre('jazz');
    editor.dispose();

    expect(app.writes, isEmpty);
    expect(app.localSaves, 0);
    expect(app.customShuffleSettings.artistIds, ['device-artist']);
  });

  test('saving shares preset rules while both devices retain their applied filters', () async {
    final first = PresetTestApp();
    final second = PresetTestApp();
    final editor = ShufflePresetEditorController(first);
    addTearDown(first.close);
    addTearDown(second.close);
    addTearDown(editor.dispose);
    await editor.initialize();

    editor.toggleArtist('beta');
    expect(await editor.submit('  Work music  '), isTrue);
    second.publish(first.shufflePresets);

    expect(first.writes.single['name'], 'Work music');
    expect(second.shufflePresets.last.artistIds, ['beta']);
    expect(first.applied, isEmpty);
    expect(second.applied, isEmpty);
    expect(first.customShuffleSettings.artistIds, ['device-artist']);
    expect(second.customShuffleSettings.artistIds, ['device-artist']);
  });

  test('live conflicts preserve draft and save copy creates without overwriting', () async {
    final app = PresetTestApp();
    final editor = ShufflePresetEditorController(app, preset: app.shufflePresets.single);
    addTearDown(app.close);
    addTearDown(editor.dispose);
    await editor.initialize();

    editor.toggleArtist('beta');
    app.publish([testShufflePreset(name: 'Remote name', revision: 2)]);

    expect(editor.conflict, isTrue);
    expect(editor.selectedArtistIds, {'alpha', 'beta'});
    expect(await editor.submit('My draft'), isFalse);
    expect(app.writes, isEmpty);
    expect(await editor.submit('My draft', saveCopy: true), isTrue);
    expect(app.writes.single['id'], isNull);
    expect(app.writes.single['expectedRevision'], isNull);
    expect(app.writes.single['artistIds'], ['alpha', 'beta']);
    expect(app.shufflePresets.first.name, 'Remote name');
  });

  test('reload explicitly discards the draft and adopts the newest revision', () async {
    final app = PresetTestApp();
    final editor = ShufflePresetEditorController(app, preset: app.shufflePresets.single);
    addTearDown(app.close);
    addTearDown(editor.dispose);
    await editor.initialize();
    editor.toggleArtist('beta');
    app.publish([testShufflePreset(name: 'New name', revision: 3)]);

    expect((await editor.reloadLatest())?.name, 'New name');
    expect(editor.selectedArtistIds, {'alpha'});
    expect(editor.conflict, isFalse);
    expect(await editor.submit('New name'), isTrue);
    expect(app.writes.single['expectedRevision'], 3);
  });

  test('409 and remote deletion preserve fields until saved as a new copy', () async {
    final app = PresetTestApp();
    final editor = ShufflePresetEditorController(app, preset: app.shufflePresets.single);
    addTearDown(app.close);
    addTearDown(editor.dispose);
    await editor.initialize();
    editor.toggleArtist('beta');
    app.conflictOnSave = true;

    expect(await editor.submit('My name'), isFalse);
    expect(editor.conflict, isTrue);
    expect(editor.selectedArtistIds, {'alpha', 'beta'});
    app.publish([]);
    expect(await editor.reloadLatest(), isNull);
    expect(editor.error, contains('deleted'));
    expect(editor.selectedArtistIds, {'alpha', 'beta'});
  });

  test('account replacement blocks a stale editor and late success cannot close it', () async {
    final app = PresetTestApp();
    final editor = ShufflePresetEditorController(app);
    addTearDown(app.close);
    addTearDown(editor.dispose);
    await editor.initialize();
    app.saveGate = Completer<void>();
    final pending = editor.submit('Draft');
    app.connection.sessionRevision++;
    app.authEvents.add(app.authState);
    app.saveGate!.complete();

    expect(await pending, isFalse);
    expect(editor.sessionValid, isFalse);
    expect(await editor.submit('Another'), isFalse);
    expect(app.writes, hasLength(1));
  });

  test('local drafts remain available offline and save only local fields', () async {
    final app = PresetTestApp();
    app.authState = AuthState(baseUrl: '', isAuthorized: false);
    final editor = ShufflePresetEditorController(app, local: true);
    addTearDown(app.close);
    addTearDown(editor.dispose);
    await editor.initialize();
    editor.toggleGenre('rock');

    expect(await editor.submit(''), isTrue);
    expect(app.customShuffleSettings.localGenres, ['rock']);
    expect(app.customShuffleSettings.artistIds, ['device-artist']);
    expect(app.customShuffleSettings.genres, ['jazz']);
    expect(app.writes, isEmpty);
  });
}
