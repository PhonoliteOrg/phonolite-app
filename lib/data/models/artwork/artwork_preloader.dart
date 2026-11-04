import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

enum ArtworkPreparation { ready, unavailable, cancelled }

/// A borrowed capability that keeps an ordered artwork window ready to display.
/// [update] warms upcoming covers without waiting. [prepare] waits for a cover's
/// first decoded frame, or an artwork miss, before playback can begin. The
/// composition owns its resources; consumers release their window with [clear].
abstract interface class ArtworkPreloader {
  void update(Iterable<ArtworkRequest> requests);

  /// A cleared window cancels the wait; a still-current playback request can
  /// prepare its cover again. Failed or absent covers return unavailable.
  Future<ArtworkPreparation> prepare(ArtworkRequest request);

  void clear();
}
