#!/usr/bin/env python3
"""Generate the complete root/OH Dart lockfile comparison."""

import argparse
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "ohos" / "docs" / "dependencies" / "lock-inventory.md"


def read_lock(path):
    packages = {}
    sdks = {}
    current = None
    in_packages = False
    in_sdks = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "packages:":
            in_packages = True
            continue
        if line == "sdks:":
            in_packages = False
            in_sdks = True
            continue
        if in_sdks:
            match = re.fullmatch(r"  ([A-Za-z0-9_]+): \"?([^\"]+)\"?", line)
            if match:
                sdks[match.group(1)] = match.group(2)
            continue
        if not in_packages:
            continue
        match = re.fullmatch(r"  ([A-Za-z0-9_]+):", line)
        if match:
            current = match.group(1)
            packages[current] = {
                "dependency": "",
                "source": "",
                "version": "",
                "resolved-ref": "",
            }
            continue
        if current is None:
            continue
        for field in ("dependency", "source", "version", "resolved-ref"):
            match = re.fullmatch(rf"    {field}: \"?([^\"\s]+(?: [^\"]+)?)\"?", line)
            if match:
                packages[current][field] = match.group(1).strip('"')
                break
            match = re.fullmatch(rf"      {field}: \"?([^\"\s]+(?: [^\"]+)?)\"?", line)
            if match:
                packages[current][field] = match.group(1).strip('"')
                break
    return packages, sdks


def cell(package):
    if package is None:
        return "-"
    source = package["source"]
    if package["resolved-ref"]:
        source += f" @ `{package['resolved-ref']}`"
    return f"`{package['version']}` / {source} / {package['dependency']}"


def comparison(root, ohos):
    if root is None:
        return "OH only"
    if ohos is None:
        return "root only"
    if root == ohos:
        return "same"
    return "different"


def generate():
    root, root_sdks = read_lock(ROOT / "pubspec.lock")
    ohos, ohos_sdks = read_lock(ROOT / "ohos" / "flutter" / "pubspec.lock")
    names = sorted(set(root) | set(ohos))
    status_counts = {
        status: sum(comparison(root.get(name), ohos.get(name)) == status for name in names)
        for status in ("same", "different", "root only", "OH only")
    }
    lines = [
        "# Dart 依赖完整锁表",
        "",
        "> 由 `python ohos/tool/generate_ohos_dependency_inventory.py` 生成，请勿手工编辑。",
        "> 每个单元格的格式为 `版本 / 来源 / 依赖关系`。Git 来源同时显示锁定提交。",
        "",
        f"根锁文件共 {len(root)} 个包，鸿蒙锁文件共 {len(ohos)} 个包。",
        f"其中 {status_counts['same']} 项相同、{status_counts['different']} 项不同、",
        f"{status_counts['root only']} 项仅根锁存在、{status_counts['OH only']} 项仅鸿蒙锁存在。",
        "",
        "| SDK constraint | Root lock | OH lock |",
        "| --- | --- | --- |",
        f"| Dart | `{root_sdks.get('dart', '-')}` | `{ohos_sdks.get('dart', '-')}` |",
        f"| Flutter | `{root_sdks.get('flutter', '-')}` | `{ohos_sdks.get('flutter', '-')}` |",
        "",
        "| Package | Root lock | OH lock | Status |",
        "| --- | --- | --- | --- |",
    ]
    for name in names:
        lines.append(
            f"| `{name}` | {cell(root.get(name))} | {cell(ohos.get(name))} | "
            f"{comparison(root.get(name), ohos.get(name))} |"
        )
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    content = generate()
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != content:
            print(f"依赖锁表需要更新：{OUTPUT}", file=sys.stderr)
            return 1
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"已生成：{OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
