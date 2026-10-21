class AudioSourceRejected implements Exception {
  final String message;

  const AudioSourceRejected(this.message);

  @override
  String toString() => message;
}
