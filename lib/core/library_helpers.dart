import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../entities/app_controller.dart';

Map<String, String> authHeaders(AppController controller) {
  final token = controller.connection.token;
  if (token == null || token.isEmpty) {
    return const {};
  }
  return {'Authorization': 'Bearer $token'};
}

Future<void> precacheImages(
  BuildContext context,
  Iterable<String> urls, {
  Map<String, String> headers = const {},
}) async {
  if (!shouldPrecacheImages()) {
    return;
  }
  for (final url in urls) {
    try {
      await precacheImage(NetworkImage(url, headers: headers), context);
    } catch (_) {}
  }
}

bool shouldPrecacheImages() {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform != TargetPlatform.windows;
}
