class AppUpdateConfiguration {
  final bool available;
  final String feedUrl;
  final String currentVersion;
  final String publicKey;
  final String? disabledReason;

  const AppUpdateConfiguration({
    required this.available,
    required this.feedUrl,
    required this.currentVersion,
    this.publicKey = '',
    this.disabledReason,
  });

  factory AppUpdateConfiguration.fromPlatform(Map<Object?, Object?> values) => AppUpdateConfiguration(
    available: values['available'] == true,
    feedUrl: values['feedUrl'] as String? ?? '',
    currentVersion: values['currentVersion'] as String? ?? '',
    publicKey: values['publicKey'] as String? ?? '',
    disabledReason: values['reason'] as String?,
  );
}
