import 'dart:collection';

import 'package:phonolite_app/data/models/library/artist_summary.dart';

/// A stable logical list with a bounded materialized page window.
/// Missing positions retain their size and identity until requested again.
class ArtistBrowseSnapshot {
  final int total;
  final int pageSize;
  final String? revision;
  final Map<int, ArtistSummaryPage> pages;
  final Set<int> loadingPages;
  final int retainedBytes;

  const ArtistBrowseSnapshot({
    this.total = 0,
    this.pageSize = 60,
    this.revision,
    this.pages = const {},
    this.loadingPages = const {},
    this.retainedBytes = 0,
  });

  ArtistSummary? at(int index) {
    final page = pages[index ~/ pageSize];
    final local = index % pageSize;

    return page != null && local < page.items.length ? page.items[local] : null;
  }

  List<int> get indices => _ArtistIndices(total);
}

/// Constant-size index view; rebuilding the viewport does not allocate N indices.
class _ArtistIndices extends ListBase<int> {
  final int _length;

  _ArtistIndices(this._length);

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Artist indices are immutable');

  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this);

    return index;
  }

  @override
  void operator []=(int index, int value) => throw UnsupportedError('Artist indices are immutable');
}
