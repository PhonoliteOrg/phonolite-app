import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';
import 'package:phonolite_app/infrastructure/server/transport/sse_transport.dart';

class ServerEventsApi {
  final SseTransport _events;

  ServerEventsApi(ApiTransport transport) : _events = SseTransport(transport);

  Stream<MetadataUpdateEvent> streamMetadataEvents() =>
      // The server sends a keep-alive comment every 15 s; silence for 45 s means a dead connection.
      _events.openJson(
        path: '/library/metadata-events',
        decode: _decodeMetadata,
        idleTimeout: const Duration(seconds: 45),
      );

  MetadataUpdateEvent? _decodeMetadata(Map<String, dynamic> json) {
    final event = MetadataUpdateEvent.fromJson(json);

    return event.kind.isNotEmpty && event.id.isNotEmpty ? event : null;
  }
}
