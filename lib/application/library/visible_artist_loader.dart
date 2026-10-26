import 'dart:async';
import 'dart:collection';

import 'package:phonolite_app/data/models/library/artist.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';

/// Short-lived metadata for the artists currently on screen. Detail reads also
/// trigger the server's enrichment path; push updates normally finish the load.
/// A few bounded follow-up reads recover when an update event is missed.
class VisibleArtistLoader {
  final Future<Artist> Function(String) fetch;
  final Stream<Artist> Function(String) watch;
  final void Function() onChanged;
  final void Function(String, Object)? onError;
  final int concurrency;
  final int maxVisible;
  final List<Duration> retryDelays;
  final _visible = <String, _VisibleArtist>{};
  final _queue = Queue<_VisibleArtist>();
  int _inFlight = 0;
  bool _disposed = false;

  VisibleArtistLoader({
    required this.fetch,
    required this.watch,
    required this.onChanged,
    this.onError,
    this.concurrency = 3,
    this.maxVisible = 128,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)],
  }) : assert(concurrency > 0),
       assert(maxVisible > 0);

  Artist resolve(Artist source) {
    // Fresh list metadata takes precedence over our temporary overlay.
    return _hasLogo(source) ? source : _visible[source.id]?.artist ?? source;
  }

  void setVisible(Artist artist, bool visible) {
    if (_disposed) {
      return;
    }
    if (!visible) {
      final entry = _visible.remove(artist.id);
      if (entry != null) {
        _release(entry);
      }
      return;
    }
    if (_visible.containsKey(artist.id)) {
      return;
    }

    if (_visible.length >= maxVisible) {
      return;
    }

    final entry = _VisibleArtist(artist);
    _visible[artist.id] = entry;
    entry.subscription = watch(artist.id).listen(
      (updated) {
        if (_isCurrent(entry) && updated.id == artist.id) {
          entry.revision++;
          _apply(entry, updated);
        }
      },
      onError: (Object error) {
        if (_isCurrent(entry)) {
          onError?.call(artist.id, error);
        }
      },
    );
    _enqueue(entry);
  }

  void clear() {
    for (final entry in _visible.values) {
      _release(entry);
    }
    _visible.clear();
    _queue.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  bool _isCurrent(_VisibleArtist entry) => !_disposed && identical(_visible[entry.artist.id], entry);

  static bool _hasLogo(Artist artist) => artist.logoRef?.trim().isNotEmpty == true;

  void _release(_VisibleArtist entry) {
    entry.timer?.cancel();
    unawaited(entry.subscription?.cancel());
    _queue.remove(entry);
    // No notification: a tile leaving the viewport needs no metadata rebuild.
  }

  void _enqueue(_VisibleArtist entry) {
    if (!_isCurrent(entry) || _hasLogo(entry.artist) || entry.inFlight || _queue.contains(entry)) {
      return;
    }
    _queue.add(entry);
    _drain();
  }

  void _drain() {
    while (!_disposed && _inFlight < concurrency && _queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      if (!_isCurrent(entry) || _hasLogo(entry.artist)) {
        continue;
      }
      entry.inFlight = true;
      _inFlight++;
      unawaited(_read(entry));
    }
  }

  Future<void> _read(_VisibleArtist entry) async {
    final revision = entry.revision;
    Duration? retryAfter;
    var retryable = true;
    entry.attempts++;
    try {
      final updated = await fetch(entry.artist.id);
      if (_isCurrent(entry) && entry.revision == revision && updated.id == entry.artist.id) {
        _apply(entry, updated);
      }
    } catch (error) {
      if (error is ApiException) {
        retryable = !const [401, 403, 404, 410].contains(error.statusCode);
        retryAfter = error.retryAfter;
      }
      if (_isCurrent(entry)) {
        onError?.call(entry.artist.id, error);
      }
    } finally {
      entry.inFlight = false;
      _inFlight--;
      if (retryable && _isCurrent(entry) && !_hasLogo(entry.artist) && entry.attempts <= retryDelays.length) {
        entry.timer = Timer(retryAfter ?? retryDelays[entry.attempts - 1], () => _enqueue(entry));
      }
      _drain();
    }
  }

  void _apply(_VisibleArtist entry, Artist updated) {
    if (_hasLogo(updated)) {
      entry.timer?.cancel();
      _queue.remove(entry);
    }
    if (!entry.artist.hasSameMetadata(updated)) {
      entry.artist = updated;
      onChanged();
    }
  }
}

class _VisibleArtist {
  Artist artist;
  StreamSubscription<Artist>? subscription;
  Timer? timer;
  int revision = 0;
  int attempts = 0;
  bool inFlight = false;

  _VisibleArtist(this.artist);
}
