import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';

typedef ShufflePageLoader = Future<ShuffleSessionPage> Function(int offset);

/// A future occurrence in a deck. Reserving it never advances audible history.
class ServerShuffleReservation {
  final String sessionId;
  final int origin;
  final int position;
  final Track track;

  const ServerShuffleReservation({
    required this.sessionId,
    required this.origin,
    required this.position,
    required this.track,
  });
}

/// Keeps the previous, current and upcoming ten-ID pages in memory. Absolute
/// offsets let Previous reload history without downloading the full deck.
class ServerShuffleDeck {
  static const pageSize = 10;
  final String sessionId;
  final int total;
  final ShufflePageLoader _load;
  final _pages = <int, ShuffleSessionPage>{};
  final _loading = <int, Future<ShuffleSessionPage?>>{};
  bool _closed = false;
  int _position = -1;
  final _reservations = <int, ServerShuffleReservation>{};
  ServerShuffleReservation? _lastCommittedReservation;
  int _navigationRevision = 0;

  ServerShuffleDeck(ShuffleSessionPage first, {required ShufflePageLoader load})
    : sessionId = first.sessionId,
      total = first.total,
      _load = load {
    _validate(first, first.offset);
    _pages[first.offset] = first;
  }

  int get position => _position;
  bool get isClosed => _closed;
  List<MapEntry<int, Track>> get _entries {
    final entries = [
      for (final page in _pages.values)
        for (var i = 0; i < page.items.length; i++) MapEntry(page.itemOffsets[i], page.items[i]),
    ];
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  List<Track> get tracks => _entries.map((entry) => entry.value).toList(growable: false);
  int get queueIndex => _entries.indexWhere((entry) => entry.key == _position);

  /// Restores the absolute cursor, skipping IDs removed since the deck was saved.
  Future<bool> restorePosition(int position) async {
    if (position < 0 || position >= total) return false;

    _position = position - 1;
    if (await move(1)) return true;

    _position = position + 1;
    return move(-1);
  }

  /// Keeps a playing track outside the deck while Next selects this candidate.
  void retainExternalCurrent() {
    _navigationRevision++;
    _reservations.clear();
    _lastCommittedReservation = null;
    if (_position >= 0) {
      _position--;
    }
  }

  Future<bool> initialize({required bool play, String? currentTrackId}) async {
    if (play) return move(1);
    final anchored = _entries.where((entry) => entry.value.id == currentTrackId).firstOrNull;
    if (anchored != null) {
      _position = anchored.key;
      return true;
    }
    // An ineligible current track stays outside this deck. Next selects the
    // first surviving item, even when deleted IDs make the first page empty.
    final available = await move(1);
    if (available) _position--;
    return available;
  }

  Future<bool> move(int direction) async {
    _navigationRevision++;
    _reservations.clear();
    _lastCommittedReservation = null;
    if (_closed || total == 0) return false;
    var candidate = _position + direction;
    var wrapped = false;
    if (direction < 0 && candidate < 0) {
      candidate = total - 1;
      wrapped = true;
    }
    while (!_closed && candidate >= 0 && candidate < total) {
      final offset = (candidate ~/ pageSize) * pageSize;
      final page = await _page(offset);
      if (_closed || page == null) return false;
      _trim(offset);
      final available = page.itemOffsets.where((value) => direction > 0 ? value >= candidate : value <= candidate);
      if (available.isNotEmpty) {
        _position = direction > 0 ? available.first : available.last;
        _trim(offset);
        return true;
      }
      candidate = direction > 0 ? page.nextOffset : offset - 1;
      if (direction < 0 && candidate < 0 && !wrapped) {
        candidate = total - 1;
        wrapped = true;
      }
    }
    return false;
  }

  /// Loads a successor, including across pages containing deleted IDs, while
  /// leaving the current cursor untouched. A concurrent navigation invalidates
  /// the reservation instead of letting a slow page response select old audio.
  Future<ServerShuffleReservation?> reserveNext({ServerShuffleReservation? after}) async {
    if (after != null &&
        (after.sessionId != sessionId ||
            (!identical(_reservations[after.position], after) &&
                !(after.position == _position && identical(_lastCommittedReservation, after))))) {
      return null;
    }
    final origin = after?.position ?? _position;
    final revision = _navigationRevision;
    bool isCurrent() =>
        !_closed &&
        _navigationRevision == revision &&
        (after == null
            ? _position == origin
            : _position <= origin &&
                  (identical(_reservations[origin], after) ||
                      (_position == origin && identical(_lastCommittedReservation, after))));
    final existing = _reservations.values.where((item) => item.origin == origin).firstOrNull;
    if (existing != null) return existing;
    // Two reserved occurrences are sufficient for the bounded short-track
    // lookahead. Callers cannot pin arbitrarily many pages by peeking ahead.
    if (_reservations.length >= 2) return null;
    var candidate = origin + 1;
    while (isCurrent() && candidate < total) {
      final offset = (candidate ~/ pageSize) * pageSize;
      final page = await _page(offset);
      if (!isCurrent() || page == null) return null;
      final index = page.itemOffsets.indexWhere((value) => value >= candidate);
      if (index >= 0) {
        final reservation = ServerShuffleReservation(
          sessionId: sessionId,
          origin: origin,
          position: page.itemOffsets[index],
          track: page.items[index],
        );
        _reservations[reservation.position] = reservation;
        _trim((_position.clamp(0, total) ~/ pageSize) * pageSize);
        return reservation;
      }
      if (offset != (_position ~/ pageSize) * pageSize &&
          !_reservations.keys.any((position) => position ~/ pageSize == offset ~/ pageSize)) {
        _pages.remove(offset);
      }
      candidate = page.nextOffset;
    }
    return null;
  }

  bool commitReservation(ServerShuffleReservation reservation) {
    if (_closed ||
        reservation.sessionId != sessionId ||
        reservation.origin != _position ||
        !identical(_reservations[reservation.position], reservation)) {
      return false;
    }
    final page = _pages[(reservation.position ~/ pageSize) * pageSize];
    final index = page?.itemOffsets.indexOf(reservation.position) ?? -1;
    if (page == null || index < 0 || page.items[index].id != reservation.track.id) return false;
    _position = reservation.position;
    _lastCommittedReservation = reservation;
    _reservations.remove(reservation.position);
    _trim((_position ~/ pageSize) * pageSize);
    return true;
  }

  void cancelReservation(ServerShuffleReservation reservation) {
    if (!identical(_reservations[reservation.position], reservation)) return;
    _reservations.removeWhere((position, _) => position >= reservation.position);
    _trim((_position.clamp(0, total) ~/ pageSize) * pageSize);
  }

  Future<void> prefetch() async {
    if (_closed || _position < 0) return;
    final offset = (_position ~/ pageSize) * pageSize;
    final page = _pages[offset];
    if (page == null || !page.hasMore || page.itemOffsets.where((value) => value > _position).length > 3) return;
    await _page(page.nextOffset);
    if (!_closed) _trim((_position ~/ pageSize) * pageSize);
  }

  void close() {
    _closed = true;
    _navigationRevision++;
    _reservations.clear();
    _lastCommittedReservation = null;
    _pages.clear();
    _loading.clear();
  }

  Future<ShuffleSessionPage?> _page(int offset) {
    if (_closed) return Future.value();
    final existing = _pages[offset];
    if (existing != null) return Future.value(existing);
    return _loading.putIfAbsent(offset, () async {
      try {
        final page = await _load(offset);
        if (_closed) return null;
        _validate(page, offset);
        _pages[offset] = page;
        return page;
      } finally {
        _loading.remove(offset);
      }
    });
  }

  void _trim(int around) {
    final reservedPages = _reservations.keys.map((position) => (position ~/ pageSize) * pageSize).toSet();
    _pages.removeWhere((offset, _) => !reservedPages.contains(offset) && (offset - around).abs() > pageSize);
  }

  void _validate(ShuffleSessionPage page, int expectedOffset) {
    if (page.sessionId != sessionId ||
        page.offset != expectedOffset ||
        page.total != total ||
        total < 0 ||
        sessionId.isEmpty ||
        page.offset < 0 ||
        page.nextOffset < page.offset ||
        page.nextOffset > total ||
        page.nextOffset != (page.offset + pageSize).clamp(0, total) ||
        page.hasMore != (page.nextOffset < total) ||
        (page.hasMore && page.nextOffset <= page.offset) ||
        page.items.length != page.itemOffsets.length ||
        page.itemOffsets.toSet().length != page.itemOffsets.length ||
        page.itemOffsets.any((value) => value < page.offset || value >= page.nextOffset)) {
      throw const FormatException('Invalid server shuffle page');
    }
    for (var i = 1; i < page.itemOffsets.length; i++) {
      if (page.itemOffsets[i] <= page.itemOffsets[i - 1]) throw const FormatException('Unordered server shuffle page');
    }
  }
}
