import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

import 'package:phonolite_app/data/models/updates/windows_update_asset.dart';

class WindowsUpdateVerifier {
  const WindowsUpdateVerifier();

  /// Verifies the same raw-file Ed25519 signature used by the release tooling.
  /// File reading and cryptography stay off the Flutter isolate.
  Future<void> verify(File candidate, WindowsUpdateAsset asset, String publicKey) async {
    final path = candidate.path;
    final valid = await Isolate.run(() async {
      final key = base64.decode(publicKey);
      final signature = base64.decode(asset.signature);
      if (key.length != 32 || signature.length != 64) return false;

      final file = File(path);
      if (await file.length() != asset.length) return false;
      return Ed25519().verify(
        await file.readAsBytes(),
        signature: Signature(signature, publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)),
      );
    });
    if (!valid) throw const FormatException('The downloaded update has an invalid signature.');
  }
}
