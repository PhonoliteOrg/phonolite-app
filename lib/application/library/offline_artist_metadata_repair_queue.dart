import 'dart:async';

/// Coalesces downloaded-artist events without launching parallel repair sweeps.
/// Overflow uses a cursor over current local state instead of retaining more IDs.
class OfflineArtistMetadataRepairQueue {
  final Future<void> Function(String id) repair;
  final bool Function(String id) isDownloaded;
  final String? Function(int index) downloadedArtistAt;
  final void Function(Object error)? onError;
  final int maxQueued;
  final Duration delay;
  final _pending = <String>{};
  Timer? _timer;
  Future<void>? _running;
  int _generation = 0;
  int _cursor = 0;
  bool _reconcile = false;
  bool _closed = false;

  OfflineArtistMetadataRepairQueue({
    required this.repair,
    required this.isDownloaded,
    required this.downloadedArtistAt,
    this.onError,
    this.maxQueued = 128,
    this.delay = const Duration(milliseconds: 300),
  }) : assert(maxQueued > 0);

  int get queued => _pending.length;

  bool get running => _running != null;

  Future<void> close() async {
    _closed = true;
    reset();
    // The download runtime owns the in-flight operation. Queue shutdown must
    // not wait for an entire large artist's remote metadata repair indefinitely.
    await _running?.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _reconcile = false;
    _cursor = 0;
  }

  void schedule(String id) {
    if (_closed || !isDownloaded(id)) {
      return;
    }

    if (_pending.length >= maxQueued && !_pending.contains(id)) {
      _reconcile = true;
    } else {
      _pending.add(id);
    }

    _schedule();
  }

  void _schedule() {
    if (_closed || _timer != null || _running != null || (_pending.isEmpty && !_reconcile)) {
      return;
    }

    _timer = Timer(delay, () {
      _timer = null;
      _running = _drain().whenComplete(() {
        _running = null;
        _schedule();
      });
    });
  }

  Future<void> _drain() async {
    final generation = _generation;

    while (!_closed && generation == _generation) {
      String? id;

      if (_pending.isNotEmpty) {
        id = _pending.first;
        _pending.remove(id);
      } else if (_reconcile) {
        id = downloadedArtistAt(_cursor++);

        if (id == null) {
          _reconcile = false;
          _cursor = 0;
        }
      }

      if (id == null) {
        return;
      }

      try {
        await repair(id);
      } catch (error) {
        onError?.call(error);
      }
    }
  }
}
