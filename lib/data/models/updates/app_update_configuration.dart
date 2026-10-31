class AppUpdateConfiguration {
  final bool available;
  final String feedUrl;
  final String currentVersion;
  final String? disabledReason;

  const AppUpdateConfiguration({
    required this.available,
    required this.feedUrl,
    required this.currentVersion,
    this.disabledReason,
  });

  factory AppUpdateConfiguration.fromPlatform(Map<Object?, Object?> values) => AppUpdateConfiguration(
    available: values['available'] == true,
    feedUrl: values['feedUrl'] as String? ?? '',
    currentVersion: values['currentVersion'] as String? ?? '',
    disabledReason: values['reason'] as String?,
  );
}
