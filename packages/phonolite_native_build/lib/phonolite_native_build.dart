import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Builds a macOS FFI library and lets Flutter bundle and sign its framework.
/// Other platforms retain their existing native plugin build integration.
Future<void> buildMacOSLibrary(List<String> arguments, {String? rustCrate}) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets || input.config.code.targetOS != OS.macOS) {
      return;
    }

    final architecture = switch (input.config.code.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      final unsupported => throw UnsupportedError('Unsupported macOS architecture: $unsupported'),
    };
    final sdk = await _run('xcrun', ['--sdk', 'macosx', '--show-sdk-path'], logOutput: false);
    final environment = {
      'SDKROOT': sdk.trim(),
      'MACOSX_DEPLOYMENT_TARGET': '${input.config.code.macOS.targetVersion}.0',
    };
    final packageRoot = input.packageRoot;
    final outputDirectory = input.outputDirectory;
    final name = input.packageName;
    final asset = outputDirectory.resolve('lib$name.dylib');

    await Directory.fromUri(outputDirectory).create(recursive: true);

    if (rustCrate == null) {
      await _buildOpus(packageRoot, outputDirectory, architecture, environment);
      await File.fromUri(outputDirectory.resolve('cmake/lib/lib$name.dylib')).copy(asset.toFilePath());
    } else {
      await _buildRust(packageRoot, outputDirectory, architecture, environment, rustCrate);
      final target = architecture == 'arm64' ? 'aarch64-apple-darwin' : 'x86_64-apple-darwin';

      await File.fromUri(outputDirectory.resolve('cargo/$target/release/lib$name.dylib')).copy(asset.toFilePath());
    }

    // Track vendored sources as well as Rust sources so edits invalidate the
    // hook cache. Build products must never become inputs to their own build.
    final sourceRoots = [
      packageRoot.resolve('macos/'),
      if (rustCrate != null) packageRoot.resolve('native/$rustCrate/'),
      packageRoot.resolve('../phonolite_opus/src/'),
      packageRoot.resolve('../phonolite_opus/cmake/'),
      packageRoot.resolve('../phonolite_opus/third_party/opus/'),
    ];

    for (final root in sourceRoots) {
      output.dependencies.addAll(_sourceFiles(Directory.fromUri(root)).map((file) => file.uri));
    }

    output.assets.code.add(
      CodeAsset(package: name, name: '$name.dart', linkMode: DynamicLoadingBundled(), file: asset),
    );
  });
}

Future<void> _buildOpus(
  Uri packageRoot,
  Uri outputDirectory,
  String architecture,
  Map<String, String> environment,
) async {
  final directory = outputDirectory.resolve('cmake/').toFilePath();

  await _run('cmake', [
    '-S',
    packageRoot.resolve('macos/').toFilePath(),
    '-B',
    directory,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_SYSTEM_NAME=Darwin',
    '-DCMAKE_SYSTEM_PROCESSOR=${architecture == 'arm64' ? 'aarch64' : 'x86_64'}',
    '-DCMAKE_OSX_ARCHITECTURES=$architecture',
    '-DCMAKE_OSX_SYSROOT=${environment['SDKROOT']}',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=${environment['MACOSX_DEPLOYMENT_TARGET']}',
    '-DPHONOLITE_OPUS_SHARED=ON',
  ], environment: environment);
  await _run('cmake', ['--build', directory, '--config', 'Release', '--parallel', '4'], environment: environment);
}

Future<void> _buildRust(
  Uri packageRoot,
  Uri outputDirectory,
  String architecture,
  Map<String, String> environment,
  String crate,
) async {
  final home = Platform.environment['CARGO_HOME'] ?? '${Platform.environment['HOME']}/.cargo';
  final cargo = File('$home/bin/cargo');
  final target = architecture == 'arm64' ? 'aarch64-apple-darwin' : 'x86_64-apple-darwin';

  await _run(cargo.existsSync() ? cargo.path : 'cargo', [
    'build',
    '--lib',
    '--locked',
    '--release',
    '--manifest-path',
    packageRoot.resolve('native/$crate/Cargo.toml').toFilePath(),
    '--target',
    target,
    '--target-dir',
    outputDirectory.resolve('cargo/').toFilePath(),
  ], environment: environment);
}

Future<String> _run(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  bool logOutput = true,
}) async {
  final result = await Process.run(executable, arguments, environment: environment);

  if (logOutput) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }

  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, '${result.stdout}\n${result.stderr}', result.exitCode);
  }

  return result.stdout as String;
}

Iterable<File> _sourceFiles(Directory directory) sync* {
  for (final entry in directory.listSync(followLinks: false)) {
    final name = entry.uri.pathSegments.where((segment) => segment.isNotEmpty).last;

    if (entry is Directory && !const {'.git', 'target', 'build', '.dart_tool'}.contains(name)) {
      yield* _sourceFiles(entry);
    } else if (entry is File && !name.endsWith('.a')) {
      yield entry;
    }
  }
}
