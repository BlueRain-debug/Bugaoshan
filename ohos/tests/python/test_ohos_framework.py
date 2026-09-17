"""Verify the HarmonyOS Flutter framework patch is isolated and pinned."""

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "tool" / "ohos_framework.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("ohos_framework", SCRIPT)
ohos_framework = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ohos_framework)


class OhosFrameworkTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.native = self.root / "ohos"
        self.workspace = self.native / ".flutter-workspace"
        self.sdk = self.root / "sdk"
        self.source = self.sdk / "packages/flutter/lib/src/services/platform_channel.dart"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("before\n", encoding="utf-8")
        package_config = self.workspace / ".dart_tool/package_config.json"
        package_config.parent.mkdir(parents=True)
        package_config.write_text(
            json.dumps({
                "configVersion": 2,
                "packages": [{
                    "name": "flutter",
                    "rootUri": (self.sdk / "packages/flutter").as_uri(),
                    "packageUri": "lib/",
                }],
            }),
            encoding="utf-8",
        )
        config = self.native / "flutter/patches/framework"
        config.mkdir(parents=True)
        (self.native / "flutter/toolchain.lock.json").write_text(
            json.dumps({"flutter": {"frameworkRevision": "locked"}}),
            encoding="utf-8",
        )
        (config / "manifest.json").write_text(
            json.dumps({
                "schemaVersion": 1,
                "frameworkRevision": "locked",
                "patch": "fix.patch",
                "sources": [{
                    "path": "lib/src/services/platform_channel.dart",
                    "sha256": hashlib.sha256(b"before\n").hexdigest(),
                }],
            }),
            encoding="utf-8",
        )
        (config / "fix.patch").write_text(
            "diff --git a/lib/src/services/platform_channel.dart "
            "b/lib/src/services/platform_channel.dart\n"
            "--- a/lib/src/services/platform_channel.dart\n"
            "+++ b/lib/src/services/platform_channel.dart\n"
            "@@ -1 +1 @@\n"
            "-before\n"
            "+after\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_stages_patched_copy_and_rewrites_only_workspace_config(self):
        destination = ohos_framework.stage_flutter_framework(
            self.workspace, self.sdk, self.native,
        )

        self.assertEqual(self.source.read_text(encoding="utf-8"), "before\n")
        self.assertEqual(
            (destination / "lib/src/services/platform_channel.dart").read_text(
                encoding="utf-8",
            ),
            "after\n",
        )
        config = json.loads(
            (self.workspace / ".dart_tool/package_config.json").read_text(
                encoding="utf-8",
            )
        )
        self.assertEqual(config["packages"][0]["rootUri"], destination.as_uri())

    def test_rejects_framework_source_drift(self):
        self.source.write_text("changed\n", encoding="utf-8")

        with self.assertRaisesRegex(ValueError, "源码与补丁基线不一致"):
            ohos_framework.stage_flutter_framework(
                self.workspace, self.sdk, self.native,
            )


if __name__ == "__main__":
    unittest.main()
