"""Assemble OH Dart overrides and ARB entries after checking upstream baselines."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


SOURCE_MANIFEST = "source-manifest.json"
LOCALIZATIONS = {"lib/l10n/app_en.arb", "lib/l10n/app_zh.arb"}


def source_sha256(content):
    """Ignore checkout line endings, but retain all other bytes, including BOM."""
    return hashlib.sha256(content.replace(b"\r\n", b"\n")).hexdigest()


def entry_sha256(value):
    content = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"JSON 包含重复键：{key}")
        result[key] = value
    return result


def _read_object(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=_unique_object)
    except (OSError, ValueError) as error:
        raise ValueError(f"无法读取鸿蒙源码配置：{path}\n{error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"鸿蒙源码配置必须为 JSON 对象：{path}")
    return value


def _target(root, relative):
    if not isinstance(relative, str):
        raise ValueError("鸿蒙源码路径必须是字符串")
    path = PurePosixPath(relative)
    if (
        len(path.parts) < 2 or path.parts[0] != "lib"
        or ".." in path.parts or "\\" in relative or ":" in relative
        or path.as_posix() != relative
        or not (path.suffix == ".dart" or relative in LOCALIZATIONS)
    ):
        raise ValueError(f"鸿蒙源码路径越界或类型不支持：{relative}")
    target = root / relative
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"鸿蒙源码路径越界：{relative}")
    return target


def _validate_digest(value):
    if value is not None and (
        not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None
    ):
        raise ValueError("上游基线必须是 SHA-256；新增文件或条目使用 null")


def plan_source_overrides(source_root, config):
    manifest = _read_object(config / SOURCE_MANIFEST)
    files = manifest.get("files")
    localizations = manifest.get("localizations")
    if (
        manifest.get("schemaVersion") != 1
        or not isinstance(files, list) or not isinstance(localizations, list)
    ):
        raise ValueError(f"鸿蒙源码清单无效：{config / SOURCE_MANIFEST}")

    overrides = config / "overrides"
    output = []
    seen = set()
    declared_dart = set()
    conflicts = []
    entry_count = 0

    def register(relative):
        target = _target(source_root, relative)
        if relative.casefold() in seen:
            raise ValueError(f"鸿蒙源码清单包含重复路径：{relative}")
        seen.add(relative.casefold())
        return target

    for item in files:
        if not isinstance(item, dict) or "upstreamSha256" not in item:
            raise ValueError("Dart 覆盖条目缺少上游基线")
        relative = item.get("path")
        target = register(relative)
        if target.suffix != ".dart":
            raise ValueError(f"完整文件覆盖只支持 Dart：{relative}")
        expected = item["upstreamSha256"]
        _validate_digest(expected)
        replacement = _target(overrides, relative)
        if not replacement.is_file():
            raise ValueError(f"缺少鸿蒙覆盖文件：{replacement}")
        declared_dart.add(relative)
        actual = source_sha256(target.read_bytes()) if target.is_file() else None
        if actual != expected or (expected is None and target.exists()):
            conflicts.append(f"{relative}：期望 {expected}，当前 {actual}")
        output.append((relative, replacement.read_bytes()))

    actual_dart = {
        path.relative_to(overrides).as_posix()
        for path in (overrides / "lib").rglob("*.dart")
    }
    unlisted = actual_dart - declared_dart
    if unlisted:
        raise ValueError("鸿蒙覆盖文件未登记：" + "、".join(sorted(unlisted)))

    declared_localizations = set()
    for item in localizations:
        if not isinstance(item, dict):
            raise ValueError("鸿蒙翻译清单条目无效")
        relative = item.get("path")
        target = register(relative)
        if relative not in LOCALIZATIONS:
            raise ValueError(f"不支持的鸿蒙翻译目标：{relative}")
        entries = item.get("entries")
        if not isinstance(entries, dict):
            raise ValueError(f"鸿蒙翻译条目缺少上游基线：{relative}")
        source = config / "l10n" / target.name
        if not source.resolve().is_relative_to(config.resolve()):
            raise ValueError(f"鸿蒙翻译路径越界：{source}")
        additions = _read_object(source)
        original = _read_object(target)
        if set(additions) != set(entries):
            raise ValueError(f"鸿蒙翻译条目与清单不一致：{relative}")
        for key, expected in entries.items():
            _validate_digest(expected)
            actual = entry_sha256(original[key]) if key in original else None
            if actual != expected:
                conflicts.append(f"{relative} / {key}：期望 {expected}，当前 {actual}")
        original.update(additions)
        output.append((relative, (json.dumps(original, ensure_ascii=False, indent=2) + "\n").encode("utf-8")))
        declared_localizations.add(source.name)
        entry_count += len(additions)

    unlisted_arb = {path.name for path in (config / "l10n").glob("*.arb")} - declared_localizations
    if unlisted_arb:
        raise ValueError("鸿蒙翻译文件未登记：" + "、".join(sorted(unlisted_arb)))
    if conflicts:
        raise ValueError(
            "鸿蒙源码上游基线变化，尚未覆盖任何文件：\n" + "\n".join(conflicts)
            + "\n请将上游变化合并到 ohos/flutter/overrides/ 或 l10n/，"
            "再更新 source-manifest.json 的对应基线；不要只修改哈希跳过合并。"
        )
    return output, len(files), entry_count


def check_source_overrides(source_root, config):
    """Read-only check; no SDK, dependency resolution or Git checkout required."""
    _, file_count, entry_count = plan_source_overrides(source_root.resolve(), config.resolve())
    return file_count, entry_count


def apply_source_overrides(workspace, config):
    workspace = workspace.resolve()
    config = config.resolve()
    workspace_parent = config.parent / "build" / "workspace"
    if workspace == workspace_parent or not workspace.is_relative_to(workspace_parent):
        raise ValueError("鸿蒙源码覆盖只能写入 ohos/build/workspace/ 下的独立副本")
    # Validate every target before the first write, including new-file collisions.
    output, file_count, entry_count = plan_source_overrides(workspace, config)
    for relative, content in output:
        target = _target(workspace, relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    print(f"已组装鸿蒙源码：{file_count} 个 Dart 文件、{entry_count} 个翻译条目", flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description="只读检查鸿蒙覆盖文件及上游基线，不构建或修改文件。")
    parser.add_argument("--check", action="store_true", help="检查源码覆盖及翻译清单（默认行为）")
    parser.parse_args(argv)
    root = Path(__file__).resolve().parents[2]
    try:
        files, entries = check_source_overrides(root, root / "ohos" / "flutter")
    except (OSError, ValueError) as error:
        print(f"鸿蒙源码检查失败：{error}", file=sys.stderr)
        return 1
    print(f"鸿蒙源码基线一致：{files} 个 Dart 文件、{entries} 个翻译条目")
    return 0


if __name__ == "__main__":
    sys.exit(main())
