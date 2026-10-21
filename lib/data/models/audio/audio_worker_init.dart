import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

class AudioWorkerInit {
  final SendPort sendPort;
  final RootIsolateToken? rootIsolateToken;

  AudioWorkerInit(this.sendPort, this.rootIsolateToken);
}
