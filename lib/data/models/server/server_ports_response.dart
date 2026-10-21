class ServerPortsResponse {
  final int? httpPort;
  final int? quicPort;
  final bool quicEnabled;

  ServerPortsResponse({required this.httpPort, required this.quicPort, required this.quicEnabled});

  factory ServerPortsResponse.fromJson(Map<String, dynamic> json) {
    return ServerPortsResponse(
      httpPort: (json['http_port'] as num?)?.toInt(),
      quicPort: (json['quic_port'] as num?)?.toInt(),
      quicEnabled: json['quic_enabled'] == true,
    );
  }
}
