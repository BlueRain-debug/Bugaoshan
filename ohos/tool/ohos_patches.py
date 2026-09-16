"""Apply OH source patches to build copies and dependency patches to the OH cache."""

import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile


def source_target(workspace, relative):
    path = PurePosixPath(relative)
    is_source = path.suffix == ".dart"
    is_localization = relative in {"lib/l10n/app_en.arb", "lib/l10n/app_zh.arb"}
    if (
        not path.parts or path.parts[0] != "lib" or not (is_source or is_localization)
        or ".." in path.parts or "\\" in relative or ":" in relative
        or path.as_posix() != relative
    ):
        raise ValueError(
            f"鸿蒙源码补丁只允许修改 lib/ 下的 Dart 文件及 app_en/app_zh.arb：{relative}"
        )
    target = workspace / relative
    if not target.resolve().is_relative_to((workspace / "lib").resolve()):
        raise ValueError(f"鸿蒙源码补丁目标越界：{relative}")
    return target


def apply_source_patches(workspace, config):
    workspace = workspace.resolve()
    workspace_parent = config.resolve().parent / "build" / "workspace"
    if workspace == workspace_parent or not workspace.is_relative_to(workspace_parent):
        raise ValueError("鸿蒙源码补丁只能应用到 ohos/build/workspace/ 下的独立副本。")
    manifest_path = config / "patches" / "source" / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1 or not manifest.get("patches"):
        raise ValueError(f"鸿蒙源码补丁清单无效：{manifest_path}")

    # 独立 Git 工作目录避免 git apply 向上发现根仓库后跳过路径或修改主工程。
    # 所有补丁成功后才把涉及的文件写回构建副本，不在副本里保留 .git。
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith("GIT_")}
    with tempfile.TemporaryDirectory(prefix="patches-", dir=workspace) as directory:
        staging = Path(directory)
        git = ["git", "-C", str(staging), "-c", "core.autocrlf=false"]
        subprocess.run([*git, "init", "--quiet"], check=True, env=env)
        patches = []
        targets = set()
        for item in manifest["patches"]:
            patch = (manifest_path.parent / item["patch"]).resolve()
            if not patch.is_relative_to(manifest_path.parent.resolve()) or not patch.is_file():
                raise ValueError(f"鸿蒙源码补丁不存在或路径越界：{item['patch']}")
            stats = subprocess.check_output(
                [*git, "apply", "--numstat", "-z", str(patch)], env=env,
            ).decode("utf-8")
            if not stats:
                raise ValueError(f"鸿蒙源码补丁为空：{item['patch']}")
            for row in stats.rstrip("\0").split("\0"):
                added, removed, relative = row.split("\t", 2)
                if not added.isdigit() or not removed.isdigit():
                    raise ValueError(f"鸿蒙源码补丁不支持二进制文件：{item['patch']}")
                source_target(workspace, relative)
                targets.add(relative)
            patches.append(patch)

        for relative in sorted(targets):
            source = source_target(workspace, relative)
            target = source_target(staging, relative)
            if source.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                # 补丁使用 LF；允许 Windows 检出源文件使用 CRLF。
                target.write_bytes(source.read_bytes().replace(b"\r\n", b"\n"))
        for patch in patches:
            command = [*git, "apply", "--whitespace=nowarn"]
            check = subprocess.run(
                [*command, "--check", str(patch)], capture_output=True, text=True,
                encoding="utf-8", errors="replace", env=env,
            )
            if check.returncode != 0:
                raise ValueError(
                    f"鸿蒙源码补丁与上游不匹配：{patch.name}\n{check.stderr}"
                    "请更新 ohos/flutter/patches/source/ 中的补丁，不要修改根源码。"
                )
            subprocess.run([*command, str(patch)], check=True, env=env)
        for relative in sorted(targets):
            source = source_target(staging, relative)
            target = source_target(workspace, relative)
            if source.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            else:
                target.unlink(missing_ok=True)
        for patch in patches:
            print(f"已应用鸿蒙源码补丁：{patch.name}", flush=True)


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
