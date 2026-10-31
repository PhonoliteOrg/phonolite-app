import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

const _runner = 'linux/runner';

void main() {
  test('Linux CMake registers each handwritten source and header exactly once', () {
    final build = readProjectFile('$_runner/CMakeLists.txt');
    final membership = readProjectFile('$_runner/sources.cmake');
    final sources = RegExp(r'set\(PHONOLITE_RUNNER_SOURCES[\s\S]*?\n\)').firstMatch(membership)![0]!;
    final references = RegExp(r'"([^"\n]+\.(?:cc|h))"')
        .allMatches(sources)
        .map((match) => match[1]!)
        .where((path) => !path.contains(r'${FLUTTER_MANAGED_DIR}'))
        .toList();
    final expected = _nativeFiles().map((file) => _relative(file)).toSet();

    expect(references.length, references.toSet().length);
    expect(references.toSet(), expected);
    expect(sources, contains(r'"${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"'));
    expectContainsAll(build, const [
      r'include("${CMAKE_CURRENT_SOURCE_DIR}/sources.cmake")',
      r'add_executable(${BINARY_NAME} ${PHONOLITE_RUNNER_SOURCES})',
    ]);
    expect(build, contains('apply_standard_settings'));

    final project = readProjectFile('linux/CMakeLists.txt');
    expectContainsAll(project, const [
      'set(BINARY_NAME "phonolite_app")',
      'set(APPLICATION_ID "com.phonoliteorg.phonolite_app")',
      'cxx_std_14',
      r'set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")',
      'include(flutter/generated_plugins.cmake)',
    ]);
  });

  test('standalone updater registers sources and keeps privileged code independent of UI', () {
    final build = readProjectFile('linux/updater/CMakeLists.txt');
    final references = RegExp(r'(?<![a-z_/])([a-z][a-z_/]*\.(?:cc|h))')
        .allMatches(build)
        .map((match) => match[1]!)
        .toList();
    final files = Directory('linux/updater')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => RegExp(r'\.(?:cc|h)$').hasMatch(file.path))
        .toList();
    expect(references.toSet(), files.map((file) => file.path.substring('linux/updater/'.length)).toSet());
    expect(references.length, references.toSet().length);
    final privileged = RegExp(r'add_executable\(phonolite-update-installer[^)]*\)').firstMatch(build)![0]!;
    expect(privileged, isNot(contains('ui/')));
    expect(build, contains('target_link_libraries(phonolite-update-installer PRIVATE phonolite_update_core)'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(file.readAsLinesSync().length, lessThanOrEqualTo(1000), reason: file.path);
      if (file.path.contains('/infrastructure/')) {
        expect(source, isNot(contains('#include "ui/')), reason: file.path);
        expect(source, isNot(contains('#include "bootstrap/')), reason: file.path);
      }
      if (file.path.contains('/data/')) {
        expect(source, isNot(matches(r'#include <(?:gtk|gio|glib|flutter_linux)/')), reason: file.path);
      }
    }
  });

  test('Linux data, shell and native capabilities keep responsibility boundaries', () {
    for (final file in _nativeFiles()) {
      final path = _relative(file);
      final source = file.readAsStringSync();

      expect(file.uri.pathSegments.last, matches(r'^[a-z][a-z0-9_]*\.(?:cc|h)$'), reason: path);
      expect(file.readAsLinesSync().length, lessThanOrEqualTo(1000), reason: path);
      expect(source, isNot(matches(r'#include\s+"(?:\.\./|[A-Za-z]:)')), reason: path);

      if (path == 'main.cc') continue;

      expect(path.split('/').first, isIn(['bootstrap', 'data', 'infrastructure', 'ui']), reason: path);

      if (path.startsWith('data/')) {
        expect(source, isNot(matches(r'#include <(?:gtk|gio|glib|flutter_linux)/')), reason: path);
        expect(source, isNot(contains('GError*')), reason: path);
      }

      if (path.startsWith('infrastructure/')) {
        expect(source, isNot(contains('runner/bootstrap/')), reason: path);
        expect(source, isNot(contains('runner/ui/')), reason: path);
      }

      if (path.startsWith('ui/')) {
        expect(source, isNot(contains('flutter_linux')), reason: path);
        expect(source, isNot(contains('g_app_info_launch')), reason: path);
        expect(source, isNot(contains('runner/bootstrap/')), reason: path);
      }
    }
  });

  test('Linux keeps native window policy and first-frame startup sequencing', () {
    final shell = readProjectFile('$_runner/ui/shell/application_window.cc');
    expectContainsAll(shell, const [
      'const gchar* title = g_get_application_name()',
      'gtk_window_set_title(window_, title)',
      'gtk_header_bar_set_title(header_bar, title)',
      'default_window_width = 1280',
      'default_window_height = 720',
      '#ifdef GDK_WINDOWING_X11',
      'GDK_IS_X11_SCREEN(screen)',
      'g_strcmp0(window_manager, "GNOME Shell") == 0',
      'gtk_header_bar_set_show_close_button(header_bar, TRUE)',
    ]);

    final host = readProjectFile('$_runner/bootstrap/flutter_host.cc');
    final startup = [
      'fl_dart_project_new()',
      'fl_dart_project_set_dart_entrypoint_arguments(',
      'fl_view_new(project)',
      'fl_view_set_background_color(',
      'gtk_widget_show(GTK_WIDGET(view_))',
      'window_.set_content(',
      'g_signal_connect(view_, "first-frame"',
      'gtk_widget_realize(',
      'fl_register_plugins(',
      'directories_.attach(',
      'gtk_widget_grab_focus(',
    ].map(host.indexOf).toList();

    expect(startup, everyElement(greaterThanOrEqualTo(0)));
    expect(startup, orderedEquals([...startup]..sort()));
    expect(host, contains('window_.show()'));

    final application = readProjectFile('$_runner/bootstrap/my_application.cc');
    expectContainsAll(application, const [
      'g_set_prgname(APPLICATION_ID)',
      'g_set_application_name("Phonolite")',
      'static_cast<GApplicationFlags>(0)',
      'g_strdupv(*arguments + 1)',
      '*exit_status = 1',
      '*exit_status = 0',
    ]);
    expect(application.indexOf('g_clear_pointer('), lessThan(application.indexOf('g_strdupv(')));
    expect(application, isNot(contains('FlMethodChannel*')));
    expect(application, isNot(contains('std::unique_ptr')));
  });

  test('each Linux window releases its handlers while the engine is still owned', () {
    final host = readProjectFile('$_runner/bootstrap/flutter_host.cc');
    expectContainsAll(host, const [
      'g_object_set_data_full(G_OBJECT(window), host_data_key, host, release)',
      'g_signal_connect(window, "destroy"',
      'g_signal_connect(view_, "destroy"',
      'g_object_ref(fl_view_get_engine(view_))',
      'g_object_set_data(G_OBJECT(window), host_data_key, nullptr)',
    ]);

    final destruction = host.substring(
      host.indexOf('FlutterHost::~FlutterHost()'),
      host.indexOf('void FlutterHost::create('),
    );
    expect(destruction.indexOf('directories_.detach()'), lessThan(destruction.indexOf('g_clear_object(&engine_)')));
    expect(
      destruction.indexOf('window_constraints_.detach()'),
      lessThan(destruction.indexOf('g_clear_object(&engine_)')),
    );
    expect(destruction, contains('g_signal_handler_disconnect'));

    final adapter = readProjectFile('$_runner/infrastructure/flutter/directories_channel_adapter.cc');
    final detach = adapter.substring(
      adapter.indexOf('void DirectoriesChannelAdapter::detach()'),
      adapter.indexOf('void DirectoriesChannelAdapter::method_call_cb('),
    );
    expectContainsAll(detach, const [
      'if (registered_)',
      'fl_binary_messenger_set_message_handler_on_channel(',
      'fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr)',
      'g_clear_object(&channel_)',
      'g_clear_object(&messenger_)',
    ]);
    expect(
      detach.indexOf('fl_binary_messenger_set_message_handler_on_channel('),
      lessThan(detach.indexOf('g_clear_object(&channel_)')),
    );
  });

  test('Linux window constraints validate Dart dimensions and keep GTK content sizing in the shell', () {
    final adapter = readProjectFile('$_runner/infrastructure/flutter/window_constraints_channel_adapter.cc');
    expectContainsAll(adapter, const [
      '"phonolite/window"',
      '"setMinimumContentSize"',
      'FL_VALUE_TYPE_MAP',
      'FL_VALUE_TYPE_FLOAT',
      'FL_VALUE_TYPE_INT',
      '!std::isfinite(dimension) || dimension <= 0 || dimension > G_MAXINT',
      'std::ceil(dimension)',
      '"invalid_size", "Positive finite window dimensions are required."',
      'fl_method_not_implemented_response_new()',
      'set_minimum_content_size_(width, height)',
      'fl_method_success_response_new(nullptr)',
      'fl_binary_messenger_set_message_handler_on_channel(',
      'fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr)',
    ]);
    expect(RegExp(r'send_method_response\(').allMatches(adapter), hasLength(1));
    expect(adapter, isNot(contains('gtk_widget_set_size_request')));

    final shell = readProjectFile('$_runner/ui/shell/application_window.cc');
    expectContainsAll(shell, const [
      'GtkWidget* content = gtk_bin_get_child(GTK_BIN(window_))',
      'gtk_widget_set_size_request(content, width, height)',
    ]);

    final host = readProjectFile('$_runner/bootstrap/flutter_host.cc');
    expectContainsAll(host, const [
      'window_.set_minimum_content_size(width, height)',
      'window_constraints_.attach(fl_engine_get_binary_messenger(engine_))',
    ]);
    expect(host.indexOf('window_.set_content('), lessThan(host.indexOf('window_constraints_.attach(')));
  });

  test('Linux directory boundary retains its absolute-path and response contracts', () {
    final adapter = readProjectFile('$_runner/infrastructure/flutter/directories_channel_adapter.cc');
    expectContainsAll(adapter, const [
      '"phonolite/directories"',
      '"openDirectory"',
      'FL_VALUE_TYPE_STRING',
      '!g_path_is_absolute(path)',
      '"invalid_path", "An absolute folder path is required."',
      'fl_method_not_implemented_response_new()',
      'fl_method_success_response_new(nullptr)',
      '"open_failed", result.message.c_str(), nullptr',
    ]);
    expect(RegExp(r'send_method_response\(').allMatches(adapter), hasLength(1));

    final launcher = readProjectFile('$_runner/infrastructure/shell/directory_launcher.cc');
    expectContainsAll(launcher, const [
      'g_filename_to_uri(absolute_path.c_str(), nullptr, &error)',
      'g_app_info_launch_default_for_uri(uri.c_str(), nullptr, &error)',
      'error != nullptr ? error->message : "Could not open the folder."',
    ]);
    expect(launcher, isNot(contains('FlValue')));
    expect(launcher, isNot(contains('system(')));
  });
}

Iterable<File> _nativeFiles() =>
    Directory(_runner)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => RegExp(r'\.(?:cc|h)$').hasMatch(file.path));

String _relative(File file) => file.path.replaceAll('\\', '/').substring('$_runner/'.length);
