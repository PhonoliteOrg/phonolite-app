import 'dart:async';

import 'package:phonolite_app/data/models/playback/custom_shuffle_settings.dart';
import 'package:phonolite_app/data/models/playback/playback_source_context.dart';
import 'package:phonolite_app/data/storage/preferences/custom_shuffle_settings_storage.dart';
import 'package:phonolite_app/data/structures/async/serial_action_queue.dart';

/// Active local and account shuffle choices. A delayed load may only update
/// filters which have not been edited or switched to a different account.
class ShufflePreferences {
  final CustomShuffleSettingsStorage _store;
  final _changes = StreamController<CustomShuffleSettings>.broadcast();
  bool _closed = false;
  CustomShuffleSettings _customShuffleSettings = const CustomShuffleSettings();
  Future<void>? _customShuffleLoadFuture;
  final _customShuffleSaves = SerialActionQueue();
  String? _shuffleAccountScope;
  int _shuffleAccountGeneration = 0;
  int _shuffleLoadGeneration = 0;
  int _localShuffleLoadGeneration = 0;
  int _serverShuffleMutation = 0;
  int _localShuffleMutation = 0;

  ShufflePreferences(this._store);

  int get accountGeneration => _shuffleAccountGeneration;
  CustomShuffleSettings get value => _customShuffleSettings;
  Stream<CustomShuffleSettings> get changes => _changes.stream;

  void _publish() {
    _customShuffleSettings = CustomShuffleSettings(
      artistIds: List.unmodifiable(_customShuffleSettings.artistIds),
      genres: List.unmodifiable(_customShuffleSettings.genres),
      localArtistIds: List.unmodifiable(_customShuffleSettings.localArtistIds),
      localGenres: List.unmodifiable(_customShuffleSettings.localGenres),
    );
    if (!_closed) _changes.add(_customShuffleSettings);
  }

  Future<void> close() async {
    _closed = true;
    unawaited(_changes.close());
    await _customShuffleSaves.drain();
  }

  Future<void> update({
    List<String>? artistIds,
    List<String>? genres,
    List<String>? localArtistIds,
    List<String>? localGenres,
  }) {
    if (_closed) return Future.value();
    final scope = _shuffleAccountScope;
    final accountGeneration = _shuffleAccountGeneration;
    final changesServerFilters = artistIds != null || genres != null;
    final changesLocalFilters = localArtistIds != null || localGenres != null;
    final next = CustomShuffleSettings(
      artistIds: _normalizeCustomList(artistIds ?? _customShuffleSettings.artistIds),
      genres: _normalizeCustomList(genres ?? _customShuffleSettings.genres, lowerCase: true),
      localArtistIds: _normalizeCustomList(localArtistIds ?? _customShuffleSettings.localArtistIds),
      localGenres: _normalizeCustomList(localGenres ?? _customShuffleSettings.localGenres, lowerCase: true),
    );

    if (changesServerFilters) {
      _serverShuffleMutation++;
    }

    if (changesLocalFilters) {
      _localShuffleMutation++;
    }

    _customShuffleSettings = next;
    _publish();

    return _customShuffleSaves.add(() async {
      if (changesLocalFilters) {
        await _store.writeLocal(next);
      }

      if (changesServerFilters &&
          scope != null &&
          _shuffleAccountScope == scope &&
          _shuffleAccountGeneration == accountGeneration) {
        await _store.writeForAccount(scope, next);
      }
    });
  }

  void restoreShuffleFilters(PlaybackSourceContext context, {required bool local}) {
    _customShuffleSettings = _customShuffleSettings.copyWith(
      artistIds: local ? null : context.artistIds,
      genres: local ? null : context.genres,
      localArtistIds: local ? context.artistIds : null,
      localGenres: local ? context.genres : null,
    );
    _publish();
  }

  Future<void> selectAccount(String? scope) async {
    if (_closed ||
        (_shuffleAccountScope == scope &&
            (scope != null || (_customShuffleSettings.artistIds.isEmpty && _customShuffleSettings.genres.isEmpty)))) {
      return;
    }

    _shuffleAccountScope = scope;
    _shuffleAccountGeneration++;
    _serverShuffleMutation++;
    _customShuffleSettings = _customShuffleSettings.copyWith(artistIds: const [], genres: const []);
    _publish();
    _customShuffleLoadFuture = _loadCustomShuffleSettings(loadLocal: false);

    await _customShuffleLoadFuture;
  }

  Future<void> _loadCustomShuffleSettings({bool loadLocal = true}) async {
    final scope = _shuffleAccountScope;
    final generation = ++_shuffleLoadGeneration;
    final localGeneration = loadLocal ? ++_localShuffleLoadGeneration : _localShuffleLoadGeneration;
    final serverMutation = _serverShuffleMutation;
    final localMutation = _localShuffleMutation;
    final settings = loadLocal ? await _store.read() : null;
    final accountSettings = scope == null ? const CustomShuffleSettings() : await _store.readForAccount(scope);

    if (_closed) {
      return;
    }

    final applyServer =
        generation == _shuffleLoadGeneration &&
        scope == _shuffleAccountScope &&
        serverMutation == _serverShuffleMutation;
    final applyLocal =
        settings != null && localGeneration == _localShuffleLoadGeneration && localMutation == _localShuffleMutation;

    if (!applyServer && !applyLocal) {
      return;
    }

    _customShuffleSettings = CustomShuffleSettings(
      artistIds: applyServer ? accountSettings.artistIds : _customShuffleSettings.artistIds,
      genres: applyServer ? accountSettings.genres : _customShuffleSettings.genres,
      localArtistIds: applyLocal ? settings.localArtistIds : _customShuffleSettings.localArtistIds,
      localGenres: applyLocal ? settings.localGenres : _customShuffleSettings.localGenres,
    );
    _publish();
  }

  Future<void> load({bool force = false}) async {
    if (force || _customShuffleLoadFuture == null) {
      _customShuffleLoadFuture = _loadCustomShuffleSettings();
    }

    await _customShuffleLoadFuture;
  }

  List<String> _normalizeCustomList(List<String> values, {bool lowerCase = false}) {
    final seen = <String>{};
    final result = <String>[];

    for (final raw in values) {
      var value = raw.trim();

      if (value.isEmpty) {
        continue;
      }

      if (lowerCase) {
        value = value.toLowerCase();
      }

      if (seen.add(value)) {
        result.add(value);
      }
    }

    return List.unmodifiable(result);
  }
}
