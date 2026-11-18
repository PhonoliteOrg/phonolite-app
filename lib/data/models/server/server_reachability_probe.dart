import 'dart:async';

typedef ServerReachabilityProbe = Future<void> Function({
  required String host,
  required int port,
  String? expectedSpki,
});
