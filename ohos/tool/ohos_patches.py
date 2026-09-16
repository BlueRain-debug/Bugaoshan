"""Apply third-party OH plugin patches to the dedicated Pub cache."""

import json
import re
import subprocess


def apply_dependency_patches(workspace, config, package_root):
    manifest = config / "patches" / "plugins" / "manifest.json"
    for item in json.loads(manifest.read_text(encoding="utf-8")):
        package = package_root(workspace, item["package"])
        version = (package / "pubspec.yaml").read_text(encoding="utf-8")
        if not re.search(
            rf"^version:\s*{re.escape(item['version'])}\s*$", version, re.MULTILINE,
        ):
            raise ValueError(f"鸿蒙补丁版本不匹配：{item['package']}")
        revision = subprocess.check_output(
            ["git", "-C", str(package), "rev-parse", "HEAD"], text=True,
        ).strip()
        if revision != item["revision"]:
            raise ValueError(f"鸿蒙补丁提交不匹配：{item['package']}")
        repo = subprocess.check_output(
            ["git", "-C", str(package), "rev-parse", "--show-toplevel"], text=True,
        ).strip()
        patch = (manifest.parent / item["patch"]).resolve()
        if not patch.is_relative_to(manifest.parent.resolve()):
            raise ValueError("鸿蒙补丁路径越界")
        command = ["git", "-C", repo, "apply", "--whitespace=nowarn"]
        check = subprocess.run(
            [*command, "--check", str(patch)], capture_output=True, text=True,
        )
        if check.returncode == 0:
            subprocess.run([*command, str(patch)], check=True)
            print(f"已应用鸿蒙补丁：{item['patch']}", flush=True)
            continue
        reverse = subprocess.run(
            [*command, "--reverse", "--check", str(patch)], capture_output=True,
        )
        if reverse.returncode == 0:
            print(f"鸿蒙补丁已存在：{item['patch']}", flush=True)
            continue

        # A reused OH cache may contain the previous, explicitly recorded patch.
        # Verify that state before applying its small upgrade; do not reset Git
        # files or guess which local edits can be discarded.
        previous_name = item.get("previousPatch")
        upgrade_name = item.get("upgradePatch")
        if previous_name and upgrade_name:
            previous = (manifest.parent / previous_name).resolve()
            upgrade = (manifest.parent / upgrade_name).resolve()
            for migration_patch in (previous, upgrade):
                if (
                    not migration_patch.is_relative_to(manifest.parent.resolve())
                    or not migration_patch.is_file()
                ):
                    raise ValueError("鸿蒙补丁升级文件不存在或路径越界")
            previous_check = subprocess.run(
                [*command, "--reverse", "--check", str(previous)],
                capture_output=True,
            )
            if previous_check.returncode == 0:
                upgrade_check = subprocess.run(
                    [*command, "--check", str(upgrade)], capture_output=True,
                )
                if upgrade_check.returncode == 0:
                    subprocess.run([*command, str(upgrade)], check=True)
                    print(f"已升级鸿蒙补丁：{item['patch']}", flush=True)
                    continue
        raise ValueError(f"鸿蒙补丁与源码不匹配：{item['patch']}\n{check.stderr}")
