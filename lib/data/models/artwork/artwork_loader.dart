import 'dart:typed_data';

import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

/// A borrowed loading capability. The application composition owns shutdown.
/// [cacheScope] changes when authenticated identity changes, preventing stale
/// decoded images from being reused by another session.
abstract interface class ArtworkLoader {
  String get cacheScope;

  int get sessionRevision;

  Future<Uint8List> load(ArtworkRequest request);

  /// Admits the complete load-and-codec operation before its bytes allocate.
  /// Waiting callbacks stay lightweight; a changed identity rejects old work.
  Future<T> decode<T>(String scope, Future<T> Function() operation);

  Future<void> invalidate(ArtworkRequest request);

  Future<void> close();
}
