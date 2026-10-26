import 'package:xml/xml.dart';

class AppUpdateRelease {
  static const _sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

  final String version;

  const AppUpdateRelease({required this.version});

  String get displayVersion =>
      version.endsWith('.0') && version.split('.').length == 4 ? version.substring(0, version.length - 2) : version;

  static AppUpdateRelease? latestFromAppcast(String source, {required String currentVersion}) {
    final current = _versionParts(currentVersion);
    if (current == null) {
      throw const FormatException('The running app has an invalid update version.');
    }

    final document = XmlDocument.parse(source);
    final channel = document.rootElement.getElement('channel');
    if (document.rootElement.name.local != 'rss' || channel == null) {
      throw const FormatException('The update feed is not an RSS appcast.');
    }

    AppUpdateRelease? latest;
    var newest = current;
    for (final item in channel.findElements('item')) {
      for (final enclosure in item.findElements('enclosure')) {
        final os = enclosure.getAttribute('os', namespace: _sparkleNamespace);
        if (os != null && os != 'windows' && os != 'windows-x64') {
          continue;
        }
        final version =
            (item.getElement('version', namespace: _sparkleNamespace)?.innerText ??
                    enclosure.getAttribute('version', namespace: _sparkleNamespace))
                ?.trim();
        final parts = version == null ? null : _versionParts(version);
        final download = Uri.tryParse(enclosure.getAttribute('url') ?? '');
        if (parts == null || download?.scheme != 'https' || download!.host.isEmpty || download.userInfo.isNotEmpty) {
          continue;
        }
        if (_compare(parts, newest) > 0) {
          latest = AppUpdateRelease(version: version!);
          newest = parts;
        }
      }
    }
    return latest;
  }

  static List<int>? _versionParts(String value) {
    if (!RegExp(r'^\d+(?:\.\d+){0,3}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.any((part) => part == null || part > 65535)) {
      return null;
    }
    return [...parts.cast<int>(), ...List.filled(4 - parts.length, 0)];
  }

  static int _compare(List<int> left, List<int> right) {
    for (var index = 0; index < 4; index++) {
      final comparison = left[index].compareTo(right[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }
}
