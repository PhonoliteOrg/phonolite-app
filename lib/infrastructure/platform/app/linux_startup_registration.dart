import 'dart:io';

/// XDG autostart registration, with executable paths quoted as desktop-entry
/// arguments rather than shell commands. No processes are launched here.
class LinuxStartupRegistration {
  final Map<String, String> environment;
  final String executable;

  LinuxStartupRegistration({Map<String, String>? environment, String? executable})
    : environment = environment ?? Platform.environment,
      executable = executable ?? Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;

  File get entry {
    final configured = environment['XDG_CONFIG_HOME'];
    final home = environment['HOME'];
    final String root;

    if (configured != null && configured.startsWith('/')) {
      root = configured;
    } else if (home != null && home.isNotEmpty) {
      root = '$home/.config';
    } else {
      throw StateError('The user configuration directory is unavailable.');
    }

    return File('$root/autostart/Phonolite.desktop');
  }

  Future<void> setEnabled(bool enabled) async {
    final file = entry;

    if (!enabled) {
      if (await file.exists()) {
        await file.delete();
      }

      return;
    }

    if (executable.contains('\n') || executable.contains('\r')) {
      throw StateError('The application path cannot contain a newline.');
    }

    // Desktop Exec quoting is parsed twice: escape reserved characters for its
    // argument parser, then escape backslashes for the desktop-entry string.
    final argument = executable
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('`', '\\`')
        .replaceAll(r'$', r'\$')
        .replaceAll('%', '%%')
        .replaceAll('\\', '\\\\');
    final contents =
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Phonolite\n'
        'Exec="$argument"\n'
        'Terminal=false\n'
        'StartupNotify=false\n';

    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  }
}
