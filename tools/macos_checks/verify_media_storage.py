#!/usr/bin/env python3
"""Compile and run foreground Apple SDK contracts without an app or engine."""

import pathlib
import subprocess


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    output = root / '.dart_tool' / 'macos_media_storage'
    output.mkdir(parents=True, exist_ok=True)
    sources = [
        'macos/NativeTests/MediaStorageContracts.swift',
        'native/apple/Data/Models/Playback/ArtworkSource.swift',
        'native/apple/Data/Models/Playback/NowPlayingState.swift',
        'native/apple/Data/Models/Playback/NowPlayingUpdate.swift',
        'native/apple/Infrastructure/Media/NowPlayingInfoPublisher.swift',
        'macos/Runner/Data/Storage/DirectoryBookmarkStore.swift',
        'macos/Runner/Infrastructure/Files/SecurityScopedDirectories.swift',
    ]
    executable = output / 'contracts'
    subprocess.run([
        'xcrun', 'swiftc', '-module-cache-path', str(output / 'module-cache'),
        '-parse-as-library', *sources, '-o', str(executable),
    ], cwd=root, check=True)
    subprocess.run([str(executable)], cwd=root, check=True)


if __name__ == '__main__':
    main()
