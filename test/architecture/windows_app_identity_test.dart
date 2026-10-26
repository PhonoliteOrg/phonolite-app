import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native identity and installer share configuration and isolate debug registration', () {
    final config = jsonDecode(File('distribution_tools/windows/scripts/package_config.json').readAsStringSync()) as Map;
    expect(config['identityName'], 'PhonoliteOrg.Phonolite');
    final template = File('windows/runner/data/configuration/app_identity.h.in').readAsStringSync();
    expect(template, contains('L"@identityName@"'));
    expect(template, contains('L"@identityName@.Debug"'));
    expect(template, contains('L"@displayName@"'));
    final configure = File('windows/runner/identity.cmake').readAsStringSync();
    expect(configure, contains('distribution_tools/windows/scripts/package_config.json'));
    expect(configure, contains('CMAKE_CONFIGURE_DEPENDS'));
  });

  test('Windows identity is configured before UI and is used by system media metadata', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final identity = main.indexOf('configure_application_identity()');
    expect(identity, greaterThan(main.indexOf('::CoInitializeEx(')));
    expect(identity, lessThan(main.indexOf('flutter::DartProject project(')));
    final media = File('windows/runner/infrastructure/media/windows_media_transport.cpp').readAsStringSync();
    expect(media, contains('updater.AppMediaId(phonolite_identity::app_id)'));
    final installer = File('distribution_tools/windows/scripts/installer.nsi').readAsStringSync();
    expect(installer, contains(r'${PKEY_AppUserModel_ID}'));
    expect(installer, contains(r'SHStrDupW(w "${APP_ID}"'));
    expect(installer, contains(r'DeleteRegKey HKCU "Software\Classes\AppUserModelId\${APP_ID}"'));
  });
}
