import 'dart:io';

import 'package:file_selector/file_selector.dart';

Future<XFile?> openPlaylistImageFileFallback() async {
  if (!Platform.isWindows) {
    return null;
  }

  final result = await Process.run('powershell.exe', const <String>[
    '-NoLogo',
    '-NoProfile',
    '-STA',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Choose playlist image'
$dialog.Filter = 'Image files (*.jpg;*.jpeg;*.png;*.webp)|*.jpg;*.jpeg;*.png;*.webp'
$dialog.Multiselect = $false
$result = $dialog.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.FileName
}
''',
  ]);

  if (result.exitCode != 0) {
    throw StateError('Windows image picker failed: ${result.stderr}');
  }
  final path = result.stdout.toString().trim();
  if (path.isEmpty) {
    return null;
  }
  return XFile(path);
}
