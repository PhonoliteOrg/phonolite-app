/// The acknowledged result of revoking account sessions.
class SessionRevocationResult {
  final int revoked;

  const SessionRevocationResult({required this.revoked});

  factory SessionRevocationResult.fromJson(Map<String, dynamic> json) {
    final revoked = json['revoked'];

    if (revoked is! int || revoked < 0) {
      throw const FormatException('Invalid session revocation result.');
    }

    return SessionRevocationResult(revoked: revoked);
  }
}
