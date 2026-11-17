import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Keychain policy for credentials used by locked-screen CarPlay.
class CredentialVault {
  static const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // Cleanup must see older WhenUnlocked items as well as migrated credentials.
  static const allIOSAccessibilities = IOSOptions(accessibility: null);

  /// Whether [error] means the Android vault holds ciphertext whose Keystore key
  /// is gone, as after a restore onto another device. Such values can never be
  /// read again; Keychain and I/O failures are not reported as undecryptable.
  static bool isUndecryptable(Object error) {
    if (defaultTargetPlatform != TargetPlatform.android || error is! PlatformException) {
      return false;
    }

    final trace = '${error.details}';

    return trace.contains('javax.crypto.') || trace.contains('java.security.');
  }
}
