class OpusException implements Exception {
  OpusException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() {
    if (code == null) {
      return 'OpusException: $message';
    }
    return 'OpusException($code): $message';
  }
}
