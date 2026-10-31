"""Verify and sign Linux artifacts for manual upload to one tagged GitHub release."""
from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import quote

from common import CONFIG, ROOT, external_key, load_json, public_key, run, sha256, sign, verify, version, write_json
from package_app import EXTENSIONS, target_by_id


def verify_package(path: Path, target: dict, native_version: str, fingerprint: str) -> None:
    format = target["format"]
    if format != "deb" and not re.fullmatch(r"[A-F0-9]{40,64}", fingerprint):
        raise ValueError("Configure the full uppercase native OpenPGP fingerprint before publishing RPM/Arch packages.")
    if format == "deb":
        identity = [run(["dpkg-deb", "-f", str(path), field]) for field in ("Package", "Version", "Architecture")]
        if identity != ["phonolite", native_version, "amd64"]:
            raise ValueError("Debian package identity does not match its release declaration.")
        contents = run(["dpkg-deb", "-c", str(path)])
        for required in ("./opt/phonolite/phonolite_app", "./opt/phonolite/lib/libapp.so", "./usr/libexec/phonolite-update-installer", "./usr/bin/phonolite"):
            if required not in contents:
                raise ValueError(f"Incomplete Debian package: {required}")
    elif format == "rpm":
        identity = run(["rpm", "-qp", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}", str(path)])
        if identity != f"phonolite\t{native_version}\tx86_64":
            raise ValueError("RPM identity does not match its release declaration.")
        proof = run(["rpmkeys", "--checksig", "--verbose", str(path)])
        if "Signature" not in proof or "NOKEY" in proof or "NOT OK" in proof:
            raise ValueError("A trusted native RPM signature is required.")
        if fingerprint[-16:].lower() not in proof.lower().replace(" ", ""):
            raise ValueError("RPM was not signed by the configured native signing identity.")
    else:
        # bsdtar handles Arch zstd packages on supported release hosts.
        info = run(["bsdtar", "-xOf", str(path), ".PKGINFO"])
        for expected in ("pkgname = phonolite", f"pkgver = {native_version}", "arch = x86_64"):
            if expected not in info.splitlines():
                raise ValueError("Arch identity does not match its release declaration.")
        proof = run(["gpg", "--no-autostart", "--status-fd", "1", "--verify", str(path) + ".sig", str(path)])
        signatures = [line.split()[2] for line in proof.splitlines() if line.startswith("[GNUPG:] VALIDSIG ")]
        if fingerprint not in signatures and not any(fingerprint in line.split()[2:] for line in proof.splitlines() if "VALIDSIG" in line):
            raise ValueError("Arch was not signed by the configured native signing identity.")


def verify_release(directory: Path, config: dict, native_verifier: Path, configuration: Path = CONFIG, *, checksums: bool = True) -> dict:
    manifest_path = directory / config["manifest_asset"]
    envelope = load_json(directory / config["signature_asset"])
    valid = False
    for item in envelope["signatures"]:
        public = config["trusted_keys"].get(item["key_id"])
        if public:
            try:
                verify(manifest_path, item["signature"], public)
                valid = True
            except (ValueError, subprocess.CalledProcessError):
                pass
    if not valid:
        raise ValueError("The manifest has no valid signature from a configured key.")
    run([str(native_verifier.resolve()), "--verify-manifest", str(manifest_path.resolve()), str((directory / config["signature_asset"]).resolve())])
    manifest = load_json(manifest_path)
    commits = set()
    seen = set()
    required = {config["manifest_asset"], config["signature_asset"], "linux-release.json"}
    for asset in manifest["assets"]:
        target = target_by_id(config, asset["target"])
        if not target["validated"] or target["id"] in seen or target["format"] != asset["format"] or target["architecture"] != asset["architecture"]:
            raise ValueError("Unvalidated, duplicate or mismatched release target.")
        seen.add(target["id"])
        filename = f"phonolite_{asset['package_version']}_{target['id']}{EXTENSIONS[target['format']]}"
        path = directory / filename
        required.update({filename, filename + ".build.json"})
        if target["format"] == "archlinux":
            required.add(filename + ".sig")
        if path.stat().st_size != asset["length"] or sha256(path) != asset["sha256"]:
            raise ValueError(f"Package bytes do not match the signed manifest: {filename}")
        metadata = load_json(directory / (filename + ".build.json"))
        for field in ("target", "format", "architecture", "package_version"):
            if metadata[field] != asset[field]:
                raise ValueError(f"Package build metadata mismatch: {field}")
        if metadata["version"] != manifest["version"] or metadata["revision"] != manifest["revision"]:
            raise ValueError("Build version/revision does not match the signed release.")
        if not metadata["releasable"] or metadata["configuration_sha256"] != sha256(configuration):
            raise ValueError("This package was not built with the trusted release configuration.")
        commits.add(metadata["commit"])
        verify_package(path, target, asset["package_version"], config.get("native_signing_fingerprint", ""))
    if len(commits) != 1:
        raise ValueError("Release packages must come from one source commit.")
    release = load_json(directory / "linux-release.json")
    if release["commit"] not in commits or release["version"] != manifest["version"] or release["revision"] != manifest["revision"] or set(release["targets"]) != seen:
        raise ValueError("Release metadata does not match its signed packages.")
    for asset in manifest["assets"]:
        filename = f"phonolite_{asset['package_version']}_{asset['target']}{EXTENSIONS[asset['format']]}"
        expected_url = f"https://github.com/{config['repository']}/releases/download/{quote(release['tag'], safe='')}/{filename}"
        if asset["url"] != expected_url:
            raise ValueError("A signed package URL points to a different release.")
    if any(asset["format"] != "deb" for asset in manifest["assets"]):
        required.update({"linux-native-signing-key.asc", "linux-native-signing-fingerprint.txt"})
        fingerprint = config["native_signing_fingerprint"]
        if (directory / "linux-native-signing-fingerprint.txt").read_text().strip() != fingerprint:
            raise ValueError("Published native signing fingerprint does not match configuration.")
        keys = run(["gpg", "--no-autostart", "--with-colons", "--show-keys", str(directory / "linux-native-signing-key.asc")])
        if next(line.split(":")[9] for line in keys.splitlines() if line.startswith("fpr:")) != fingerprint:
            raise ValueError("Published native public key does not match configuration.")
    packages = {path.name for path in directory.iterdir() if path.name.startswith("phonolite_") and path.name.endswith(tuple(EXTENSIONS.values()))}
    expected_packages = {name for name in required if name.endswith(tuple(EXTENSIONS.values()))}
    if packages != expected_packages:
        raise ValueError("The release directory contains missing or undeclared Linux packages.")
    if checksums:
        records = {}
        for line in (directory / "linux-SHA256SUMS.txt").read_text().splitlines():
            digest, name = line.split("  ", 1)
            if name in records or "/" in name or "\\" in name:
                raise ValueError("Invalid or duplicate checksum record.")
            records[name] = digest
        for name in required:
            if records.get(name) != sha256(directory / name):
                raise ValueError(f"Missing or incorrect release checksum: {name}")
    return manifest


def prepare(arguments: argparse.Namespace) -> None:
    config = load_json(arguments.config)
    upstream, revision = version(arguments.revision)
    native_version = f"{upstream}-{revision}"
    private = external_key(arguments.private_key)
    if config["trusted_keys"].get(arguments.key_id) != public_key(private):
        raise ValueError("The signing key does not match the configured key ID.")
    commit = run(["git", "rev-parse", "HEAD"], cwd=ROOT)
    tag = arguments.tag or f"v{upstream}"
    if run(["git", "rev-list", "-n", "1", tag], cwd=ROOT) != commit or run(["git", "status", "--porcelain"], cwd=ROOT):
        raise ValueError("Release preparation requires the clean tagged source commit.")
    directory = arguments.directory.resolve()
    assets = []
    for identifier in arguments.target:
        target = target_by_id(config, identifier)
        if not target["validated"]:
            raise ValueError(f"The target has not passed release validation: {identifier}")
        path = directory / f"phonolite_{native_version}_{identifier}{EXTENSIONS[target['format']]}"
        metadata = load_json(path.with_name(path.name + ".build.json"))
        if metadata["commit"] != commit:
            raise ValueError("Package source commit does not match the release tag.")
        verify_package(path, target, native_version, config.get("native_signing_fingerprint", ""))
        assets.append({"target": identifier, "format": target["format"], "architecture": target["architecture"],
                       "package_version": native_version,
                       "url": f"https://github.com/{config['repository']}/releases/download/{quote(tag, safe='')}/{path.name}",
                       "length": path.stat().st_size, "sha256": sha256(path)})
    if any(item["format"] != "deb" for item in assets):
        if not arguments.native_public_key:
            raise ValueError("--native-public-key is required for RPM/Arch releases.")
        fingerprint = config["native_signing_fingerprint"]
        keys = run(["gpg", "--no-autostart", "--with-colons", "--show-keys", str(arguments.native_public_key)])
        first = next(line.split(":")[9] for line in keys.splitlines() if line.startswith("fpr:"))
        if first != fingerprint:
            raise ValueError("The public native signing key does not match its pinned fingerprint.")
        shutil.copyfile(arguments.native_public_key, directory / "linux-native-signing-key.asc")
        (directory / "linux-native-signing-fingerprint.txt").write_text(fingerprint + "\n")
    now = int(dt.datetime.now(dt.timezone.utc).timestamp())
    manifest = directory / config["manifest_asset"]
    write_json(manifest, {"schema": 1, "channel": "stable", "package_name": "phonolite", "version": upstream,
                          "revision": revision, "published_at": now, "expires_at": now + arguments.valid_days * 86400,
                          "notes_url": f"https://github.com/{config['repository']}/releases/tag/{quote(tag, safe='')}", "assets": assets})
    identities = [(arguments.key_id, private)]
    for specification in arguments.additional_private_key:
        identifier, path = specification.split("=", 1)
        identities.append((identifier, external_key(Path(path))))
    if len({item[0] for item in identities}) != len(identities):
        raise ValueError("Signing identities must be unique.")
    signatures = []
    for identifier, key in identities:
        if config["trusted_keys"].get(identifier) != public_key(key):
            raise ValueError("An additional signing key does not match public configuration.")
        proof = sign(manifest, key)
        verify(manifest, proof, config["trusted_keys"][identifier])
        signatures.append({"key_id": identifier, "signature": proof})
    write_json(directory / config["signature_asset"], {"schema": 1, "signatures": signatures})
    write_json(directory / "linux-release.json", {"schema": 1, "tag": tag, "commit": commit, "version": upstream, "revision": revision, "targets": arguments.target})
    verify_release(directory, config, arguments.native_verifier, arguments.config, checksums=False)
    files = [path for path in directory.iterdir() if path.is_file() and path.name != "linux-SHA256SUMS.txt"]
    (directory / "linux-SHA256SUMS.txt").write_text("".join(f"{sha256(path)}  {path.name}\n" for path in sorted(files)))
    print(f"Verified signed Linux assets in {directory}. Upload them to the same draft release as Windows, then verify before publishing Latest.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--native-verifier", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--private-key", type=Path)
    parser.add_argument("--native-public-key", type=Path)
    parser.add_argument("--key-id")
    parser.add_argument("--additional-private-key", action="append", default=[], metavar="KEY_ID=PATH")
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--tag")
    parser.add_argument("--revision", type=int)
    parser.add_argument("--valid-days", type=int, default=90, choices=range(1, 367), metavar="DAYS")
    arguments = parser.parse_args()
    try:
        if arguments.verify_only:
            verify_release(arguments.directory, load_json(arguments.config), arguments.native_verifier, arguments.config)
            print("Signed Linux release verified.")
        else:
            if not arguments.private_key or not arguments.key_id or not arguments.target:
                parser.error("--private-key, --key-id and at least one --target are required for signing")
            prepare(arguments)
    except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Release verification failed: {error}\n{getattr(error, 'stderr', '')}\n")


if __name__ == "__main__":
    main()
