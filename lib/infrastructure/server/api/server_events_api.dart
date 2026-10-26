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

  Stream<MetadataUpdateEvent> streamMetadataEvents() {
    late final StreamController<MetadataUpdateEvent> controller;
    StreamSubscription<String>? bodySubscription;
    var cancelled = false;
    var buffer = '';

    void closeStream() {
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }

    void handleError(Object error, StackTrace stackTrace) {
      if (!cancelled && !controller.isClosed) {
        controller.addError(error, stackTrace);
        closeStream();
      }
    }

    void handleChunk(String chunk) {
      if (cancelled || controller.isClosed) {
        return;
      }

      buffer = (buffer + chunk).replaceAll('\r\n', '\n');
      var separator = buffer.indexOf('\n\n');

      while (separator >= 0) {
        final frame = buffer.substring(0, separator);
        buffer = buffer.substring(separator + 2);

        final event = _metadataEventFromSseFrame(frame);

        if (event != null) {
          controller.add(event);
        }

        separator = buffer.indexOf('\n\n');
      }
    }

    Future<void> openStream() async {
      try {
        final request = http.Request('GET', Uri.parse('${_transport.baseUrl}/library/metadata-events'));
        request.headers.addAll(_transport.buildHeaders());
        final response = await _transport.client.send(request);

        if (cancelled) {
          // A request may finish after Quit. Consume and cancel its body so
          // closing the shared client cannot leave an unobserved stream error.
          await response.stream.listen(null, onError: (Object _, StackTrace _) {}).cancel();
          return;
        }

        final successful = response.statusCode >= 200 && response.statusCode < 300;
        final errorBody = StringBuffer();
        bodySubscription = response.stream
            .transform(utf8.decoder)
            .listen(
              (chunk) {
                if (successful) {
                  handleChunk(chunk);
                } else {
                  errorBody.write(chunk);
                }
              },
              onError: handleError,
              onDone: () {
                bodySubscription = null;
                if (cancelled || controller.isClosed) {
                  return;
                }

                if (!successful) {
                  controller.addError(ApiException(response.statusCode, errorBody.toString()));
                } else {
                  final trailingFrame = buffer.trim();
                  if (trailingFrame.isNotEmpty) {
                    final event = _metadataEventFromSseFrame(trailingFrame);
                    if (event != null) {
                      controller.add(event);
                    }
                  }
                }
                closeStream();
              },
            );

        if (controller.isPaused) {
          bodySubscription!.pause();
        }
      } catch (error, stackTrace) {
        handleError(error, stackTrace);
      }
    }

    // An async* generator cannot interrupt an idle network await on cancel.
    // Own the response subscription directly so shutdown can release it now.
    controller = StreamController<MetadataUpdateEvent>(
      onListen: () => unawaited(openStream()),
      onPause: () => bodySubscription?.pause(),
      onResume: () => bodySubscription?.resume(),
      onCancel: () {
        cancelled = true;
        final subscription = bodySubscription;
        bodySubscription = null;
        return subscription?.cancel();
      },
    );

    return controller.stream;
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
