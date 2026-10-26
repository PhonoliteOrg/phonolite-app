import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/platform/app/linux_startup_registration.dart';

void main() {
  late Directory temporary;

  setUp(() async => temporary = await Directory.systemTemp.createTemp('phonolite-autostart-'));
  tearDown(() => temporary.delete(recursive: true));

  test('XDG config takes precedence; relative XDG values fall back to HOME', () {
    final registration = LinuxStartupRegistration(
      environment: {'XDG_CONFIG_HOME': '/custom config', 'HOME': '/home/listener'},
      executable: '/opt/Phonolite/Phonolite',
    );
    expect(registration.entry.path, '/custom config/autostart/Phonolite.desktop');
    final fallback = LinuxStartupRegistration(
      environment: {'XDG_CONFIG_HOME': 'relative', 'HOME': '/home/listener'},
      executable: '/opt/Phonolite/Phonolite',
    );
    expect(fallback.entry.path, '/home/listener/.config/autostart/Phonolite.desktop');
  });

  test('registration quotes spaces, Unicode, and Exec field codes; off removes only its entry', () async {
    final registration = LinuxStartupRegistration(
      environment: {'HOME': temporary.path},
      executable: '/opt/Music é/100%/Phonolite',
    );
    await registration.setEnabled(true);
    final contents = await registration.entry.readAsString();
    expect(contents, contains('Exec="/opt/Music é/100%%/Phonolite"\n'));
    expect(contents, contains('Terminal=false\n'));
    final unrelated = File('${registration.entry.parent.path}/other.desktop');
    await unrelated.writeAsString('keep');
    await registration.setEnabled(false);
    await registration.setEnabled(false);
    expect(await registration.entry.exists(), isFalse);
    expect(await unrelated.readAsString(), 'keep');
  });

  test('paths cannot inject another desktop-entry line', () async {
    final registration = LinuxStartupRegistration(
      environment: {'HOME': temporary.path},
      executable: '/opt/Phonolite\nHidden=true',
    );
    await expectLater(registration.setEnabled(true), throwsStateError);
    expect(await registration.entry.exists(), isFalse);
  });
}
