"""Foreground, unprivileged checks for signing, native fixtures and package staging."""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import shutil
from unittest import mock
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import CONFIG, ROOT, external_key, load_json, public_key, run, sha256, sign, verify, write_json
from package_app import nfpm_configuration, stage_bundle
from prepare_updates import verify_release


class SigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="phonolite-release-test-")
        cls.directory = Path(cls.temporary.name)
        cls.private = cls.directory / "test.pem"
        run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(cls.private)])
        cls.private.chmod(0o600)
        cls.public = public_key(cls.private)
        cls.verifier = Path(os.environ.get("PHONOLITE_NATIVE_TEST", ROOT / ".dart_tool/linux_updater_build/phonolite-updater-tests"))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def manifest(self):
        now = int(time.time())
        return {"schema": 1, "channel": "stable", "package_name": "phonolite", "version": "0.4.0", "revision": 2,
                "published_at": now - 60, "expires_at": now + 86400,
                "notes_url": "https://github.com/PhonoliteOrg/phonolite-app/releases/tag/v0.4.0",
                "assets": [{"target": "ubuntu-26.04-amd64", "format": "deb", "architecture": "amd64", "package_version": "0.4.0-2",
                            "url": "https://github.com/PhonoliteOrg/phonolite-app/releases/download/v0.4.0/test.deb", "length": 123, "sha256": "a" * 64}]}

    def native(self, manifest, *, envelope=None, raw=None, success=True):
        path = self.directory / "manifest.json"
        if raw is None:
            write_json(path, manifest)
        else:
            path.write_text(raw)
        signature = sign(path, self.private)
        write_json(self.directory / "manifest.sig", envelope or {"schema": 1, "signatures": [{"key_id": "test", "signature": signature}]})
        result = subprocess.run([str(self.verifier), self.public, str(path), str(self.directory / "manifest.sig")], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        if success:
            self.assertEqual(json.loads(result.stdout)["package_version"], "0.4.0-2")

    def test_exact_bytes_and_public_key_round_trip(self):
        path = self.directory / "bytes"
        path.write_bytes(b"exact manifest bytes\n")
        proof = sign(path, self.private)
        verify(path, proof, self.public)
        path.write_bytes(b"exact manifest bytes")
        with self.assertRaises(subprocess.CalledProcessError):
            verify(path, proof, self.public)

    def test_native_uses_the_same_openssl_signed_fixture(self):
        self.native(self.manifest())

    def test_native_rejects_expiry_wrong_schema_and_unsafe_assets(self):
        for field, value in [("expires_at", int(time.time()) - 1), ("schema", 2), ("revision", 0), ("channel", "preview")]:
            with self.subTest(field=field):
                manifest = self.manifest()
                manifest[field] = value
                self.native(manifest, success=False)
        for field, value in [("url", "http://example.com/test.deb"), ("architecture", "arm64"), ("length", 2147483649), ("package_version", "0.1.0-1")]:
            with self.subTest(field=field):
                manifest = self.manifest()
                manifest["assets"][0][field] = value
                self.native(manifest, success=False)

    def test_native_rejects_unknown_keys_bad_proofs_and_duplicate_fields(self):
        self.native(self.manifest(), envelope={"schema": 1, "signatures": [{"key_id": "unknown", "signature": "A" * 88}]}, success=False)
        self.native(self.manifest(), envelope={"schema": 1, "signatures": [{"key_id": "test", "signature": "A" * 88}]}, success=False)
        raw = json.dumps(self.manifest()).replace('"schema": 1', '"schema": 1, "schema": 1')
        self.native(None, raw=raw, success=False)
        manifest = self.manifest()
        manifest["assets"].append(copy.deepcopy(manifest["assets"][0]))
        self.native(manifest, success=False)

    def test_private_keys_inside_repository_are_rejected(self):
        with self.assertRaises(ValueError):
            external_key(CONFIG)

    @unittest.skipUnless(shutil.which("dpkg-deb"), "Debian artifact tools are required")
    def test_offline_release_verification_rejects_missing_changed_or_mixed_assets(self):
        with tempfile.TemporaryDirectory(prefix="phonolite-artifact-test-") as temporary:
            directory = Path(temporary)
            package_root = directory / "root"
            control = package_root / "DEBIAN/control"
            control.parent.mkdir(parents=True)
            control.write_text("Package: phonolite\nVersion: 0.4.0-2\nArchitecture: amd64\nMaintainer: Test <test@example.com>\nDescription: fixture\n")
            for name in ("opt/phonolite/phonolite_app", "opt/phonolite/lib/libapp.so", "usr/libexec/phonolite-update-installer", "usr/bin/phonolite"):
                path = package_root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture")
            name = "phonolite_0.4.0-2_ubuntu-26.04-amd64.deb"
            artifact = directory / name
            run(["dpkg-deb", "--build", "--root-owner-group", str(package_root), str(artifact)])
            config = load_json(CONFIG)
            config["trusted_keys"] = {"test": self.public}
            config["targets"][0]["validated"] = True
            configuration = directory / "configuration.json"
            write_json(configuration, config)
            metadata = {"schema": 1, "target": "ubuntu-26.04-amd64", "format": "deb", "architecture": "amd64",
                        "version": "0.4.0", "revision": 2, "package_version": "0.4.0-2", "commit": "fixture-commit",
                        "releasable": True, "configuration_sha256": sha256(configuration)}
            write_json(directory / (name + ".build.json"), metadata)
            manifest = self.manifest()
            manifest["assets"][0].update({"url": f"https://github.com/{config['repository']}/releases/download/v0.4.0/{name}",
                                          "length": artifact.stat().st_size, "sha256": sha256(artifact)})
            source = directory / config["manifest_asset"]
            write_json(source, manifest)
            write_json(directory / config["signature_asset"], {"schema": 1, "signatures": [{"key_id": "test", "signature": sign(source, self.private)}]})
            write_json(directory / "linux-release.json", {"schema": 1, "tag": "v0.4.0", "commit": "fixture-commit", "version": "0.4.0", "revision": 2, "targets": ["ubuntu-26.04-amd64"]})
            files = [artifact, directory / (name + ".build.json"), source, directory / config["signature_asset"], directory / "linux-release.json"]
            (directory / "linux-SHA256SUMS.txt").write_text("".join(f"{sha256(path)}  {path.name}\n" for path in files))
            def execute(arguments, **kwargs):
                return "{\"verified\":true}" if arguments[0] == "/fixture/coordinator" else run(arguments, **kwargs)
            with mock.patch("prepare_updates.run", side_effect=execute):
                verify_release(directory, config, Path("/fixture/coordinator"), configuration)
                metadata["commit"] = "another-source"
                write_json(directory / (name + ".build.json"), metadata)
                with self.assertRaises(ValueError):
                    verify_release(directory, config, Path("/fixture/coordinator"), configuration)
                metadata["commit"] = "fixture-commit"
                write_json(directory / (name + ".build.json"), metadata)
                with artifact.open("ab") as changed:
                    changed.write(b"changed")
                with self.assertRaises(ValueError):
                    verify_release(directory, config, Path("/fixture/coordinator"), configuration)

    def test_staging_keeps_full_bundle_and_system_identity(self):
        with tempfile.TemporaryDirectory(prefix="phonolite-stage-test-") as temporary:
            directory = Path(temporary)
            bundle, helpers, stage = directory / "bundle", directory / "helpers", directory / "stage"
            (bundle / "lib").mkdir(parents=True)
            (bundle / "data/flutter_assets/assets/images").mkdir(parents=True)
            (bundle / "lib/libapp.so").write_text("aot fixture")
            (bundle / "phonolite_app").write_text("executable fixture")
            (bundle / "phonolite_app").chmod(0o755)
            (bundle / "data/flutter_assets/assets/images/phonolite-logo-nobackground.png").write_bytes(b"png fixture")
            (bundle / "data/flutter_assets/asset.bin").write_bytes(b"complete asset")
            helpers.mkdir()
            for name in ("phonolite-update-coordinator", "phonolite-update-installer"):
                (helpers / name).write_text("helper fixture")
            config = load_json(CONFIG)
            target = config["targets"][0]
            stage_bundle(bundle, helpers, stage, config, target, "0.4.0-2")
            self.assertEqual((stage / "opt/phonolite/data/flutter_assets/asset.bin").read_bytes(), b"complete asset")
            self.assertEqual(os.readlink(stage / "usr/bin/phonolite"), "/opt/phonolite/phonolite_app")
            self.assertEqual(load_json(stage / "opt/phonolite/update-installation.json")["package_version"], "0.4.0-2")
            recipe = nfpm_configuration(stage, config, target, "0.4.0", 2)
            self.assertNotIn("scripts", recipe)
            self.assertTrue(all(item["dst"].startswith(("/opt/phonolite/", "/usr/")) for item in recipe["contents"]))


if __name__ == "__main__":
    unittest.main()
