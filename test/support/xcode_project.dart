import 'dart:convert';
import 'dart:io';

/// Reads the OpenStep project structure needed to verify native target membership.
class XcodeProject {
  final Directory directory;
  final Map<String, Object?> _document;

  XcodeProject(File file)
    : directory = file.parent.parent,
      _document = _OpenStepReader(file.readAsStringSync()).read() as Map<String, Object?>;

  Map<String, Object?> get _objects => _document['objects']! as Map<String, Object?>;

  Map<String, String> get filePaths {
    final result = <String, String>{};
    final project = _object(_document['rootObject']! as String);

    void visit(String id, Directory parent) {
      final object = _object(id);
      final sourceTree = object['sourceTree'];

      if (sourceTree != null && sourceTree != '<group>' && sourceTree != 'SOURCE_ROOT') {
        return;
      }

      final base = sourceTree == 'SOURCE_ROOT' ? directory : parent;
      final path = object['path'] as String?;
      final location = path == null ? base.path : '${base.path}${Platform.pathSeparator}$path';

      if (object['isa'] == 'PBXFileReference') {
        result[id] = _path(File(location));

        return;
      }

      for (final child in object['children'] as List<Object?>? ?? const []) {
        visit(child! as String, Directory(location));
      }
    }

    visit(project['mainGroup']! as String, directory);

    return result;
  }

  List<String> sources(String targetName) {
    final target = _target(targetName);
    final paths = filePaths;
    final sources = <String>[];

    for (final phaseID in target['buildPhases']! as List<Object?>) {
      final phase = _object(phaseID! as String);

      if (phase['isa'] != 'PBXSourcesBuildPhase') {
        continue;
      }

      for (final buildID in phase['files']! as List<Object?>) {
        final reference = _object(buildID! as String)['fileRef']! as String;
        final path = paths[reference];

        if (path == null) {
          throw StateError('Unresolved source reference: $reference');
        }

        sources.add(path);
      }
    }

    return sources;
  }

  Map<String, String> shellScripts(String targetName) {
    final target = _target(targetName);
    final scripts = <String, String>{};

    for (final phaseID in target['buildPhases']! as List<Object?>) {
      final phase = _object(phaseID! as String);

      if (phase['isa'] == 'PBXShellScriptBuildPhase') {
        scripts[phase['name'] as String? ?? phaseID as String] = phase['shellScript']! as String;
      }
    }

    return scripts;
  }

  Map<String, Object?> _target(String name) {
    return _objects.values.cast<Map<String, Object?>>().singleWhere(
      (object) => object['isa'] == 'PBXNativeTarget' && object['name'] == name,
    );
  }

  Map<String, Object?> _object(String id) {
    final object = _objects[id];

    if (object is! Map<String, Object?>) {
      throw StateError('Missing Xcode object: $id');
    }

    return object;
  }

  static String _path(FileSystemEntity entity) => entity.absolute.path.replaceAll('\\', '/');
}

class _OpenStepReader {
  final List<String> _tokens;
  int _position = 0;

  _OpenStepReader(String source)
    : _tokens = RegExp(r'''/\*[\s\S]*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+''')
          .allMatches(source)
          .map((match) => match[0]!)
          .where((token) => !token.startsWith('/*') && !token.startsWith('//'))
          .toList();

  Object? read() {
    final value = _readValue();

    if (_position != _tokens.length) {
      throw const FormatException('Unexpected content after Xcode project');
    }

    return value;
  }

  Object? _readValue() {
    final token = _take();

    if (token == '{') {
      final values = <String, Object?>{};

      while (_tokens[_position] != '}') {
        final key = _string(_take());

        if (values.containsKey(key)) {
          throw FormatException('Duplicate Xcode key: $key');
        }

        _take('=');
        values[key] = _readValue();
        _take(';');
      }

      _take('}');

      return values;
    }

    if (token == '(') {
      final values = <Object?>[];

      while (_tokens[_position] != ')') {
        values.add(_readValue());

        if (_tokens[_position] == ',') {
          _take(',');
        } else if (_tokens[_position] != ')') {
          throw const FormatException('Missing Xcode array separator');
        }
      }

      _take(')');

      return values;
    }

    return _string(token);
  }

  String _take([String? expected]) {
    if (_position >= _tokens.length) {
      throw const FormatException('Incomplete Xcode project');
    }

    final token = _tokens[_position++];

    if (expected != null && token != expected) {
      throw FormatException('Expected $expected, found $token');
    }

    return token;
  }

  String _string(String token) {
    if (!token.startsWith('"')) {
      return token;
    }

    try {
      return jsonDecode(token) as String;
    } on FormatException {
      // OpenStep permits quoted shell strings beyond JSON's escape grammar.
      return token.substring(1, token.length - 1);
    }
  }
}
