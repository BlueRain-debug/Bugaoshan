"""Exercise source assembly, upstream drift and localization merge boundaries."""

import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool"))
from ohos_sources import apply_source_overrides, check_source_overrides, entry_sha256, source_sha256


class OhosSourcesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "ohos/flutter"
        self.workspace = self.root / "ohos/build/workspace/run-fixture"
        self.write("lib/main.dart", "original\n")
        self.write("lib/shared.dart", "shared\n")
        self.write("lib/l10n/app_en.arb", json.dumps({"title": "Original", "shared": "Shared"}))
        self.write("ohos/flutter/overrides/lib/main.dart", "adapted\n")
        self.write("ohos/flutter/overrides/lib/utils/ohos.dart", "OH helper\n")
        self.write("ohos/flutter/l10n/app_en.arb", json.dumps({"title": "OH title", "ohos": "OH only"}))
        self.manifest = {
            "schemaVersion": 1,
            "files": [
                {"path": "lib/main.dart", "upstreamSha256": source_sha256(b"original\n")},
                {"path": "lib/utils/ohos.dart", "upstreamSha256": None},
            ],
            "localizations": [{
                "path": "lib/l10n/app_en.arb",
                "entries": {"title": entry_sha256("Original"), "ohos": None},
            }],
        }
        self.save_manifest()

    def write(self, relative, content):
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8", newline="\n")

    def save_manifest(self):
        self.write("ohos/flutter/source-manifest.json", json.dumps(self.manifest))

    def copy_shared(self):
        shutil.copytree(self.root / "lib", self.workspace / "lib")

    def test_assembly_preserves_shared_files_root_and_unrelated_translation_changes(self):
        self.write("lib/l10n/app_en.arb", json.dumps({
            "title": "Original", "shared": "Upstream update", "newUpstream": "New",
        }))
        self.assertEqual(check_source_overrides(self.root, self.config), (2, 2))
        self.assertFalse(self.workspace.exists())
        self.copy_shared()
        apply_source_overrides(self.workspace, self.config)
        self.assertEqual((self.workspace / "lib/main.dart").read_text(), "adapted\n")
        self.assertEqual((self.workspace / "lib/utils/ohos.dart").read_text(), "OH helper\n")
        self.assertEqual((self.workspace / "lib/shared.dart").read_text(), "shared\n")
        self.assertEqual(json.loads((self.workspace / "lib/l10n/app_en.arb").read_text()), {
            "title": "OH title", "shared": "Upstream update", "newUpstream": "New", "ohos": "OH only",
        })
        self.assertEqual((self.root / "lib/main.dart").read_text(), "original\n")
        self.assertFalse((self.root / "lib/utils/ohos.dart").exists())

    def test_changed_upstream_source_is_rejected_before_any_overlay_write(self):
        self.write("lib/main.dart", "upstream changed\n")
        self.copy_shared()
        with self.assertRaisesRegex(ValueError, "上游基线变化"):
            apply_source_overrides(self.workspace, self.config)
        self.assertEqual((self.workspace / "lib/main.dart").read_text(), "upstream changed\n")
        self.assertFalse((self.workspace / "lib/utils/ohos.dart").exists())

    def test_localization_collision_cannot_partially_overwrite_dart_files(self):
        self.write("lib/l10n/app_en.arb", json.dumps({"title": "Original", "ohos": "Upstream owns key"}))
        self.copy_shared()
        with self.assertRaisesRegex(ValueError, "app_en.arb / ohos"):
            apply_source_overrides(self.workspace, self.config)
        self.assertEqual((self.workspace / "lib/main.dart").read_text(), "original\n")

    def test_missing_upstream_file_and_new_file_collision_are_reported(self):
        (self.root / "lib/main.dart").unlink()
        self.write("lib/utils/ohos.dart", "new upstream file\n")
        with self.assertRaises(ValueError) as error:
            check_source_overrides(self.root, self.config)
        self.assertIn("lib/main.dart", str(error.exception))
        self.assertIn("lib/utils/ohos.dart", str(error.exception))

    def test_checkout_line_endings_do_not_change_source_baseline(self):
        (self.root / "lib/main.dart").write_bytes(b"original\r\n")
        self.assertEqual(check_source_overrides(self.root, self.config), (2, 2))

    def test_root_and_paths_outside_the_source_tree_cannot_be_overwritten(self):
        with self.assertRaisesRegex(ValueError, "独立副本"):
            apply_source_overrides(self.root, self.config)
        self.manifest["files"][0]["path"] = "lib/../pubspec.yaml"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "路径越界"):
            check_source_overrides(self.root, self.config)

    def test_unlisted_override_and_translation_entries_are_rejected(self):
        self.write("ohos/flutter/overrides/lib/forgotten.dart", "unlisted\n")
        with self.assertRaisesRegex(ValueError, "未登记"):
            check_source_overrides(self.root, self.config)
        (self.config / "overrides/lib/forgotten.dart").unlink()
        self.write("ohos/flutter/l10n/app_en.arb", json.dumps({"title": "OH title", "forgotten": "New"}))
        with self.assertRaisesRegex(ValueError, "条目与清单不一致"):
            check_source_overrides(self.root, self.config)

    def test_duplicate_json_keys_are_rejected(self):
        self.write("ohos/flutter/l10n/app_en.arb", '{"title":"one","title":"two"}')
        with self.assertRaisesRegex(ValueError, "重复键"):
            check_source_overrides(self.root, self.config)


if __name__ == "__main__":
    unittest.main()
