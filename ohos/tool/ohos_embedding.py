"""Patch the selected Flutter embedding HAR inside an isolated OH workspace."""

import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile


def prepare_embedding_runtime(workspace, native):
    """Remember this invocation's Python for later DevEco/Hvigor builds."""
    git = shutil.which("git")
    if git is None:
        raise ValueError("PATH 中找不到 git，无法准备嵌入层补丁运行配置。")
    # Keep the launcher outside build outputs so DevEco Clean cannot remove it.
    (native / ".flutter-embedding-runtime.json").write_text(
        json.dumps({
            "schemaVersion": 1,
            "workspace": str(workspace.resolve()),
            "python": sys.executable,
            "git": git,
        }, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _patch_sources(sources, patch):
    # Stage only the pinned source files, never the SDK or an OHPM directory.
    env = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith("GIT_")
    }
    with tempfile.TemporaryDirectory(prefix="sources-", dir=patch["output"]) as directory:
        staging = Path(directory)
        command = [patch["git"], "-C", str(staging), "-c", "core.autocrlf=false"]

        def git(*args):
            result = subprocess.run(
                [*command, *args], env=env, capture_output=True,
                text=True, encoding="utf-8", errors="replace",
            )
            if result.returncode:
                raise ValueError(f"Flutter 嵌入层补丁失败：{result.stderr.strip()}")
            return result.stdout

        git("init", "--quiet")
        stats = git("apply", "--numstat", "-z", str(patch["file"]))
        targets = set()
        for row in stats.rstrip("\0").split("\0"):
            added, removed, relative = row.split("\t", 2)
            if not added.isdigit() or not removed.isdigit() or relative not in sources:
                raise ValueError(f"嵌入层补丁包含未锁定的文件：{relative}")
            targets.add(relative)
        if targets != set(sources):
            raise ValueError("嵌入层补丁与锁定的源文件清单不一致。")
        for relative, content in sources.items():
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        git("apply", "--check", "--whitespace=nowarn", str(patch["file"]))
        git("apply", "--whitespace=nowarn", str(patch["file"]))
        return {relative: (staging / relative).read_bytes() for relative in sources}


def patch_embedding(source, workspace, native):
    workspace = workspace.resolve()
    native = native.resolve()
    if workspace != native / ".flutter-workspace":
        raise ValueError("嵌入层输出必须位于原生工程的 .flutter-workspace 内。")
    # Hvigor cleans native/build. Its input HAR must live outside that tree.
    output = (workspace / "build" / "flutter-embedding").resolve()
    if not output.is_relative_to(workspace):
        raise ValueError("嵌入层输出目录不在当前鸿蒙副本内。")
    runtime_path = native / ".flutter-embedding-runtime.json"
    if not runtime_path.is_file():
        raise ValueError("请先通过 ohos/tool/build_ohos.py --prepare-only 准备 Flutter 工作目录。")
    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    if runtime.get("schemaVersion") != 1 or Path(runtime["workspace"]).resolve() != workspace:
        raise ValueError("嵌入层运行配置与当前构建副本不匹配。")
    git = runtime.get("git")
    if not isinstance(git, str) or not Path(git).is_file():
        raise ValueError("副本内记录的 Git 不可用，请重新准备副本。")
    output.mkdir(parents=True, exist_ok=True)

    config = native / "flutter" / "patches" / "embedding"
    manifest_bytes = (config / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    toolchain = json.loads((native / "flutter" / "toolchain.lock.json").read_text(encoding="utf-8"))
    if (manifest.get("schemaVersion") != 1 or
            manifest["engineRevision"] != toolchain["flutter"]["engineRevision"]):
        raise ValueError("嵌入层补丁与锁定工具链不匹配。")
    patch = (config / manifest["patch"]).resolve()
    if not patch.is_relative_to(config.resolve()) or not patch.is_file():
        raise ValueError("嵌入层补丁不存在或路径越界。")

    source = source.resolve(strict=True)
    source_bytes = source.read_bytes()
    fingerprint = hashlib.sha256()
    for data in (source_bytes, manifest_bytes, patch.read_bytes(), Path(__file__).read_bytes()):
        fingerprint.update(len(data).to_bytes(8, "big"))
        fingerprint.update(data)
    destination = output / f"flutter-embedding-{fingerprint.hexdigest()[:20]}.har"
    if source == destination:
        raise ValueError("不能把已打补丁的 HAR 作为 SDK 输入。")

    with tarfile.open(fileobj=io.BytesIO(source_bytes), mode="r:*") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        package_path = "package/oh-package.json5"
        if names.count(package_path) != 1:
            raise ValueError("Flutter HAR 缺少唯一的包描述。")
        package = json.loads(archive.extractfile(package_path).read())
        if (package.get("name") != manifest["packageName"] or
                package.get("version") != manifest["packageVersion"]):
            raise ValueError("Flutter HAR 包名或版本与补丁基线不匹配。")
        sources = {}
        for item in manifest["sources"]:
            relative = item["path"]
            path = PurePosixPath(relative)
            if (path.is_absolute() or ".." in path.parts or "\\" in relative or
                    ":" in relative or path.as_posix() != relative):
                raise ValueError(f"无效的嵌入层源码路径：{relative}")
            member_path = "package/" + relative
            if names.count(member_path) != 1 or not archive.getmember(member_path).isfile():
                raise ValueError(f"Flutter HAR 缺少唯一的源码文件：{relative}")
            content = archive.extractfile(member_path).read().replace(b"\r\n", b"\n")
            if hashlib.sha256(content).hexdigest() != item["sha256"]:
                raise ValueError(f"Flutter 嵌入层源码已变化，请更新补丁：{relative}")
            sources[relative] = content

        # A new input/patch/script gets a new dependency URL, avoiding OHPM's
        # previous archive cache. Only completed archives enter this cache.
        if destination.is_file():
            return destination
        replacements = _patch_sources(sources, {"file": patch, "output": output, "git": git})
        with tempfile.NamedTemporaryFile(dir=output, suffix=".har", delete=False) as file:
            temporary = Path(file.name)
        try:
            with tarfile.open(temporary, "w:gz") as rebuilt:
                for member in members:
                    relative = member.name.removeprefix("package/")
                    if relative in replacements:
                        content = replacements[relative]
                        updated = copy.copy(member)
                        updated.size = len(content)
                        rebuilt.addfile(updated, io.BytesIO(content))
                    else:
                        stream = archive.extractfile(member) if member.isfile() else None
                        try:
                            rebuilt.addfile(member, stream)
                        finally:
                            if stream is not None:
                                stream.close()
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--native-project", type=Path, required=True)
    args = parser.parse_args()
    artifact = patch_embedding(args.source, args.workspace, args.native_project)
    print(json.dumps({"archive": str(artifact)}, ensure_ascii=False))


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print(f"鸿蒙嵌入层准备失败：{error}", file=sys.stderr)
        sys.exit(1)
