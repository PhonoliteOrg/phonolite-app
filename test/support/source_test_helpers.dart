import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String projectPath(String relativePath) {
  final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
  return '${Directory.current.path}${Platform.pathSeparator}$normalized';
}

String readProjectFile(String relativePath) {
  final file = File(projectPath(relativePath));
  if (!file.existsSync()) {
    throw StateError('Expected source file to exist: $relativePath');
  }
  return file.readAsStringSync();
}

String readProjectFiles(Iterable<String> relativePaths) => relativePaths.map(readProjectModule).join('\n');

void expectContainsAll(String source, Iterable<String> snippets) {
  final missing = snippets.where((snippet) => !_sourceContains(source, snippet)).toList();
  expect(missing, isEmpty, reason: 'Missing source contracts: $missing');
}

/// Reads a responsibility module, including its private Dart parts.
/// Ordinary UI/API files have explicit ownership roots so unrelated imports
/// cannot make a contract pass accidentally.
String readProjectModule(String relativePath) {
  final visited = <String>{};
  final sources = <String>[];
  void read(String path) {
    if (!visited.add(path)) return;
    final source = readProjectFile(path);
    sources.add(source);
    if (!path.endsWith('.dart')) return;
    final directives = RegExp(r"(?:part|export) '([^']+)';");
    for (final match in directives.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:phonolite_app/')) {
        read('lib/${uri.substring('package:phonolite_app/'.length)}');
      } else if (!uri.contains(':')) {
        final parent = path.substring(0, path.lastIndexOf('/') + 1);
        read('$parent$uri');
      }
    }
    // Extensible presentation structures supply part of the owning module's
    // rendering contract; follow only these explicit shared template imports.
    final structures = RegExp(
      r"import '(package:phonolite_app/ui/(?:structures/[^']+|shell/(?:base_(?:form_)?page\.dart|page_scroll_view\.dart|toolbars/[^']+|navigation/[^']+)))';",
    );
    for (final match in structures.allMatches(source)) {
      read('lib/${match[1]!.substring('package:phonolite_app/'.length)}');
    }
    // These collaborators own extracted implementation, rather than unrelated
    // feature behavior. Follow their contracts where a consumer delegates work.
    const sharedOwners = {
      'application/controllers/feature_controller.dart',
      'application/controllers/shared/controller_selection.dart',
      'application/workflows/request_generation.dart',
      'application/workflows/debounced_action.dart',
      'data/storage/preferences/json_settings_file.dart',
      'data/structures/serialization/json_values.dart',
      'data/rules/library/track_identity.dart',
      'ui/shared/music/albums/album_collection_sliver.dart',
      'ui/shared/music/artists/artist_collection_sliver.dart',
      'ui/shared/music/media_selection.dart',
      'ui/shared/music/collection_view_toggle_button.dart',
      'ui/shared/music/selectable_media_row.dart',
      'ui/shared/music/selectable_media_card.dart',
      'ui/shared/music/media_hero_frame.dart',
      'ui/shared/music/media_hero_details.dart',
      'ui/shared/music/artwork/artwork_image.dart',
      'ui/shared/music/artwork/artwork_placeholder.dart',
      'ui/shared/design_system/controls/obsidian_list_row.dart',
      'ui/shared/design_system/controls/obsidian_choice_row.dart',
      'ui/shared/design_system/interaction/pointer_interaction.dart',
      'ui/shared/design_system/surfaces/chamfer_geometry.dart',
      'ui/shared/design_system/modals/obsidian_modal_list_row.dart',
      'ui/shared/design_system/modals/obsidian_editor_dialog.dart',
    };
    final imports = RegExp(r"import 'package:phonolite_app/([^']+)';");
    for (final match in imports.allMatches(source)) {
      if (sharedOwners.contains(match[1])) read('lib/${match[1]}');
    }
  }

  void directory(String path) {
    final files =
        Directory(
            projectPath(path),
          ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final relative = file.path.substring(Directory.current.path.length + 1).replaceAll(Platform.pathSeparator, '/');
      read(relative);
    }
  }

  read(relativePath);
  switch (relativePath) {
    case 'lib/application/downloads/offline_download_manager.dart':
      read('lib/infrastructure/downloads/client/offline_download_client.dart');
      read('lib/data/configuration/downloads/offline_storage_config.dart');
      read('lib/data/models/downloads/offline_actor_protocol.dart');
      read('lib/data/models/downloads/download_worker_protocol.dart');
      read('lib/data/models/downloads/download_outcomes.dart');
      read('lib/data/files/download_integrity.dart');
      read('lib/data/rules/downloads/offline_snapshot_comparison.dart');
      read('lib/infrastructure/downloads/http/download_range.dart');
    case 'lib/infrastructure/server/server_connection.dart':
      directory('lib/infrastructure/server/api');
      directory('lib/infrastructure/server/transport');
    case 'lib/infrastructure/audio/engine/audio_engine.dart':
      directory('lib/infrastructure/audio/output');
      directory('lib/infrastructure/audio/protocol');
      read('lib/data/models/audio/audio_worker_init.dart');
      read('lib/data/models/audio/audio_source_rejected.dart');
      directory('lib/infrastructure/platform/audio');
    case 'lib/data/storage/offline/library/offline_library.dart':
      read('lib/data/models/downloads/offline_deletion_draft.dart');
    case 'lib/ui/features/playback/widgets/now_playing_bar.dart':
      directory('lib/ui/features/playback/widgets');
    case 'lib/pages/settings/settings_page.dart':
      directory('lib/ui/features/settings/sections');
      directory('lib/ui/features/settings/widgets');
      directory('lib/ui/features/settings/dialogs');
    case 'lib/pages/favorites/liked_page.dart':
      read('lib/ui/features/favorites/widgets/liked_section.dart');
    case 'lib/pages/library/library_page.dart':
      read('lib/ui/features/library/widgets/library_section_slivers.dart');
    case 'lib/ui/features/listening_stats/widgets/stats_cards.dart':
      directory('lib/ui/features/listening_stats/widgets');
    case 'lib/pages/playlists/playlists_page.dart':
      read('lib/ui/features/playlists/widgets/playlist_section.dart');
    case 'lib/pages/playlists/playlist_detail_view.dart':
      read('lib/ui/features/playlists/widgets/empty_playlist_text.dart');
    case 'lib/pages/home/home_page.dart':
      read('lib/ui/navigation/tab_route_observer.dart');
  }
  return sources.join('\n');
}

// Ignore code formatting while preserving whitespace inside quoted labels.
// Compilation verifies syntax; these checks verify the requested source tokens.
bool _sourceContains(String source, String snippet) {
  final tokens = RegExp(
    r'''r?(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")|\w+|[^\s]''',
  ).allMatches(snippet).map((match) => match[0]!).toList();
  if (tokens.isNotEmpty && tokens.last == ',') tokens.removeLast();
  final pattern = <String>[];
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    final closesGroup = token == ')' || token == ']' || token == '}';
    if (closesGroup && index > 0 && tokens[index - 1] != ',') {
      pattern.add(r'(?:,\s*)?');
    }
    final trailingComma =
        token == ',' && index + 1 < tokens.length && const [')', ']', '}'].contains(tokens[index + 1]);
    pattern.add(trailingComma ? ',?' : RegExp.escape(token));
  }
  return RegExp(pattern.join(r'\s*')).hasMatch(source);
}
