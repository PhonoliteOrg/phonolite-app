import 'dart:io';

class WindowsUpdateStaging {
  final Directory root;

  WindowsUpdateStaging({Directory? root}) : root = root ?? Directory('${Directory.systemTemp.path}/PhonoliteUpdates');

  Future<Directory> create() async {
    await root.create(recursive: true);
    return root.createTemp('stage-');
  }

  /// Retain recent stages because a silent installer may still be using one.
  Future<void> prune() async {
    if (!await root.exists()) return;
    final oldest = DateTime.now().subtract(const Duration(days: 1));
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory && entry.uri.pathSegments.where((part) => part.isNotEmpty).last.startsWith('stage-')) {
        if ((await entry.stat()).modified.isBefore(oldest)) await entry.delete(recursive: true);
      }
    }
  }
}
