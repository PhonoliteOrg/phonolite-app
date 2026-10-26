class AppUpdateConfiguration {
  final bool available;
  final String feedUrl;
  final String currentVersion;

  const AppUpdateConfiguration({required this.available, required this.feedUrl, required this.currentVersion});

  factory AppUpdateConfiguration.fromPlatform(Map<Object?, Object?> values) => AppUpdateConfiguration(
    available: values['available'] == true,
    feedUrl: values['feedUrl'] as String? ?? '',
    currentVersion: values['currentVersion'] as String? ?? '',
  );
}
