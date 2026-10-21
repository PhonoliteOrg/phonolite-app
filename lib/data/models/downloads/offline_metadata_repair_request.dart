import 'package:flutter/foundation.dart' show immutable;

@immutable
class OfflineMetadataRepairRequest {
  final String serverBaseUrl;
  final String serverTrackId;

  const OfflineMetadataRepairRequest({required this.serverBaseUrl, required this.serverTrackId});
}
