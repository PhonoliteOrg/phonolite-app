import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/data/storage/artwork/artwork_disk_cache.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class _CountingDirectory extends Fake implements Directory {
  final Directory delegate;
  int listings = 0;
  DateTime? changedStamp;

  _CountingDirectory(this.delegate);

  @override
  String get path => delegate.path;

  @override
  Future<Directory> create({bool recursive = false}) => delegate.create(recursive: recursive);

  @override
  Future<FileStat> stat() async => _DirectoryStat(changedStamp ?? (await delegate.stat()).modified);

  @override
  Stream<FileSystemEntity> list({bool recursive = false, bool followLinks = true}) {
    listings++;
    return delegate.list(recursive: recursive, followLinks: followLinks);
  }
}

class _DirectoryStat extends Fake implements FileStat {
  @override
  final DateTime modified;

  _DirectoryStat(this.modified);
}

class _NativeIo extends IOOverrides {}

class _ObservedFile extends Fake implements File {
  final File delegate;
  final Completer<void>? readReady;
  final Completer<void>? publicationReady;
  final Completer<void>? releasePublication;
  int touches = 0;

  _ObservedFile(this.delegate, {this.readReady, this.publicationReady, this.releasePublication});

  @override
  String get path => delegate.path;
  @override
  Future<int> length() => delegate.length();
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<FileStat> stat() => delegate.stat();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => delegate.delete(recursive: recursive);
  @override
  Future<File> rename(String path) => delegate.rename(path);
  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = await delegate.readAsBytes();
    if (!(readReady?.isCompleted ?? true)) {
      readReady!.complete();
    }
    return bytes;
  }

  @override
  Future<void> setLastModified(DateTime time) async {
    touches++;
    await delegate.setLastModified(time);
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) =>
      _GatedSink(delegate.openWrite(mode: mode, encoding: encoding), publicationReady!, releasePublication!);
}

class _GatedSink extends Fake implements IOSink {
  final IOSink delegate;
  final Completer<void> ready;
  final Completer<void> release;

  _GatedSink(this.delegate, this.ready, this.release);

  @override
  void add(List<int> data) => delegate.add(data);
  @override
  Future<void> flush() async {
    ready.complete();
    await release.future;
    await delegate.flush();
  }

  @override
  Future<void> close() => delegate.close();
}

