/// Log files use this capability while the application is starting and during folder moves.
abstract interface class LogDirectoryPreferences {
  bool get usesManagedLogDirectory;
  Future<String?> loadLogDirectory();
  Future<void> saveLogDirectory(String? directory);
}
