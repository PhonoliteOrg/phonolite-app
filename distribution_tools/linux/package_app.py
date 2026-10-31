"""Stage a complete release bundle and build one native Linux package (no installation)."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from common import CONFIG, ROOT, external_key, host_target, load_json, run, sha256, version, write_json
from install_desktop_entry import ICON_PATH, desktop_icon_svg

EXTENSIONS = {"deb": ".deb", "rpm": ".rpm", "archlinux": ".pkg.tar.zst"}
HELPERS = ("phonolite-update-coordinator", "phonolite-update-installer")


def target_by_id(config: dict, identifier: str) -> dict:
    return next(item for item in config["targets"] if item["id"] == identifier)


def inspect_elf(path: Path) -> dict:
    header = run(["readelf", "-h", str(path)])
    if "Advanced Micro Devices X86-64" not in header or "ELF64" not in header:
        raise ValueError(f"Unexpected ELF architecture: {path}")
    return {"path": str(path), "dynamic": run(["readelf", "-d", str(path)])}


def stage_bundle(bundle: Path, helpers: Path, stage: Path, config: dict, target: dict, native_version: str) -> list[dict]:
    if not (bundle / "lib/libapp.so").is_file():
        raise ValueError("A release bundle with its AOT library is required; debug bundles cannot be packaged.")
    if not (bundle / "phonolite_app").is_file() or not (bundle / ICON_PATH).is_file():
        raise ValueError("The complete Flutter Linux bundle is required.")
    app = stage / "opt/phonolite"
    shutil.copytree(bundle, app, symlinks=False)
    write_json(app / "update-installation.json", {
        "schema": 1, "package_name": "phonolite", "target": target["id"], "format": target["format"],
        "architecture": target["architecture"], "package_version": native_version, "ownership": "github",
    })
    for name in HELPERS:
        destination = stage / "usr/libexec" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(helpers / name, destination)
        destination.chmod(0o755)
    launcher = stage / "usr/bin/phonolite"
    launcher.parent.mkdir(parents=True)
    launcher.symlink_to("/opt/phonolite/phonolite_app")
    application_id = config["application_id"]
    icon = stage / "usr/share/icons/hicolor/scalable/apps" / f"{application_id}.svg"
    icon.parent.mkdir(parents=True)
    icon.write_text(desktop_icon_svg(bundle / ICON_PATH))
    desktop = stage / "usr/share/applications" / f"{application_id}.desktop"
    desktop.parent.mkdir(parents=True)
    desktop.write_text(
        "[Desktop Entry]\nType=Application\nName=Phonolite\nExec=/usr/bin/phonolite\n"
        f"Icon={application_id}\nStartupWMClass={application_id}\n"
        "Terminal=false\nStartupNotify=false\nCategories=AudioVideo;Audio;Player;\n"
    )
    policy = stage / "usr/share/polkit-1/actions/com.phonoliteorg.phonolite.update.policy"
    policy.parent.mkdir(parents=True)
    policy.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Phonolite</vendor>
  <action id="com.phonoliteorg.phonolite.update">
    <description>Install a verified Phonolite update</description>
    <message>Authentication is required to install a verified Phonolite update</message>
    <defaults><allow_any>no</allow_any><allow_inactive>no</allow_inactive><allow_active>auth_admin</allow_active></defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/phonolite-update-installer</annotate>
  </action>
</policyconfig>
''')
    dependencies = []
    for path in sorted(stage.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as source:
            is_elf = source.read(4) == b"\x7fELF"
        if is_elf:
            entry = inspect_elf(path)
            if path.parent == stage / "usr/libexec" and any(tag in entry["dynamic"] for tag in ("(RPATH)", "(RUNPATH)")):
                raise ValueError("Installed updater helpers must not retain build-directory runtime library paths.")
            entry["path"] = "/" + str(path.relative_to(stage))
            dependencies.append(entry)
        path.chmod(0o755 if os.access(path, os.X_OK) else 0o644)
    return dependencies


def nfpm_configuration(stage: Path, config: dict, target: dict, upstream: str, revision: int) -> dict:
    contents = []
    for path in sorted(stage.rglob("*")):
        destination = "/" + str(path.relative_to(stage))
        if path.is_symlink():
            contents.append({"src": os.readlink(path), "dst": destination, "type": "symlink"})
        elif path.is_file():
            contents.append({"src": str(path), "dst": destination, "file_info": {
                "mode": path.stat().st_mode & 0o777, "owner": "root", "group": "root",
            }})
    return {
        "name": config["package_name"], "arch": target["architecture"], "platform": "linux",
        "version": upstream, "release": str(revision), "maintainer": "PhonoliteOrg <noreply@github.com>",
        "description": "Phonolite music player", "homepage": "https://github.com/" + config["repository"],
        "license": "AGPL-3.0-or-later", "section": "sound", "priority": "optional",
        "depends": target["dependencies"], "contents": contents,
        "rpm": {"group": "Applications/Multimedia", "compression": "xz"},
        "archlinux": {"pkgbase": "phonolite"},
    }


def build(arguments: argparse.Namespace) -> Path:
    config = load_json(arguments.config)
    target = target_by_id(config, arguments.target)
    upstream, revision = version(arguments.revision)
    native_version = f"{upstream}-{revision}"
    baseline_matches = host_target() == (target["os_id"], target["os_version"])
    dirty = bool(run(["git", "status", "--porcelain"], cwd=ROOT))
    if not arguments.development and (dirty or not baseline_matches or not target["validated"]):
        raise ValueError("Release packaging requires a clean checkout, matching build baseline and validated target. Use --development only for non-publishable inspection artifacts.")
    if f"{config['nfpm']['version']}" not in run([str(arguments.nfpm.resolve()), "--version"]):
        raise ValueError("The nFPM version does not match the pinned public configuration.")
    if not arguments.development:
        provenance = load_json(arguments.bundle / "data/build-source.json")
        if provenance["dirty"] or provenance["commit"] != run(["git", "rev-parse", "HEAD"], cwd=ROOT) or provenance["version"] != upstream:
            raise ValueError("Rebuild the release bundle from this clean source commit before packaging.")
        if (arguments.bundle / "data/application-id").read_text().strip() != config["application_id"]:
            raise ValueError("Release packaging requires the production application identity.")
    arguments.output.mkdir(parents=True, exist_ok=True)
    output = arguments.output.resolve()
    with tempfile.TemporaryDirectory(prefix="phonolite-package-") as temporary:
        workspace = Path(temporary)
        helper_build = workspace / "helpers"
        run(["cmake", "-S", str(ROOT / "linux/updater"), "-B", str(helper_build),
             "-DCMAKE_BUILD_TYPE=Release", f"-DPHONOLITE_UPDATE_CONFIGURATION={arguments.config.resolve()}",
             *arguments.cmake_argument])
        run(["cmake", "--build", str(helper_build), "--parallel", "4"])
        run(["ctest", "--test-dir", str(helper_build), "--output-on-failure"])
        stage = workspace / "stage"
        dependencies = stage_bundle(arguments.bundle.resolve(), helper_build, stage, config, target, native_version)
        recipe = workspace / "nfpm.json"
        definition = nfpm_configuration(stage, config, target, upstream, revision)
        if arguments.rpm_signing_key:
            definition["rpm"]["signature"] = {"key_file": str(external_key(arguments.rpm_signing_key)), "key_id": config["native_signing_fingerprint"][-16:]}
        write_json(recipe, definition)
        artifact = output / f"phonolite_{native_version}_{target['id']}{EXTENSIONS[target['format']]}"
        if artifact.exists():
            raise ValueError(f"Refusing to overwrite an existing package: {artifact}")
        run([str(arguments.nfpm.resolve()), "package", "--config", str(recipe), "--packager", target["format"], "--target", str(artifact)])
        write_json(artifact.with_name(artifact.name + ".build.json"), {
            "schema": 1, "version": upstream, "revision": revision, "package_version": native_version,
            "target": target["id"], "format": target["format"], "architecture": target["architecture"],
            "commit": run(["git", "rev-parse", "HEAD"], cwd=ROOT), "configuration_sha256": sha256(arguments.config),
            "releasable": not arguments.development and not dirty and baseline_matches and target["validated"],
            "elf_dependencies": dependencies,
        })
        return artifact


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--nfpm", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "build/linux/packages")
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--revision", type=int)
    parser.add_argument("--development", action="store_true")
    parser.add_argument("--rpm-signing-key", type=Path, help="External exported OpenPGP secret key for nFPM RPM signing.")
    parser.add_argument("--cmake-argument", action="append", default=[])
    arguments = parser.parse_args()
    try:
        print(build(arguments))
    except (OSError, ValueError, StopIteration, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Could not package Phonolite: {error}\n{getattr(error, 'stderr', '')}\n")


if __name__ == "__main__":
    main()