void main() {
  late Directory root;
  late _CountingDirectory directory;
  final caches = <ArtworkDiskCache>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('phonolite-artwork-accounting-');
    directory = _CountingDirectory(root);
  });

  tearDown(() async {
    for (final cache in caches) {
      await cache.close();
    }
    caches.clear();
    await root.delete(recursive: true);
  });

  ArtworkDiskCache storage({int maximumFiles = 10000, int maximumBytes = 256 * 1024 * 1024}) {
    final cache = ArtworkDiskCache(
      directory: () async => directory,
      maximumFiles: maximumFiles,
      maximumBytes: maximumBytes,
    );
    caches.add(cache);
    return cache;
  }

  test('repeated publications avoid directory scans both below and at the file quota', () async {
    final cache = storage(maximumFiles: 3);
    for (var index = 0; index < 12; index++) {
      await cache.write(_key(index), _artwork());
      expect((await _artFiles(root)).length, lessThanOrEqualTo(3));
    }
    expect(directory.listings, 1);
    expect(await cache.read(_key(11)), isNotNull);
    expect(await cache.read(_key(0)), isNull);
    expect(directory.listings, 1);
  });

  test('overwrites and removals retain accurate byte and file accounting', () async {
    final seed = storage();
    await seed.write(_key(0), _artwork());
    final length = await _file(root, 0).length();
    await seed.close();
    directory.listings = 0;

    final cache = storage(maximumFiles: 2, maximumBytes: length * 2);
    await cache.write(_key(1), _artwork());
    for (var index = 0; index < 5; index++) {
      await cache.write(_key(1), _artwork());
    }
    expect(await cache.read(_key(0)), isNotNull);
    expect(await cache.read(_key(1)), isNotNull);
    await cache.remove(_key(0));
    await cache.write(_key(2), _artwork());
    expect(await cache.read(_key(1)), isNotNull);
    expect(await cache.read(_key(2)), isNotNull);
    final files = await _artFiles(root);
    expect(files, hasLength(2));
    expect(
      (await Future.wait(files.map((file) => file.length()))).reduce((a, b) => a + b),
      lessThanOrEqualTo(length * 2),
    );
    expect(directory.listings, 1);
  });

  test('read touches retain the least-recently-used eviction order', () async {
    final seed = storage();
    await seed.write(_key(0), _artwork());
    await seed.write(_key(1), _artwork());
    await seed.close();
    await _file(root, 0).setLastModified(DateTime.utc(2010));
    await _file(root, 1).setLastModified(DateTime.utc(2020));

    final cache = storage(maximumFiles: 3);
    await cache.write(_key(2), _artwork());
    expect(await cache.read(_key(0)), isNotNull);
    await cache.write(_key(3), _artwork());
    expect(await cache.read(_key(0)), isNotNull);
    expect(await cache.read(_key(1)), isNull);
    expect(await cache.read(_key(2)), isNotNull);
    expect(await cache.read(_key(3)), isNotNull);
  });

  test('a changed directory stamp reconciles externally added and removed files', () async {
    final cache = storage(maximumFiles: 2);
    await cache.write(_key(0), _artwork());
    await cache.write(_key(1), _artwork());
    await _file(root, 0).delete();
    // A second owner creates a valid cache entry outside this instance.
    await _file(root, 3).writeAsBytes(await _file(root, 1).readAsBytes());
    directory.changedStamp = DateTime.utc(2040);
    await cache.write(_key(2), _artwork());
    expect(directory.listings, 2);
    expect((await _artFiles(root)).length, 2);
    expect(await cache.read(_key(2)), isNotNull);
  });

  test('observed missing and corrupt entries invalidate stale accounting', () async {
    final cache = storage(maximumFiles: 2);
    await cache.write(_key(0), _artwork());
    await cache.write(_key(1), _artwork());
    await _file(root, 0).delete();
    expect(await cache.read(_key(0)), isNull);
    await cache.write(_key(2), _artwork());
    expect(await cache.read(_key(1)), isNotNull);
    expect(await cache.read(_key(2)), isNotNull);

    await _file(root, 1).writeAsBytes([1, 2, 3]);
    expect(await cache.read(_key(1)), isNull);
    await cache.write(_key(3), _artwork());
    expect(await cache.read(_key(2)), isNotNull);
    expect(await cache.read(_key(3)), isNotNull);
    expect((await _artFiles(root)).length, 2);
  });

  test('concurrent owners sharing a directory retain its file quota', () async {
    final first = storage(maximumFiles: 2);
    final second = storage(maximumFiles: 2);
    await first.write(_key(0), _artwork());
    await second.write(_key(1), _artwork());
    await _file(root, 0).setLastModified(DateTime.utc(2020));
    await _file(root, 1).setLastModified(DateTime.utc(2010));
    await Future.wait([first.write(_key(2), _artwork()), second.write(_key(3), _artwork())]);
    expect((await _artFiles(root)).length, 2);
    expect(await first.read(_key(2)), isNotNull);
    expect(await second.read(_key(3)), isNotNull);
  });

  test('a second owner read updates eviction order even with an unchanged directory stamp', () async {
    final seed = storage();
    await seed.write(_key(0), _artwork());
    await seed.write(_key(1), _artwork());
    await seed.close();
    await _file(root, 0).setLastModified(DateTime.utc(2010));
    await _file(root, 1).setLastModified(DateTime.utc(2020));
    directory.changedStamp = DateTime.utc(2040);

    final first = storage(maximumFiles: 3);
    await first.write(_key(2), _artwork());
    final listings = directory.listings;
    final second = storage(maximumFiles: 3);
    expect(await second.read(_key(0)), isNotNull);
    await first.write(_key(3), _artwork());
    expect(directory.listings, listings + 1);
    expect(await first.read(_key(0)), isNotNull);
    expect(await first.read(_key(1)), isNull);
  });

  test('this owner read touches do not force a directory rescan', () async {
    final cache = storage(maximumFiles: 2);
    await cache.write(_key(0), _artwork());
    expect(await cache.read(_key(0)), isNotNull);
    await cache.write(_key(1), _artwork());
    expect(await cache.read(_key(0)), isNotNull);
    await cache.write(_key(2), _artwork());
    expect(directory.listings, 1);
  });

  test('a read touch waits for an overlapping publication before updating shared eviction order', () async {
    final seed = storage();
    await seed.write(_key(0), _artwork());
    await seed.write(_key(1), _artwork());
    await seed.close();
    await _file(root, 0).setLastModified(DateTime.utc(2010));
    await _file(root, 1).setLastModified(DateTime.utc(2020));
    directory.changedStamp = DateTime.utc(2040);
    final first = storage(maximumFiles: 3);
    final second = storage(maximumFiles: 3);
    await first.write(_key(2), _artwork());
    await _file(root, 2).setLastModified(DateTime.utc(2025));

    final publicationReady = Completer<void>();
    final release = Completer<void>();
    final readReady = Completer<void>();
    final readFile = _ObservedFile(_file(root, 1), readReady: readReady);
    final temporary = _ObservedFile(
      File('${_file(root, 3).path}.part'),
      publicationReady: publicationReady,
      releasePublication: release,
    );
    final native = _NativeIo();
    await IOOverrides.runZoned(
      () async {
        final write = first.write(_key(3), _artwork());
        late Future<StoredArtwork?> read;
        try {
          await publicationReady.future.timeout(const Duration(seconds: 2));
          read = second.read(_key(1));
          await readReady.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            readFile.touches,
            0,
            reason: 'Read metadata cannot change in the middle of another owner publication.',
          );
        } finally {
          release.complete();
        }
        await write;
        expect(await read, isNotNull);
        expect(readFile.touches, 1);
        final listings = directory.listings;
        await first.write(_key(4), _artwork());
        expect(directory.listings, listings + 1);
        expect(await first.read(_key(1)), isNotNull);
        expect(await first.read(_key(2)), isNull);
      },
      createFile: (path) =>
          path == temporary.path ? temporary : (path == readFile.path ? readFile : native.createFile(path)),
    );
  });

  test('restarting reconciles pre-existing files before enforcing the byte quota', () async {
    final seed = storage();
    await seed.write(_key(0), _artwork());
    await seed.write(_key(1), _artwork());
    final length = await _file(root, 0).length();
    await seed.close();

    final cache = storage(maximumBytes: length);
    await cache.write(_key(2), _artwork());
    expect(await cache.read(_key(2)), isNotNull);
    final files = await _artFiles(root);
    expect(files, hasLength(1));
    expect(await files.single.length(), lessThanOrEqualTo(length));
  });
}

StoredArtwork _artwork() => StoredArtwork(bytes: _png, expiresAt: DateTime.utc(2030));
String _key(int index) => index.toRadixString(16).padLeft(64, '0');
File _file(Directory root, int index) => File('${root.path}${Platform.pathSeparator}${_key(index)}.art');
Future<List<File>> _artFiles(Directory root) async =>
    root.list().where((entity) => entity is File && entity.path.endsWith('.art')).cast<File>().toList();
