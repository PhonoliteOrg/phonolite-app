import 'package:flutter/foundation.dart' show immutable;

@immutable
class LocalLikeState {
  final String localTrackId;
  final bool liked;
  final int updatedAt;

  const LocalLikeState({required this.localTrackId, required this.liked, required this.updatedAt});
}
