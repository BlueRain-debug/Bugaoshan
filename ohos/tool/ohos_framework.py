"""Stage pinned Flutter framework sources for HarmonyOS-only patches."""

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile


def _read_json(path, description):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as error:
        raise ValueError(f"无法读取{description} {path}：{error}") from error


def _safe_relative_path(value):
    if not isinstance(value, str):
        raise ValueError("Flutter framework 补丁清单包含无效路径。")
    relative = PurePosixPath(value)
    if relative.is_absolute() or ".." in relative.parts or "\\" in value or ":" in value:
        raise ValueError(f"Flutter framework 补丁清单路径越界：{value!r}")
    return relative


def _run_git(git, directory, *args):
    env = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith("GIT_")
    }
    result = subprocess.run(
        # The locked Windows SDK checkout uses CRLF; let Git normalize LF patch context.
        [git, "-C", str(directory), "-c", "core.autocrlf=true", *args],
        env=env, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if result.returncode:
        raise ValueError(f"Flutter framework 补丁失败：{result.stderr.strip()}")
    return result.stdout


def stage_flutter_framework(workspace, sdk, native):
    """Copy, patch, and select the locked Flutter package for the OH workspace."""
    workspace = workspace.resolve()
    sdk = sdk.resolve()
    native = native.resolve()
    if workspace != native / ".flutter-workspace":
        raise ValueError("Flutter framework 副本必须位于原生工程的 .flutter-workspace 内。")

    config = native / "flutter/patches/framework"
    manifest = _read_json(config / "manifest.json", "Flutter framework 补丁清单")
    toolchain = _read_json(native / "flutter/toolchain.lock.json", "Flutter 工具链锁")
    if manifest.get("schemaVersion") != 1:
        raise ValueError("不支持的 Flutter framework 补丁清单格式。")
    try:
        locked_revision = toolchain["flutter"]["frameworkRevision"]
    except (KeyError, TypeError) as error:
        raise ValueError("Flutter 工具链锁缺少 frameworkRevision。") from error
    if manifest.get("frameworkRevision") != locked_revision:
        raise ValueError("Flutter framework 补丁与锁定的 SDK 提交不匹配。")

    source = (sdk / "packages/flutter").resolve()
    if not source.is_dir():
        raise ValueError(f"Flutter SDK 缺少 framework package：{source}")
    source_items = manifest.get("sources")
    if not isinstance(source_items, list) or not source_items:
        raise ValueError("Flutter framework 补丁清单缺少源文件。")
    locked_sources = set()
    for item in source_items:
        if not isinstance(item, dict):
            raise ValueError("Flutter framework 补丁清单包含无效源文件条目。")
        relative = _safe_relative_path(item.get("path"))
        if relative.as_posix() in locked_sources:
            raise ValueError(f"Flutter framework 补丁清单包含重复路径：{relative}")
        locked_sources.add(relative.as_posix())
        path = source.joinpath(*relative.parts)
        if not path.is_file():
            raise ValueError(f"Flutter framework 源文件不存在：{relative}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != item.get("sha256"):
            raise ValueError(f"Flutter framework 源码与补丁基线不一致：{relative}")

    patch_name = manifest.get("patch")
    patch_relative = _safe_relative_path(patch_name)
    patch = config.joinpath(*patch_relative.parts).resolve()
    if not patch.is_relative_to(config.resolve()) or not patch.is_file():
        raise ValueError(f"Flutter framework 补丁不存在：{patch_name!r}")
    git = shutil.which("git")
    if git is None:
        raise ValueError("PATH 中找不到 git，无法应用 Flutter framework 补丁。")

    tooling = workspace / "tooling"
    tooling.mkdir(parents=True, exist_ok=True)
    destination = (tooling / "flutter-framework").resolve()
    if destination.parent != tooling.resolve():
        raise ValueError("Flutter framework 输出目录越界。")
    with tempfile.TemporaryDirectory(prefix="flutter-framework-", dir=tooling) as directory:
        staged = Path(directory) / "flutter"
        shutil.copytree(source, staged)
        _run_git(git, staged, "init", "--quiet")
        stats = _run_git(git, staged, "apply", "--numstat", "-z", str(patch))
        patch_targets = set()
        for row in stats.rstrip("\0").split("\0"):
            added, removed, relative = row.split("\t", 2)
            if not added.isdigit() or not removed.isdigit():
                raise ValueError(f"Flutter framework 补丁包含非文本文件：{relative}")
            patch_targets.add(relative)
        if patch_targets != locked_sources:
            raise ValueError("Flutter framework 补丁与锁定的源文件清单不一致。")
        _run_git(
            git, staged, "apply", "--check",
            "--whitespace=nowarn", str(patch),
        )
        _run_git(
            git, staged, "apply", "--whitespace=nowarn", str(patch),
        )
        _run_git(
            git, staged, "apply", "--reverse", "--check",
            "--whitespace=nowarn", str(patch),
        )
        git_metadata = (staged / ".git").resolve()
        if git_metadata.parent != staged.resolve() or not git_metadata.is_dir():
            raise ValueError("Flutter framework 临时 Git 目录无效。")
        shutil.rmtree(git_metadata)
        if destination.is_symlink():
            raise ValueError(f"Flutter framework 输出目录不能是符号链接：{destination}")
        if destination.exists():
            if not destination.is_dir():
                raise ValueError(f"Flutter framework 输出目录无效：{destination}")
            shutil.rmtree(destination)
        staged.replace(destination)

    package_config_path = workspace / ".dart_tool/package_config.json"
    package_config = _read_json(package_config_path, "Dart package_config")
    packages = package_config.get("packages")
    if not isinstance(packages, list):
        raise ValueError(f"Dart package_config 缺少 packages 数组：{package_config_path}")
    flutter_package = next(
        (item for item in packages if isinstance(item, dict) and item.get("name") == "flutter"),
        None,
    )
    if flutter_package is None:
        raise ValueError("Dart package_config 缺少 flutter package。")
    flutter_package["rootUri"] = destination.as_uri()
    package_config_path.write_text(
        json.dumps(package_config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("已校验并应用鸿蒙 Flutter framework 补丁。", flush=True)
    return destination
