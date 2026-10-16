"""Release integrity checks reject wrong sources, unsigned fallbacks and tampering."""

import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / ".github/scripts"))
import macos_dmg
import macos_signing
import release_prepare


class MacDistributionTest(unittest.TestCase):
    def test_source_and_payload_integrity(self):
        with tempfile.TemporaryDirectory() as temporary:
            dmg = Path(temporary) / macos_dmg.asset_name("v2.5.4-preview.13")
            dmg.write_bytes(b"notarized-test-fixture")
            manifest = {"schema": 1, "source_repository": macos_dmg.SOURCE_REPOSITORY,
                        "source_tag": "v2.5.4-preview.13", "source_sha": "a" * 40,
                        "version": "2.5.3", "build": "20503", "team_id": macos_dmg.TEAM_ID,
                        "asset": dmg.name, "notarization_status": "Accepted", "notarization_id": "receipt",
                        "sha256": hashlib.sha256(dmg.read_bytes()).hexdigest()}
            args = (dmg, "v2.5.4-preview.13", "a" * 40, "2.5.3", "20503")
            macos_dmg.check_manifest(manifest, *args)
            for key, wrong in [("source_sha", "b" * 40), ("source_tag", "v2.5.3"),
                               ("team_id", "OTHER"), ("build", "20504"),
                               ("notarization_status", "In Progress"), ("source_repository", "other/repo")]:
                with self.subTest(key=key), self.assertRaises(ValueError):
                    macos_dmg.check_manifest(dict(manifest, **{key: wrong}), *args)
            dmg.write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "checksum"):
                macos_dmg.check_manifest(manifest, *args)

    def test_invalid_tag_cannot_be_used_as_asset_path(self):
        for tag in ["../../file", "v1.2.3/evil", "--help", "v1.2.3\n"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                macos_dmg.asset_name(tag)

    def test_missing_signed_asset_never_falls_back_to_validation_zip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ["android-apk", "windows-release", "macos-validation-unsigned"]:
                (root / name).mkdir()
            (root / "android-apk/app-release.apk").write_bytes(b"android")
            (root / "windows-release/Bugaoshan.exe").write_bytes(b"windows")
            (root / "macos-validation-unsigned/Bugaoshan-unsigned.zip").write_bytes(b"unsigned")
            with self.assertRaises(FileNotFoundError):
                release_prepare.prepare_release_files("v2.5.3", root, macos_signed=True)
            self.assertFalse(list(root.glob("*.dmg")))

    def test_no_download_link_when_signing_is_disabled(self):
        script = ROOT / ".github/scripts/release_body.py"
        env = dict(os.environ, VERSION="v2.5.3", REPO="https://github.com/test/repo", GITHUB_OUTPUT="")
        result = subprocess.check_output([sys.executable, str(script)], env=dict(env, MACOS_SIGNED=""), text=True)
        self.assertNotIn(".dmg)", result)
        result = subprocess.check_output([sys.executable, str(script)], env=dict(env, MACOS_SIGNED="true"), text=True)
        self.assertIn("bugaoshan_2.5.3_macos_universal.dmg", result)

    def test_wait_timeout_is_a_failure_not_an_unsigned_download(self):
        args = type("Args", (), {"tag": "v2.5.3", "timeout": 0})()
        with tempfile.TemporaryDirectory() as temporary:
            args.output = Path(temporary)
            with patch.object(macos_signing, "run", return_value=subprocess.CompletedProcess([], 1, "", "404")):
                with self.assertRaises(TimeoutError):
                    macos_signing.fetch(args)

    def test_preview_version_uses_its_stable_ancestor_not_a_later_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=source, text=True).strip()
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.invalid")
            (source / ".github").mkdir()
            (source / ".github/macos-signing.json").write_text('{"schema":1}')
            (source / "pubspec.yaml").write_text("version: 2.5.3+20503\n")
            git("add", ".")
            git("commit", "-qm", "stable")
            git("tag", "v2.5.3")
            (source / "change").write_text("preview")
            git("add", ".")
            git("commit", "-qm", "preview")
            git("tag", "v2.5.4-preview.13")
            expected_sha = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/origin/preview", "HEAD")
            (source / "pubspec.yaml").write_text("version: 2.5.4+20504\n")
            git("add", ".")
            git("commit", "-qm", "later stable")
            git("tag", "v2.5.4")
            git("update-ref", "refs/remotes/origin/main", "HEAD")
            actual_run = macos_signing.run
            def missing_release(*args, **kwargs):
                if args[0] == "gh":
                    return subprocess.CompletedProcess(args, 1, "", "404")
                return actual_run(*args, **kwargs)
            with patch.object(macos_signing, "run", side_effect=missing_release):
                result = macos_signing.select(source, "v2.5.4-preview.13")
            self.assertEqual(result["sha"], expected_sha)
            self.assertEqual(result["version"], "2.5.3")
            self.assertEqual(result["build"], "20503")


if __name__ == "__main__":
    unittest.main()
