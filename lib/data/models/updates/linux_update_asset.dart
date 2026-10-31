class LinuxUpdateAsset {
  final String version;
  final String packageVersion;
  final String target;
  final String format;
  final String architecture;
  final Uri url;
  final String sha256;
  final int length;

  const LinuxUpdateAsset({
    required this.version,
    required this.packageVersion,
    required this.target,
    required this.format,
    required this.architecture,
    required this.url,
    required this.sha256,
    required this.length,
  });

  factory LinuxUpdateAsset.fromVerifiedJson(Map<String, dynamic> value) {
    final url = Uri.parse(value['url'] as String);
    final length = value['length'] as int;
    final digest = value['sha256'] as String;
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        length < 1 ||
        length > 2147483648 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid verified Linux asset.');
    }
    return LinuxUpdateAsset(
      version: value['version'] as String,
      packageVersion: value['package_version'] as String,
      target: value['target'] as String,
      format: value['format'] as String,
      architecture: value['architecture'] as String,
      url: url,
      sha256: digest,
      length: length,
    );
  }
}
