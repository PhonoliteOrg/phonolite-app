import 'dart:math';

/// An opaque ID carries no hardware, filesystem, or network identity.
String newListeningId() {
  final random = Random.secure();

  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
