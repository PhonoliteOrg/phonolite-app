import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'package:phonolite_app/data/models/library/metadata_update_event.dart';
import 'package:phonolite_app/data/models/server/server_errors.dart';
import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

class ServerEventsApi {
  final ApiTransport _transport;

  ServerEventsApi(this._transport);

  Stream<MetadataUpdateEvent> streamMetadataEvents() async* {
    final request = http.Request('GET', Uri.parse('${_transport.baseUrl}/library/metadata-events'));
    request.headers.addAll(_transport.buildHeaders());

    final response = await _transport.client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();

      throw ApiException(response.statusCode, body);
    }

    var buffer = '';

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer = (buffer + chunk).replaceAll('\r\n', '\n');
      var separator = buffer.indexOf('\n\n');

      while (separator >= 0) {
        final frame = buffer.substring(0, separator);
        buffer = buffer.substring(separator + 2);

        final event = _metadataEventFromSseFrame(frame);

        if (event != null) {
          yield event;
        }

        separator = buffer.indexOf('\n\n');
      }
    }

    final trailingFrame = buffer.trim();

    if (trailingFrame.isNotEmpty) {
      final event = _metadataEventFromSseFrame(trailingFrame);

      if (event != null) {
        yield event;
      }
    }
  }
}

MetadataUpdateEvent? _metadataEventFromSseFrame(String frame) {
  final data = <String>[];

  for (final rawLine in frame.split('\n')) {
    final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;

    if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }

  if (data.isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(data.join('\n'));

    if (decoded is Map<String, dynamic>) {
      final event = MetadataUpdateEvent.fromJson(decoded);

      if (event.kind.isNotEmpty && event.id.isNotEmpty) {
        return event;
      }
    }
  } catch (err, stackTrace) {
    developer.log('Ignoring malformed metadata event', name: 'ServerConnection', error: err, stackTrace: stackTrace);
  }

  return null;
}
