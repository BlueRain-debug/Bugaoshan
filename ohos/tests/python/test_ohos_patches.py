"""Verify patches reject source drift and can be reapplied safely."""

import difflib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool"))
from ohos_patches import apply_dependency_patches


class OhosPatchTest(unittest.TestCase):
    def test_fixed_revision_patch_is_idempotent_and_rejects_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "pubspec.yaml").write_text("version: 1.0.0\n")
            source = package / "source.txt"
            source.write_text("original\n")
            command = ["git", "-C", str(package)]
            subprocess.run([*command, "init", "-q"], check=True)
            subprocess.run([*command, "add", "."], check=True, capture_output=True)
            subprocess.run(
                [*command, "-c", "user.name=Patch test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], check=True,
            )
            revision = subprocess.check_output([*command, "rev-parse", "HEAD"], text=True).strip()
            patches = root / "patches" / "plugins"
            patches.mkdir(parents=True)
            (patches / "fix.patch").write_text("".join(difflib.unified_diff(
                ["original\n"], ["patched\n"], fromfile="a/source.txt", tofile="b/source.txt",
            )))
            item = {"package": "fixture", "version": "1.0.0", "revision": revision, "patch": "fix.patch"}
            manifest = patches / "manifest.json"
            manifest.write_text(json.dumps([item]))
            resolve = lambda workspace, name: package
            apply_dependency_patches(root, root, resolve)
            apply_dependency_patches(root, root, resolve)
            self.assertEqual(source.read_text(), "patched\n")
            source.write_text("unrelated edit\n")
            with self.assertRaisesRegex(ValueError, "源码不匹配"):
                apply_dependency_patches(root, root, resolve)
            self.assertEqual(source.read_text(), "unrelated edit\n")
            manifest.write_text(json.dumps([dict(item, revision="0" * 40)]))
            with self.assertRaisesRegex(ValueError, "提交不匹配"):
                apply_dependency_patches(root, root, resolve)
            manifest.write_text(json.dumps([dict(item, version="2.0.0")]))
            with self.assertRaisesRegex(ValueError, "版本不匹配"):
                apply_dependency_patches(root, root, resolve)


if __name__ == "__main__":
    unittest.main()
