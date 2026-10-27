import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';
import 'package:phonolite_app/infrastructure/server/transport/sse_transport.dart';

class ServerEventsApi {
  final SseTransport _events;

  ServerEventsApi(ApiTransport transport) : _events = SseTransport(transport);

  Stream<MetadataUpdateEvent> streamMetadataEvents() =>
      _events.openJson(path: '/library/metadata-events', decode: _decodeMetadata);

  MetadataUpdateEvent? _decodeMetadata(Map<String, dynamic> json) {
    final event = MetadataUpdateEvent.fromJson(json);

    return event.kind.isNotEmpty && event.id.isNotEmpty ? event : null;
  }
}
