#!/usr/bin/env python3
"""Check iOS native exports and plugin metadata after archiving or IPA export.

Usage: python3 ios/Scripts/verify_release_artifact.py <.ipa|.xcarchive|.app>
Requires macOS, Xcode command-line tools, and the matching checkout after pub get.
This inspects binaries without loading or launching the application.
"""

import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse
import zipfile


PROJECT = Path(__file__).resolve().parents[2]
NATIVE_GROUPS = (
    (
        "Apple audio output",
        "ios/Runner/Infrastructure/Audio/Native/phonolite_audio.h",
        "lib/infrastructure/platform/audio/apple/core_audio_bindings.dart",
        "Runner",
    ),
    (
        "Opus decoder",
        "packages/phonolite_opus/src/phonolite_opus.h",
        "packages/phonolite_opus/lib/phonolite_opus.dart",
        "Runner",
    ),
    (
        "QUIC and authentication",
        "packages/phonolite_quic/src/phonolite_quic.h",
        "packages/phonolite_quic/lib/phonolite_quic.dart",
        "Frameworks/phonolite_quic.framework/phonolite_quic",
    ),
    (
        "Offline audio decoder",
        "packages/phonolite_local_audio/src/phonolite_local_audio.h",
        "packages/phonolite_local_audio/lib/phonolite_local_audio.dart",
        "Frameworks/phonolite_local_audio.framework/phonolite_local_audio",
    ),
)
# package:sqlite3 guards this lookup with ENABLE_COLUMN_METADATA detection.
OPTIONAL_SQLITE_EXPORTS = {"sqlite3_column_table_name"}


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


@contextmanager
def application_bundle(artifact):
    if not artifact.exists():
        raise ValueError(f"Artifact does not exist: {artifact}")
    if artifact.suffix == ".ipa":
        with tempfile.TemporaryDirectory(prefix="phonolite-ipa-audit-") as folder:
            with zipfile.ZipFile(artifact) as archive:
                for entry in archive.infolist():
                    path = Path(entry.filename)
                    if path.is_absolute() or ".." in path.parts:
                        raise ValueError(f"Unsafe IPA entry: {entry.filename}")
                archive.extractall(folder)
            yield one_app(Path(folder) / "Payload")
    elif artifact.suffix == ".xcarchive":
        yield one_app(artifact / "Products/Applications")
    elif artifact.suffix == ".app" and artifact.is_dir():
        yield artifact
    else:
        raise ValueError("Expected an .ipa, .xcarchive, or .app")


def one_app(directory):
    apps = list(directory.glob("*.app"))
    if len(apps) != 1:
        raise ValueError(f"Expected one application in {directory}, found {len(apps)}")
    return apps[0]


def sqlite_package():
    config = PROJECT / ".dart_tool/package_config.json"
    if not config.is_file():
        raise ValueError("Run flutter pub get to resolve the matching SQLite bindings")
    for package in json.loads(config.read_text())["packages"]:
        if package["name"] == "sqlite3":
            uri = urlparse(urljoin(config.as_uri(), package["rootUri"]))
            if uri.scheme != "file":
                raise ValueError("SQLite bindings must be available locally")
            return Path(unquote(uri.path))
    raise ValueError("sqlite3 is missing from package_config.json")


