#!/usr/bin/env python3
"""Inspect a built Mac app without launching it or loading its libraries."""

import argparse
import pathlib
import plistlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[2]
MACHO_MAGIC = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}


def tool(*arguments):
    return subprocess.check_output(['xcrun', *map(str, arguments)], text=True)


def version(value):
    parts = tuple(int(part) for part in value.split('.'))
    return parts + (0,) * (3 - len(parts))


def require_exports(binary, symbols, architectures):
    if not binary.is_file():
        raise RuntimeError(f'Missing native binary: {binary}')
    if not symbols:
        raise RuntimeError(f'No public symbols were found for {binary}')
    for architecture in architectures:
        exports = tool('dyld_info', '-arch', architecture, '-exports', binary)
        present = set(re.findall(r'\b_(phonolite_\w+)\b', exports))
        missing = symbols - present
        if missing:
            raise RuntimeError(f'{binary} ({architecture}) is missing exports: {sorted(missing)}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    parser.add_argument('--architectures', nargs='+', default=['x86_64', 'arm64'])
    args = parser.parse_args()
    contents = args.app.resolve() / 'Contents'
    with (contents / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    if info['CFBundleIdentifier'] != 'com.adamuremek.phonolite':
        raise RuntimeError('The Mac bundle ID must match the shared Apple App Store identity')
    if info.get('LSApplicationCategoryType') != 'public.app-category.music':
        raise RuntimeError('The Mac App Store Music category is missing')
    minimum = version(info['LSMinimumSystemVersion'])
    if not (contents / 'Resources/PrivacyInfo.xcprivacy').is_file():
        raise RuntimeError('The app privacy manifest is missing from Resources')

    inspected = set()
    for candidate in contents.rglob('*'):
        if not candidate.is_file():
            continue
        binary = candidate.resolve()
        if binary in inspected:
            continue
        with binary.open('rb') as source:
            if source.read(4) not in MACHO_MAGIC:
                continue
        inspected.add(binary)
        actual = set(tool('lipo', '-archs', binary).split())
        if not set(args.architectures).issubset(actual):
            raise RuntimeError(f'{candidate} has {actual}, expected {args.architectures}')
        for architecture in args.architectures:
            settings = tool('vtool', '-arch', architecture, '-show-build', binary)
            for target in re.findall(r'\bminos\s+([\d.]+)', settings):
                if version(target) > minimum:
                    raise RuntimeError(f'{candidate} requires macOS {target}, above the app minimum')

    main_binary = contents / 'MacOS' / info['CFBundleExecutable']
    bindings = (ROOT / 'lib/infrastructure/platform/audio/apple/core_audio_bindings.dart').read_text()
    audio_symbols = set(re.findall(r"'(phonolite_audio_\w+)'", bindings))
    require_exports(main_binary, audio_symbols, args.architectures)
    export_count = len(audio_symbols)
    for package in ['phonolite_opus', 'phonolite_local_audio', 'phonolite_quic']:
        header = (ROOT / 'packages' / package / 'src' / f'{package}.h').read_text()
        symbols = set(re.findall(r'\b(phonolite_\w+)\s*\(', header))
        binary = contents / 'Frameworks' / f'{package}.framework' / package
        require_exports(binary, symbols, args.architectures)
        export_count += len(symbols)

    print(f'Checked {len(inspected)} Mach-O binaries and {export_count} FFI exports for {args.architectures}.')


if __name__ == '__main__':
    main()
