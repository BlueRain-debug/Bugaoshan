"""Read-only checks for the OH artifacts used by Dart's FFI/AOT compiler."""

import hashlib
from pathlib import Path
import re


REVISION_FILES = {
    "engineRevision": "bin/internal/engine.ohos.version",
    "harRevision": "bin/internal/engine.ohos.har.version",
    "dartSdkRevision": "bin/cache/dart-sdk/revision",
}
PLATFORM_DIRECTORIES = ("flutter_patched_sdk", "flutter_patched_sdk_product")


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_flutter_artifacts(sdk, flutter_lock):
    """Reject stale platform kernels even when Flutter's version string matches.

    Flutter OH downloads these kernels using the OH engine revision, but its
    universal cache stamp can use the upstream engine revision. Comparing file
    contents is necessary: a matching Flutter version/stamp is insufficient.
    This check never downloads artifacts or writes to the shared SDK.
    """
    artifacts = flutter_lock.get("ohosArtifacts")
    if not isinstance(artifacts, dict):
        raise ValueError("工具链锁缺少 flutter.ohosArtifacts，不能验证 OH 平台缓存。")
    for name in REVISION_FILES:
        value = artifacts.get(name)
        if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{40}", value) is None:
            raise ValueError(f"工具链锁中的 OH {name} 必须是完整提交。")
    platforms = artifacts.get("platformSha256")
    if not isinstance(platforms, dict) or set(platforms) != set(PLATFORM_DIRECTORIES):
        raise ValueError("工具链锁必须包含普通和 product 两份 OH 平台缓存哈希。")
    for name, value in platforms.items():
        if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
            raise ValueError(f"工具链锁中的 {name} SHA-256 无效。")

    sdk = Path(sdk).resolve()
    failures = []
    for name, relative in REVISION_FILES.items():
        path = sdk / relative
        try:
            actual = path.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError) as error:
            failures.append(f"无法读取 {path}：{error}")
            continue
        if actual != artifacts[name]:
            failures.append(f"{path}：需要 {artifacts[name]}，实际 {actual!r}")

    for name in PLATFORM_DIRECTORIES:
        path = sdk / "bin/cache/artifacts/engine/common" / name / "platform_strong.dill"
        try:
            actual = _sha256(path)
        except OSError as error:
            failures.append(f"无法读取 {path}：{error}")
            continue
        if actual != platforms[name]:
            failures.append(f"{path}：需要 SHA-256 {platforms[name]}，实际 {actual}")

    if failures:
        raise ValueError(
            "Flutter OH 平台缓存与锁定工具链不一致，已停止准备/编译。\n"
            + "\n".join(f"- {failure}" for failure in failures)
            + "\n请先确认使用锁定的 Flutter OH SDK，再用该 SDK 执行 "
            "flutter precache --ohos --universal --force；"
            "校验通过后清理旧 AOT 输出并重新构建。\n"
            "完整步骤：ohos/docs/audits/release-aot-cache-repair.md。"
            "本检查不会自动修改 SDK。"
        )
