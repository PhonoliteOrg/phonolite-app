import 'dart:convert';

class WindowsUpdateAsset {
  static const maximumLength = 512 * 1024 * 1024;

  final Uri url;
  final int length;
  final String signature;

  const WindowsUpdateAsset({required this.url, required this.length, required this.signature});

  static WindowsUpdateAsset? tryParse({required String url, required String length, required String signature}) {
    final uri = Uri.tryParse(url);
    final size = int.tryParse(length);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        size == null ||
        size <= 0 ||
        size > maximumLength) {
      return null;
    }

    try {
      if (base64.decode(signature).length != 64) return null;
    } on FormatException {
      return null;
    }

    return WindowsUpdateAsset(url: uri, length: size, signature: signature);
  }
}
