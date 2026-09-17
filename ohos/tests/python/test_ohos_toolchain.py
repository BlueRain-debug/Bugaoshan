"""Reject incompatible OH platform kernels before preparation or incremental AOT."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool"))
import build_ohos
import ohos_native
from ohos_toolchain import validate_flutter_artifacts


class OhosToolchainTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.sdk = self.root / "Flutter OH with spaces"
        self.artifacts = {
            "engineRevision": "a" * 40,
            "harRevision": "b" * 40,
            "dartSdkRevision": "c" * 40,
            "platformSha256": {},
        }
        self.flutter_lock = {"ohosArtifacts": self.artifacts}
        self.write("bin/internal/engine.ohos.version", ("a" * 40 + "\n").encode())
        self.write("bin/internal/engine.ohos.har.version", ("b" * 40 + "\r\n").encode())
        self.write("bin/cache/dart-sdk/revision", ("c" * 40 + "\n").encode())
        # A matching upstream cache stamp must not make stale kernels acceptable.
        self.write("bin/cache/flutter_sdk.stamp", b"matching-upstream-engine")
        self.platforms = {}
        for name in ("flutter_patched_sdk", "flutter_patched_sdk_product"):
            content = (name + " with matching ABI").encode()
            self.platforms[name] = self.write(
                f"bin/cache/artifacts/engine/common/{name}/platform_strong.dill", content,
            )
            self.artifacts["platformSha256"][name] = hashlib.sha256(content).hexdigest()
        lock = self.root / "ohos/flutter/toolchain.lock.json"
        lock.parent.mkdir(parents=True)
        lock.write_text(json.dumps({"schemaVersion": 1, "flutter": self.flutter_lock}), encoding="utf-8")

    def write(self, relative, content):
        path = self.sdk / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def snapshot(self):
        return {p.relative_to(self.sdk): p.read_bytes() for p in self.sdk.rglob("*") if p.is_file()}

    def test_matching_artifacts_are_accepted_without_writing_to_sdk(self):
        before = self.snapshot()
        validate_flutter_artifacts(self.sdk, self.flutter_lock)
        self.assertEqual(self.snapshot(), before)

    def test_either_stale_kernel_is_rejected_despite_matching_revisions_and_stamp(self):
        for name, path in self.platforms.items():
            with self.subTest(platform=name):
                original = path.read_bytes()
                path.write_bytes(b"old kernel with different ABI order")
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, "平台缓存与锁定工具链不一致") as caught:
                    validate_flutter_artifacts(self.sdk, self.flutter_lock)
                self.assertIn(str(path), str(caught.exception))
                self.assertIn("precache --ohos --universal --force", str(caught.exception))
                self.assertEqual(self.snapshot(), before)
                path.write_bytes(original)

    def test_missing_cache_reports_path_instead_of_accepting_version_only(self):
        path = self.platforms["flutter_patched_sdk_product"]
        path.unlink()
        with self.assertRaisesRegex(ValueError, "无法读取") as caught:
            validate_flutter_artifacts(self.sdk, self.flutter_lock)
        self.assertIn(str(path), str(caught.exception))

    def test_oh_engine_har_and_dart_revisions_must_each_match(self):
        for relative in (
            "bin/internal/engine.ohos.version", "bin/internal/engine.ohos.har.version",
            "bin/cache/dart-sdk/revision",
        ):
            with self.subTest(path=relative):
                path = self.sdk / relative
                original = path.read_bytes()
                path.write_text("d" * 40, encoding="utf-8")
                with self.assertRaises(ValueError) as caught:
                    validate_flutter_artifacts(self.sdk, self.flutter_lock)
                self.assertIn(str(path), str(caught.exception))
                path.write_bytes(original)

    def test_incomplete_lock_cannot_silently_disable_platform_validation(self):
        with self.assertRaisesRegex(ValueError, "缺少 flutter.ohosArtifacts"):
            validate_flutter_artifacts(self.sdk, {})
        del self.artifacts["platformSha256"]["flutter_patched_sdk"]
        with self.assertRaisesRegex(ValueError, "两份 OH 平台缓存哈希"):
            validate_flutter_artifacts(self.sdk, self.flutter_lock)

    def test_cli_stops_before_dependency_resolution_on_stale_cache(self):
        self.platforms["flutter_patched_sdk_product"].write_bytes(b"stale")
        suffix = ".bat" if sys.platform == "win32" else ""
        self.write(f"bin/flutter{suffix}", b"")
        self.write(f"bin/dart{suffix}", b"")
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps({"flutterRoot": str(self.sdk)}))
        with (
            patch.object(build_ohos, "ROOT", self.root),
            patch.object(build_ohos.subprocess, "run", return_value=result),
            patch.object(build_ohos, "validate_flutter_sdk", return_value="locked"),
            patch.object(build_ohos, "build_workspace") as prepare,
            patch.object(build_ohos, "resolve_harmony_sdk") as resolve_harmony,
            self.assertRaisesRegex(ValueError, "平台缓存与锁定工具链不一致"),
        ):
            build_ohos.main(["--prepare-only", "--flutter-sdk", str(self.sdk)])
        prepare.assert_not_called()
        resolve_harmony.assert_not_called()

    def test_incremental_refresh_stops_before_workspace_changes_on_stale_cache(self):
        self.platforms["flutter_patched_sdk_product"].write_bytes(b"stale")
        with (
            patch.object(ohos_native, "load_runtime", return_value={"flutterSdk": str(self.sdk)}),
            patch.object(build_ohos, "prepare_workspace") as prepare,
            patch.object(ohos_native, "generate_code") as codegen,
            self.assertRaisesRegex(ValueError, "平台缓存与锁定工具链不一致"),
        ):
            ohos_native.refresh_native(self.root)
        prepare.assert_not_called()
        codegen.assert_not_called()

    def test_incremental_refresh_requires_preparation_for_old_diagnostic_framework(self):
        workspace = self.root / "ohos/.flutter-workspace"
        staged = workspace / "tooling/flutter-framework"
        staged.mkdir(parents=True)
        config = workspace / ".dart_tool/package_config.json"
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({"packages": [{
            "name": "flutter", "rootUri": staged.as_uri(),
        }]}), encoding="utf-8")
        with (
            patch.object(ohos_native, "load_runtime", return_value={"flutterSdk": str(self.sdk)}),
            patch.object(build_ohos, "prepare_workspace") as prepare,
            self.assertRaisesRegex(ohos_native.PreparationRequiredError, "旧诊断副本"),
        ):
            ohos_native.refresh_native(self.root)
        prepare.assert_not_called()


if __name__ == "__main__":
    unittest.main()
