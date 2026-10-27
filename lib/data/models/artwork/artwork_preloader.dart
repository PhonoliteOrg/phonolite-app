import 'package:phonolite_app/data/models/artwork/artwork_request.dart';

/// A borrowed capability that keeps an ordered artwork window ready to display.
/// Updating the window never waits for images or delays playback. The composition
/// owns its resources; consumers release their window with [clear].
abstract interface class ArtworkPreloader {
  void update(Iterable<ArtworkRequest> requests);

  void clear();
}
