import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/server/shuffle_session_page.dart';

typedef ShufflePageLoader = Future<ShuffleSessionPage> Function(int offset);

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

  void _trim(int around) => _pages.removeWhere((offset, _) => (offset - around).abs() > pageSize);

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
