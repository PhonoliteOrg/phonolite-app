import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef PulseSuccessCallback = Void Function(Pointer<Void>, Int32, Pointer<Void>);

/// Layouts from PulseAudio's public sample.h, def.h and volume.h.
final class PulseSampleSpec extends Struct {
  @Int32()
  external int format;
  @Uint32()
  external int rate;
  @Uint8()
  external int channels;
}

final class PulseBufferAttributes extends Struct {
  @Uint32()
  external int maximumLength;
  @Uint32()
  external int targetLength;
  @Uint32()
  external int prebuffer;
  @Uint32()
  external int minimumRequest;
  @Uint32()
  external int fragmentSize;
}

final class PulseVolume extends Struct {
  @Uint8()
  external int channels;
  @Array(32)
  external Array<Uint32> values;
}

/// libpulse's asynchronous API, driven without blocking or spawning a daemon.
class PulseAudioBindings {
  final Pointer<Void> Function() mainloopNew;
  final void Function(Pointer<Void>) mainloopFree;
  final Pointer<Void> Function(Pointer<Void>) mainloopApi;
  final int Function(Pointer<Void>, int, Pointer<Int32>) mainloopIterate;
  final Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>) contextNew;
  final int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>) contextConnect;
  final int Function(Pointer<Void>) contextState;
  final int Function(Pointer<Void>) contextError;
  final Pointer<Utf8> Function(int) errorString;
  final void Function(Pointer<Void>) contextDisconnect;
  final void Function(Pointer<Void>) contextUnref;
  final Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<PulseSampleSpec>, Pointer<Void>) streamNew;
  final int Function(Pointer<Void>, Pointer<Void>, Pointer<PulseBufferAttributes>, int, Pointer<Void>, Pointer<Void>)
  streamConnect;
  final int Function(Pointer<Void>) streamState;
  final int Function(Pointer<Void>) streamWritable;
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int, int) streamWrite;
  final int Function(Pointer<Void>, Pointer<Uint64>, Pointer<Int32>) streamLatency;
  final Pointer<Void> Function(Pointer<Void>, Pointer<NativeFunction<PulseSuccessCallback>>, Pointer<Void>) streamFlush;
  final Pointer<Void> Function(Pointer<Void>, Pointer<NativeFunction<PulseSuccessCallback>>, Pointer<Void>) streamDrain;
  final Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>, Pointer<Void>) streamCork;
  final int Function(Pointer<Void>) streamIndex;
  final int Function(Pointer<Void>) streamDisconnect;
  final void Function(Pointer<Void>) streamUnref;
  final Pointer<Void> Function(Pointer<Void>, int, Pointer<PulseVolume>, Pointer<Void>, Pointer<Void>) setVolume;
  final int Function(Pointer<Void>) operationState;
  final void Function(Pointer<Void>) operationCancel;
  final void Function(Pointer<Void>) operationUnref;

  PulseAudioBindings(DynamicLibrary library)
    : mainloopNew = library.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('pa_mainloop_new'),
      mainloopFree = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'pa_mainloop_free',
      ),
      mainloopApi = library
          .lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>(
            'pa_mainloop_get_api',
          ),
      mainloopIterate = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Int32>),
            int Function(Pointer<Void>, int, Pointer<Int32>)
          >('pa_mainloop_iterate'),
      contextNew = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
          >('pa_context_new'),
      contextConnect = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>, Int32, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>)
          >('pa_context_connect'),
      contextState = library.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_context_get_state',
      ),
      contextError = library.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_context_errno',
      ),
      errorString = library.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('pa_strerror'),
      contextDisconnect = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'pa_context_disconnect',
      ),
      contextUnref = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'pa_context_unref',
      ),
      streamNew = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<PulseSampleSpec>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<PulseSampleSpec>, Pointer<Void>)
          >('pa_stream_new'),
      streamConnect = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<PulseBufferAttributes>,
              Int32,
              Pointer<Void>,
              Pointer<Void>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<PulseBufferAttributes>,
              int,
              Pointer<Void>,
              Pointer<Void>,
            )
          >('pa_stream_connect_playback'),
      streamState = library.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_stream_get_state',
      ),
      streamWritable = library.lookupFunction<Size Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_stream_writable_size',
      ),
      streamWrite = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Void>, Int64, Int32),
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int, int)
          >('pa_stream_write'),
      streamLatency = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint64>, Pointer<Int32>),
            int Function(Pointer<Void>, Pointer<Uint64>, Pointer<Int32>)
          >('pa_stream_get_latency'),
      streamFlush = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<NativeFunction<PulseSuccessCallback>>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, Pointer<NativeFunction<PulseSuccessCallback>>, Pointer<Void>)
          >('pa_stream_flush'),
      streamDrain = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<NativeFunction<PulseSuccessCallback>>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, Pointer<NativeFunction<PulseSuccessCallback>>, Pointer<Void>)
          >('pa_stream_drain'),
      streamCork = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Int32, Pointer<Void>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>, Pointer<Void>)
          >('pa_stream_cork'),
      streamIndex = library.lookupFunction<Uint32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_stream_get_index',
      ),
      streamDisconnect = library.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_stream_disconnect',
      ),
      streamUnref = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'pa_stream_unref',
      ),
      setVolume = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Uint32, Pointer<PulseVolume>, Pointer<Void>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, int, Pointer<PulseVolume>, Pointer<Void>, Pointer<Void>)
          >('pa_context_set_sink_input_volume'),
      operationState = library.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'pa_operation_get_state',
      ),
      operationCancel = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'pa_operation_cancel',
      ),
      operationUnref = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'pa_operation_unref',
      );
}
