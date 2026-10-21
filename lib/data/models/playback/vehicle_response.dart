import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/playback/vehicle_item.dart';

enum VehicleFailure {
  unauthorized,
  serverUnavailable,
  missingArtist,
  missingAlbum,
  missingPlaylist,
  likedEmpty,
  customEmpty,
}

sealed class VehicleResponse {
  const VehicleResponse();
}

class VehicleCommandResult extends VehicleResponse {
  final VehicleFailure? failure;

  const VehicleCommandResult.ok() : failure = null;

  const VehicleCommandResult.failure(VehicleFailure this.failure);
}

class VehicleItems extends VehicleResponse {
  final List<VehicleItem> items;

  VehicleItems(Iterable<VehicleItem> items) : items = List.unmodifiable(items);
}

class VehicleSourceState extends VehicleResponse {
  final bool serverAvailable;
  final bool localAvailable;

  const VehicleSourceState({required this.serverAvailable, required this.localAvailable});

  bool get hasAnySource => serverAvailable || localAvailable;
}

class VehicleAuthorizationState extends VehicleResponse {
  final bool authorized;
  final bool hasSession;
  final SessionStatus status;

  const VehicleAuthorizationState({required this.authorized, required this.hasSession, required this.status});
}

class VehicleLibraryStatus extends VehicleResponse {
  final bool likedAvailable;
  final VehicleFailure? failure;

  const VehicleLibraryStatus({required this.likedAvailable, this.failure});
}
