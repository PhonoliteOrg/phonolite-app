part of 'package:phonolite_app/application/app/app_controller.dart';

class _LocalNetworkPermissionCoordinator {
  final AppController _host;
  LocalNetworkPermissionState _localNetworkPermissionState = LocalNetworkPermissionState.unknown;
  final _localNetworkPermissionController = StreamController<LocalNetworkPermissionState>.broadcast();

  _LocalNetworkPermissionCoordinator(this._host);

  Stream<LocalNetworkPermissionState> get localNetworkPermissionStream => _localNetworkPermissionController.stream;

  LocalNetworkPermissionState get localNetworkPermissionState => _localNetworkPermissionState;

  Future<void> refreshLocalNetworkPermission() async {
    if (!_host.localNetworkPermissionSupported) {
      return;
    }

    await _refreshLocalNetworkPermission();
  }

  void _configureLocalNetworkPermissions() {
    if (!_host._localNetworkPermissions.isSupported) {
      return;
    }

    _host._localNetworkPermissions.setStatusHandler(_handleLocalNetworkPermissionStatus);
    _refreshLocalNetworkPermission();
  }

  Future<void> _refreshLocalNetworkPermission() async {
    try {
      await _host._localNetworkPermissions.refreshPermission();
      _handleLocalNetworkPermissionStatus(await _host._localNetworkPermissions.getPermission());
    } catch (_) {}
  }

  void _handleLocalNetworkPermissionStatus(String status) {
    switch (status) {
      case 'granted':
        _setLocalNetworkPermission(LocalNetworkPermissionState.granted);
        break;
      case 'denied':
        _setLocalNetworkPermission(LocalNetworkPermissionState.denied);
        break;
      case 'unknown':
        _setLocalNetworkPermission(LocalNetworkPermissionState.unknown);
        break;
      default:
        break;
    }
  }

  void _setLocalNetworkPermission(LocalNetworkPermissionState value) {
    if (_host._disposed) {
      return;
    }

    if (_localNetworkPermissionState == value) {
      return;
    }

    _localNetworkPermissionState = value;
    _localNetworkPermissionController.add(value);
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _LocalNetworkPermissionFacade {
  _LocalNetworkPermissionCoordinator get _permissionsCoordinator;

  LocalNetworkPermissionState get _localNetworkPermissionState => _permissionsCoordinator._localNetworkPermissionState;

  StreamController<LocalNetworkPermissionState> get _localNetworkPermissionController =>
      _permissionsCoordinator._localNetworkPermissionController;

  Stream<LocalNetworkPermissionState> get localNetworkPermissionStream =>
      _permissionsCoordinator.localNetworkPermissionStream;

  LocalNetworkPermissionState get localNetworkPermissionState => _permissionsCoordinator.localNetworkPermissionState;

  Future<void> refreshLocalNetworkPermission() => _permissionsCoordinator.refreshLocalNetworkPermission();

  void _configureLocalNetworkPermissions() => _permissionsCoordinator._configureLocalNetworkPermissions();
}
