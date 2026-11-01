import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Keychain policy for credentials used by locked-screen CarPlay.
class CredentialVault {
  static const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // Cleanup must see older WhenUnlocked items as well as migrated credentials.
  static const allIOSAccessibilities = IOSOptions(accessibility: null);
}
