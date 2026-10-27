import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';
import 'package:phonolite_app/data/models/playback/shuffle_preset_snapshot.dart';
import 'package:phonolite_app/infrastructure/server/api/json_api_endpoint.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class ShufflePresetsApi extends JsonApiEndpoint {
  ShufflePresetsApi(super.transport);

  Future<ShufflePresetSnapshot> fetchPresets() => getValue('/account/shuffle-presets', ShufflePresetSnapshot.fromJson);

  Future<ShufflePreset> createPreset({
    required String name,
    required List<String> artistIds,
    required List<String> genres,
  }) => postValue('/account/shuffle-presets', {
    'name': name,
    'artist_ids': artistIds,
    'genres': genres,
  }, ShufflePreset.fromJson);

  Future<ShufflePreset> updatePreset(
    String id, {
    required String name,
    required List<String> artistIds,
    required List<String> genres,
    required int expectedRevision,
  }) {
    final encoded = ApiTransport.encodePathSegment(id);

    return postValue('/account/shuffle-presets/$encoded', {
      'name': name,
      'artist_ids': artistIds,
      'genres': genres,
      'expected_revision': expectedRevision,
    }, ShufflePreset.fromJson);
  }

  Future<void> deletePreset(String id, {required int expectedRevision}) {
    final encoded = ApiTransport.encodePathSegment(id);

    return transport.delete('/account/shuffle-presets/$encoded?expected_revision=$expectedRevision');
  }
}
