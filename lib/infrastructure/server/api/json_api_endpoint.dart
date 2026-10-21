import 'package:phonolite_app/infrastructure/server/transport/api_transport.dart';

/// The request/decode assembly shared by JSON endpoint families.
///
/// Transport owns authentication, request and wire-format policy. Endpoints
/// supply routes, payloads and data factories while preserving their public
/// feature-specific commands and connection-level orchestration.
abstract class JsonApiEndpoint {
  final ApiTransport transport;

  JsonApiEndpoint(this.transport);

  Future<T> getValue<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) async => fromJson(await transport.get(path, timeout: timeout, retryable: retryable));

  Future<List<T>> getValues<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Duration timeout = ApiTransport.defaultRequestTimeout,
    bool retryable = true,
  }) async {
    final values = await transport.getList(path, timeout: timeout, retryable: retryable);

    return values.map(fromJson).toList();
  }

  Future<T> getMetadataValue<T>(String path, T Function(Map<String, dynamic>) fromJson) async =>
      fromJson(await transport.getMetadata(path));

  Future<T> postValue<T>(String path, Map<String, dynamic> payload, T Function(Map<String, dynamic>) fromJson) async =>
      fromJson(await transport.post(path, payload));
}