def verify(app):
    failures = []
    export_cache = {}
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = app / info["CFBundleExecutable"]

    def exports(binary):
        if binary not in export_cache:
            output = run("xcrun", "dyld_info", "-exports", str(binary))
            export_cache[binary] = set(re.findall(r"\s_(\S+)", output))
        return export_cache[binary]

    def require(label, required, available):
        if not required:
            raise ValueError(f"No requirements discovered for {label}")
        missing = sorted(required - available)
        print(f"{'FAIL' if missing else 'PASS'} {label}: "
              f"{len(required) - len(missing)}/{len(required)}")
        if missing:
            failures.append(f"{label}: missing {', '.join(missing)}")

    for label, header_path, bindings_path, binary_path in NATIVE_GROUPS:
        header = (PROJECT / header_path).read_text()
        bindings = (PROJECT / bindings_path).read_text()
        required = set(re.findall(r"\b(phonolite_\w+)\s*\(", header))
        required.update(re.findall(r"['\"](phonolite_\w+)['\"]", bindings))
        binary = executable if binary_path == "Runner" else app / binary_path
        require(label, required, exports(binary))

    sqlite_source = sqlite_package() / "lib/src/ffi/generated/dynamic_library.dart"
    sqlite_symbols = set(re.findall(r"'((?:sqlite3)\w+)'", sqlite_source.read_text()))
    sqlite_binary = next(
        (app / path for path in ("Frameworks/CSQLite.framework/CSQLite",
                                "Frameworks/sqlite3.framework/sqlite3")
         if (app / path).is_file()),
        None,
    )
    if sqlite_binary is None:
        raise ValueError("The bundled SQLite framework is missing")
    sqlite_exports = exports(sqlite_binary)
    require("SQLite FFI", sqlite_symbols - OPTIONAL_SQLITE_EXPORTS, sqlite_exports)
    for symbol in sorted((sqlite_symbols & OPTIONAL_SQLITE_EXPORTS) - sqlite_exports):
        print(f"INFO Optional SQLite column metadata is unavailable: {symbol}")

    binaries = [executable]
    for framework in sorted((app / "Frameworks").glob("*.framework")):
        framework_info = plistlib.loads((framework / "Info.plist").read_bytes())
        binaries.append(framework / framework_info["CFBundleExecutable"])

    classes = set()
    registration_methods = set()
    missing_frameworks = set()
    incompatible_frameworks = set()
    app_architectures = set(run("xcrun", "lipo", "-archs", str(executable)).split())
    for binary in binaries:
        metadata = run("xcrun", "dyld_info", "-objc", str(binary))
        classes.update(re.findall(r"@interface\s+(\S+)\s*:", metadata))
        registration_methods.update(re.findall(
            r"0x[0-9a-fA-F]+\s+\+\[(\S+) registerWithRegistrar:\]", metadata,
        ))
        architectures = set(run("xcrun", "lipo", "-archs", str(binary)).split())
        if not app_architectures <= architectures:
            incompatible_frameworks.add(str(binary.relative_to(app)))
        for line in run("otool", "-L", str(binary)).splitlines()[1:]:
            dependency = line.strip().split(" (compatibility")[0]
            if dependency.startswith("@rpath/") and ".framework/" in dependency:
                if not (app / "Frameworks" / dependency.removeprefix("@rpath/")).is_file():
                    missing_frameworks.add(dependency)

    registrant = (PROJECT / "ios/Runner/GeneratedPluginRegistrant.m").read_text()
    plugins = set(re.findall(r"\[(\w+) registerWithRegistrar:", registrant))
    present_plugins = {
        plugin for plugin in plugins
        if plugin in classes or any(
            name.startswith("_TtC") and name.endswith(f"{len(plugin)}{plugin}")
            for name in classes
        )
    }
    require("Flutter plugin runtime classes", plugins, present_plugins)
    registered_plugins = {
        plugin for plugin in plugins
        if plugin in registration_methods or any(
            name.startswith("_TtC") and name.endswith(f"{len(plugin)}{plugin}")
            for name in registration_methods
        )
    }
    require("Flutter plugin registration methods", plugins, registered_plugins)

    scenes = info.get("UIApplicationSceneManifest", {}).get("UISceneConfigurations", {})
    expected_scenes = set()
    present_scenes = set()
    for configurations in scenes.values():
        for configuration in configurations:
            name = configuration.get("UISceneDelegateClassName")
            if name:
                expected_scenes.add(name)
                module, _, class_name = name.rpartition(".")
                mangled = f"_TtC{len(module)}{module}{len(class_name)}{class_name}"
                if name in classes or mangled in classes:
                    present_scenes.add(name)
    if expected_scenes:
        require("UIKit and CarPlay scene classes", expected_scenes, present_scenes)

    print(f"{'FAIL' if missing_frameworks else 'PASS'} Bundled framework dependencies")
    if missing_frameworks:
        failures.append("Missing framework dependencies: " + ", ".join(sorted(missing_frameworks)))
    print(f"{'FAIL' if incompatible_frameworks else 'PASS'} Framework architectures")
    if incompatible_frameworks:
        failures.append("Incompatible framework architectures: " +
                        ", ".join(sorted(incompatible_frameworks)))
    for failure in failures:
        print(f"ERROR {failure}", file=sys.stderr)
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()
    try:
        with application_bundle(args.artifact.resolve()) as app:
            return verify(app)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile,
            subprocess.CalledProcessError) as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
