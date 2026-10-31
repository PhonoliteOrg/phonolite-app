"""Shared release metadata and signing operations for Linux distribution tools."""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("config.json")
SPKI_PREFIX = bytes.fromhex("302a300506032b6570032100")


def load_json(path: Path) -> dict:
    def unique(pairs: list[tuple]) -> dict:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON member: {key}")
            result[key] = value
        return result

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run(arguments: list[str], **kwargs) -> str:
    result = subprocess.run(arguments, check=True, text=True, capture_output=True, **kwargs)
    return result.stdout.strip()


def version(revision: int | None = None) -> tuple[str, int]:
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", (ROOT / "pubspec.yaml").read_text(), re.M)
    if match is None:
        raise ValueError("Linux releases currently require a stable major.minor.patch+build version.")
    build = int(match[2]) if revision is None else revision
    if build < 1:
        raise ValueError("The package revision must be positive.")
    return match[1], build


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def external_key(path: Path) -> Path:
    path = path.expanduser().resolve(strict=True)
    if path.is_relative_to(ROOT):
        raise ValueError("Private signing keys must be stored outside the repository.")
    if path.stat().st_mode & 0o077:
        raise ValueError("Private signing keys must have owner-only permissions (chmod 600).")
    return path


def public_key(private: Path) -> str:
    value = subprocess.check_output(["openssl", "pkey", "-in", str(private), "-pubout", "-outform", "DER"])
    if len(value) != 44 or not value.startswith(SPKI_PREFIX):
        raise ValueError("An Ed25519 signing key is required.")
    return base64.b64encode(value[len(SPKI_PREFIX):]).decode("ascii")


def sign(path: Path, private: Path) -> str:
    private = external_key(private)
    value = subprocess.check_output(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(private), "-in", str(path)])
    return base64.b64encode(value).decode("ascii")


def verify(path: Path, signature: str, public: str) -> None:
    raw_key = base64.b64decode(public, validate=True)
    raw_signature = base64.b64decode(signature, validate=True)
    if len(raw_key) != 32 or len(raw_signature) != 64:
        raise ValueError("Invalid Ed25519 key or signature length.")
    with tempfile.TemporaryDirectory(prefix="phonolite-signature-") as temporary:
        directory = Path(temporary)
        key = directory / "key.der"
        proof = directory / "signature"
        key.write_bytes(SPKI_PREFIX + raw_key)
        proof.write_bytes(raw_signature)
        run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER", "-inkey", str(key), "-sigfile", str(proof), "-in", str(path)])


def host_target() -> tuple[str, str]:
    values = {}
    for line in Path("/etc/os-release").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value.strip('"')
    return values.get("ID", ""), values.get("VERSION_ID", "rolling")
