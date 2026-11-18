class DesktopSettings {
  final bool launchAtStartup;
  final bool runInBackground;

  const DesktopSettings({this.launchAtStartup = true, this.runInBackground = true});

  factory DesktopSettings.fromJson(Map<String, dynamic> value) => DesktopSettings(
    launchAtStartup: value['launchAtStartup'] is bool ? value['launchAtStartup'] as bool : true,
    runInBackground: value['runInBackground'] is bool ? value['runInBackground'] as bool : true,
  );

  DesktopSettings copyWith({bool? launchAtStartup, bool? runInBackground}) => DesktopSettings(
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    runInBackground: runInBackground ?? this.runInBackground,
  );

  @override
  bool operator ==(Object other) =>
      other is DesktopSettings && launchAtStartup == other.launchAtStartup && runInBackground == other.runInBackground;

  @override
  int get hashCode => Object.hash(launchAtStartup, runInBackground);

  Map<String, dynamic> toJson() => {'launchAtStartup': launchAtStartup, 'runInBackground': runInBackground};
}
