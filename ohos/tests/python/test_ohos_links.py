"""Check shared links, local generator outputs and safe link replacement/removal."""

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool"))
from ohos_links import (
    LinkedSource, STATE_FILE, assemble_linked_workspace, generated_dart,
    validate_codegen_isolation, workspace_path,
)


class OhosLinksTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.shared = self.write("lib/shared.dart", "shared\n")
        self.overlay = self.write("ohos/flutter/overrides/lib/shared.dart", "adapted\n")
        self.asset = self.write("assets/data.txt", "asset\n")
        self.generated = self.write("lib/shared.g.dart", "// GENERATED CODE\nupstream\n")

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def test_shared_sources_and_assets_are_live_and_overrides_can_be_retargeted(self):
        inputs = {"lib/shared.dart": LinkedSource(self.shared), "assets": LinkedSource(self.asset.parent, True)}
        workspace = assemble_linked_workspace(self.root, inputs)
        shared = workspace / "lib/shared.dart"
        self.assertTrue(shared.is_symlink())
        self.assertFalse(shared.parent.is_symlink())
        self.shared.write_text("updated upstream\n")
        self.asset.write_text("updated asset\n")
        self.assertEqual(shared.read_text(), "updated upstream\n")
        self.assertEqual((workspace / "assets/data.txt").read_text(), "updated asset\n")
        inputs["lib/shared.dart"] = LinkedSource(self.overlay)
        assemble_linked_workspace(self.root, inputs)
        self.assertEqual(shared.resolve(), self.overlay)
        self.assertEqual(shared.read_text(), "adapted\n")
        self.assertEqual(self.shared.read_text(), "updated upstream\n")

    def test_deleting_links_leaves_sources_assets_and_build_caches_intact(self):
        inputs = {"lib/shared.dart": LinkedSource(self.shared), "assets": LinkedSource(self.asset.parent, True)}
        workspace = assemble_linked_workspace(self.root, inputs)
        cache = workspace / ".dart_tool/build/asset_graph.json"
        cache.parent.mkdir(parents=True)
        cache.write_text("generated cache")
        assemble_linked_workspace(self.root, {})
        self.assertFalse((workspace / "lib/shared.dart").is_symlink())
        self.assertFalse((workspace / "assets").is_symlink())
        self.assertEqual(self.shared.read_text(), "shared\n")
        self.assertEqual(self.asset.read_text(), "asset\n")
        self.assertEqual(cache.read_text(), "generated cache")

    def test_generated_outputs_are_local_and_reusable(self):
        inputs = {"lib/shared.dart": LinkedSource(self.shared), "lib/shared.g.dart": self.generated}
        workspace = assemble_linked_workspace(self.root, inputs)
        output = workspace / "lib/shared.g.dart"
        self.assertFalse(output.is_symlink())
        output.write_text("// GENERATED CODE\nOH output\n")
        assemble_linked_workspace(self.root, inputs, preserve_generated={"lib/shared.g.dart"})
        validate_codegen_isolation(workspace)
        self.assertEqual(output.read_text(), "// GENERATED CODE\nOH output\n")
        self.assertEqual(self.generated.read_text(), "// GENERATED CODE\nupstream\n")

    def test_existing_generated_symlink_is_detached_before_copying(self):
        inputs = {"lib/shared.g.dart": self.generated}
        workspace = assemble_linked_workspace(self.root, inputs)
        output = workspace / "lib/shared.g.dart"
        output.unlink()
        output.symlink_to(self.generated)
        with self.assertRaisesRegex(ValueError, "独立文件"):
            validate_codegen_isolation(workspace)
        assemble_linked_workspace(self.root, inputs)
        output.write_text("OH only\n")
        self.assertFalse(output.is_symlink())
        self.assertEqual(self.generated.read_text(), "// GENERATED CODE\nupstream\n")

    def test_generated_link_and_directory_link_are_rejected_before_assembly(self):
        with self.assertRaisesRegex(ValueError, "生成代码不能链接"):
            assemble_linked_workspace(self.root, {"lib/shared.g.dart": LinkedSource(self.generated)})
        with self.assertRaisesRegex(ValueError, "只允许 assets"):
            assemble_linked_workspace(self.root, {"lib": LinkedSource(self.shared.parent, True)})
        self.assertFalse(workspace_path(self.root).exists())

    def test_generated_file_names_and_headers_are_detected(self):
        for name in ("a.g.dart", "a.freezed.dart", "injector.config.dart", "app_localizations_zh.dart"):
            self.assertTrue(generated_dart(name), name)
        arbitrary = self.write("lib/custom.dart", "// Generated code. DO NOT EDIT!\n")
        self.assertTrue(generated_dart("lib/custom.dart", arbitrary))
        self.assertFalse(generated_dart("lib/shared.dart", self.shared))

    def test_pending_link_from_interrupted_preparation_can_be_removed(self):
        workspace = assemble_linked_workspace(self.root, {"lib/shared.dart": LinkedSource(self.shared)})
        state = workspace / STATE_FILE
        state.write_text(json.dumps({"schemaVersion": 1, "files": {"lib/shared.dart": None}}))
        assemble_linked_workspace(self.root, {})
        self.assertFalse((workspace / "lib/shared.dart").is_symlink())
        self.assertTrue(self.shared.is_file())

    def test_linked_output_directory_and_external_l10n_output_are_rejected(self):
        workspace = assemble_linked_workspace(self.root, {"lib/shared.dart": LinkedSource(self.shared)})
        (workspace / ".dart_tool").symlink_to(self.root / "lib", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "生成目录不能链接"):
            validate_codegen_isolation(workspace)
        (workspace / ".dart_tool").unlink()
        (workspace / "l10n.yaml").write_text("output-dir: ../../../../lib/l10n\n")
        with self.assertRaisesRegex(ValueError, "生成路径必须位于"):
            validate_codegen_isolation(workspace)

    def test_second_native_project_is_rejected(self):
        with self.assertRaises(ValueError):
            assemble_linked_workspace(self.root, {"ohos/build-profile.json5": b"not allowed"})
        workspace = assemble_linked_workspace(self.root, {})
        (workspace / "ohos").mkdir()
        with self.assertRaisesRegex(ValueError, "不能再创建或链接原生"):
            validate_codegen_isolation(workspace)

    def test_paths_outside_workspace_and_writes_below_shared_assets_are_rejected(self):
        workspace = assemble_linked_workspace(self.root, {"assets": LinkedSource(self.asset.parent, True)})
        for relative in ("../outside.txt", "lib/../../outside.txt", "assets/data.txt"):
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                assemble_linked_workspace(self.root, {relative: b"do not write"})
        self.assertEqual(self.asset.read_text(), "asset\n")
        self.assertTrue((workspace / "assets").is_symlink())


if __name__ == "__main__":
    unittest.main()
