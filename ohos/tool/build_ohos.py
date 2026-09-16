#!/usr/bin/env python3
"""在独立副本中使用鸿蒙稳定版 SDK 准备依赖或构建 HAP。"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse
from urllib.request import url2pathname
import zipfile

from ohos_patches import apply_dependency_patches, apply_source_patches
from ohos_embedding import prepare_embedding_runtime


ROOT = Path(__file__).resolve().parents[2]
STABLE_SDK_VERSION = re.compile(r"3\.41\.10-ohos-1\.\d+\.\d+")
TOOLCHAIN_LOCK = "toolchain.lock.json"
PUBSPEC_DEPENDENCIES = "pubspec_dependencies.json"
REQUIRED_OHOS_PLUGINS = (
    "file_picker_ohos",
    "flutter_inappwebview_ohos",
    "flutter_secure_storage_ohos",
    "image_gallery_saver_plus",
    "image_picker_ohos",
    "open_filex",
    "os_type",
    "package_info_plus",
    "path_provider_ohos",
    "share_plus",
    "shared_preferences_ohos",
    "sqflite_ohos",
    "url_launcher_ohos",
)
SOURCE_DIRECTORIES = ("lib", "assets", "test", "ohos")
SOURCE_FILES = (
    "pubspec.yaml",
    "analysis_options.yaml",
    "l10n.yaml",
    ".metadata",
    "CHANGELOG.md",
    "LICENSE",
)
IGNORE_GENERATED = shutil.ignore_patterns(
    ".git", ".idea", ".dart_tool", ".hvigor", ".appanalyzer", ".cxx",
    ".test", ".preview", ".ohos", "__pycache__", "build", "node_modules",
    "oh_modules", "libs", "flutter_assets", "GeneratedPluginRegistrant.ets",
    "local.properties", "package.json", "package-lock.json", "oh-package-lock.json5",
    ".flutter-embedding-runtime.json",
)


def validate_sdk_version(info, expected=None):
    version = info.get("flutterVersion", "")
    if not STABLE_SDK_VERSION.fullmatch(version):
        raise ValueError(
            f"需要 Flutter OH 3.41.10-ohos-1.x.x 稳定版，当前为 {version!r}。"
            "不支持 canary、beta 或 dev 版本。"
        )
    if expected is not None and version != expected:
        raise ValueError(f"Flutter OH 版本不匹配：需要 {expected}，当前为 {version}。")
    return version


def command_output(command, cwd=None, env=None):
    return subprocess.check_output(
        command, cwd=cwd, env=env, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8",
    ).strip()


def load_toolchain(root):
    path = root / "ohos" / "flutter" / TOOLCHAIN_LOCK
    if not path.is_file():
        raise ValueError(f"缺少鸿蒙工具链锁定文件：{path}")
    try:
        toolchain = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as error:
        raise ValueError(f"无法读取鸿蒙工具链锁定文件：{error}") from error
    if toolchain.get("schemaVersion") != 1:
        raise ValueError(f"不支持的鸿蒙工具链锁定格式：{path}")
    return toolchain


def resolve_flutter_command(explicit_sdk=None):
    suffix = ".bat" if os.name == "nt" else ""
    if explicit_sdk is not None:
        flutter = explicit_sdk / "bin" / f"flutter{suffix}"
        if not flutter.is_file():
            raise ValueError(f"无效的 Flutter SDK 目录：{explicit_sdk}")
        return str(flutter)
    flutter = shutil.which("flutter")
    if flutter is None:
        raise ValueError("PATH 中找不到 flutter；请先在 PowerShell 中配置 Flutter OH SDK。")
    return flutter


def sdk_commands(sdk):
    suffix = ".bat" if os.name == "nt" else ""
    flutter = sdk / "bin" / f"flutter{suffix}"
    dart = sdk / "bin" / f"dart{suffix}"
    if not flutter.is_file() or not dart.is_file():
        raise ValueError(f"Flutter OH 工具不完整：{sdk}")
    return str(flutter), str(dart)


def normalize_repository_url(url):
    return url.rstrip("/").removesuffix(".git").casefold()


def validate_flutter_sdk(sdk, info, expected, env):
    version = validate_sdk_version(info, expected["flutterVersion"])
    for key in ("frameworkRevision", "engineRevision", "dartSdkVersion"):
        actual = info.get(key, "")
        if actual != expected[key]:
            raise ValueError(f"Flutter OH {key} 不匹配：需要 {expected[key]}，当前为 {actual}。")

    revision = command_output(["git", "rev-parse", "HEAD"], sdk, env)
    if revision != expected["frameworkRevision"]:
        raise ValueError(
            f"Flutter OH 实际提交不匹配：需要 {expected['frameworkRevision']}，当前为 {revision}。"
        )
    tag_revision = command_output(
        ["git", "rev-parse", f"{expected['tag']}^{{}}"], sdk, env,
    )
    if tag_revision != revision:
        raise ValueError(f"Flutter OH 当前提交不是正式 tag {expected['tag']}。")
    repository = command_output(["git", "remote", "get-url", "origin"], sdk, env)
    if normalize_repository_url(repository) != normalize_repository_url(expected["repositoryUrl"]):
        raise ValueError(
            f"Flutter OH 仓库来源不匹配：需要 {expected['repositoryUrl']}，当前为 {repository}。"
        )
    return version


def parse_flutter_config(output):
    for line in output.splitlines():
        match = re.fullmatch(r"\s*ohos-sdk:\s*(.+?)\s*", line)
        if match and match.group(1) != "(Not set)":
            return Path(match.group(1)).expanduser().resolve()
    return None


def resolve_harmony_sdk(flutter, env, explicit_sdk=None):
    if explicit_sdk is not None:
        return explicit_sdk.expanduser().resolve()
    for name in ("OHOS_SDK_HOME", "HOS_SDK_HOME", "DEVECO_SDK_HOME"):
        value = env.get(name)
        if value:
            return Path(value).expanduser().resolve()
    configured = parse_flutter_config(command_output([flutter, "config", "--list"], env=env))
    if configured is None:
        raise ValueError(
            "未找到 HarmonyOS SDK；请在 PowerShell 环境变量中配置，"
            "或执行 flutter config --ohos-sdk <SDK目录>。"
        )
    return configured


def read_json(path, description):
    if not path.is_file():
        raise ValueError(f"缺少{description}：{path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as error:
        raise ValueError(f"无法读取{description} {path}：{error}") from error


def yaml_scalar(value):
    if not isinstance(value, str):
        raise ValueError(f"鸿蒙依赖配置只支持字符串标量，当前为 {value!r}。")
    return json.dumps(value, ensure_ascii=False)


def dependency_yaml(name, dependency):
    if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", name):
        raise ValueError(f"无效的鸿蒙依赖名：{name!r}。")
    if not isinstance(dependency, dict) or set(dependency) != {"git"}:
        raise ValueError(f"鸿蒙依赖 {name} 必须使用固定 Git 来源。")
    git = dependency["git"]
    if not isinstance(git, dict) or set(git) != {"url", "ref", "path"}:
        raise ValueError(f"鸿蒙依赖 {name} 的 Git 配置不完整。")
    ref = git["ref"]
    if not isinstance(ref, str) or re.fullmatch(r"[0-9a-f]{40}", ref) is None:
        raise ValueError(f"鸿蒙依赖 {name} 必须固定到完整 Git 提交。")
    return (
        f"  {name}:\n"
        "    git:\n"
        f"      url: {yaml_scalar(git['url'])}\n"
        f"      ref: {yaml_scalar(ref)}\n"
        f"      path: {yaml_scalar(git['path'])}\n"
    )


def add_ohos_dependencies(pubspec, config_path):
    config = read_json(config_path, "鸿蒙直接依赖配置")
    if config.get("schemaVersion") != 1:
        raise ValueError(f"不支持的鸿蒙直接依赖格式：{config_path}")
    dependencies = config.get("dependencies")
    if not isinstance(dependencies, dict) or not dependencies:
        raise ValueError(f"鸿蒙直接依赖配置为空：{config_path}")

    excluded = config.get("excludedDependencies", [])
    if not isinstance(excluded, list) or any(
        not isinstance(name, str) or
        re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", name) is None
        for name in excluded
    ):
        raise ValueError(f"鸿蒙排除依赖配置无效：{config_path}")
    if len(excluded) != len(set(excluded)):
        raise ValueError(f"鸿蒙排除依赖存在重复项：{config_path}")

    content = pubspec.read_text(encoding="utf-8")
    section = re.search(
        r"^dependencies:\s*$\n(?P<body>.*?)(?=^[A-Za-z_][A-Za-z0-9_]*:\s*$)",
        content,
        re.MULTILINE | re.DOTALL,
    )
    if section is None:
        raise ValueError(f"根 pubspec.yaml 缺少 dependencies 节：{pubspec}")
    body = section.group("body")
    for name in excluded:
        pattern = re.compile(
            rf"^  {re.escape(name)}:[^\n]*(?:\n(?=    )[^\n]*)*\n?",
            re.MULTILINE,
        )
        body, count = pattern.subn("", body, count=1)
        if count != 1:
            raise ValueError(f"根 pubspec.yaml 未声明待排除依赖 {name}。")

    content = content[:section.start("body")] + body + content[section.end("body"):]
    match = re.search(r"^dependencies:\s*$", content, re.MULTILINE)
    insert_at = match.end()
    additions = []
    for name, dependency in dependencies.items():
        if re.search(rf"^  {re.escape(name)}:\s*$", content, re.MULTILINE):
            raise ValueError(f"根 pubspec.yaml 已声明鸿蒙专用依赖 {name}。")
        additions.append(dependency_yaml(name, dependency))
    updated = content[:insert_at] + "\n" + "".join(additions) + content[insert_at:]
    pubspec.write_text(updated, encoding="utf-8")


def package_root(workspace, package_name):
    config_path = workspace / ".dart_tool" / "package_config.json"
    config = read_json(config_path, "Dart package_config")
    packages = config.get("packages")
    if not isinstance(packages, list):
        raise ValueError(f"Dart package_config 缺少 packages 数组：{config_path}")
    package = next(
        (item for item in packages if item.get("name") == package_name), None,
    )
    if package is None:
        raise ValueError(f"鸿蒙依赖中缺少 {package_name}。")
    root_uri = package.get("rootUri")
    if not isinstance(root_uri, str):
        raise ValueError(f"{package_name} 缺少有效的 rootUri。")
    parsed = urlparse(root_uri)
    if parsed.scheme == "file":
        root = Path(url2pathname(unquote(parsed.path)))
    elif parsed.scheme:
        raise ValueError(f"{package_name} 使用不支持的 rootUri：{root_uri}")
    else:
        root = config_path.parent / url2pathname(unquote(root_uri))
    root = root.resolve()
    if not root.is_dir():
        raise ValueError(f"{package_name} 源码目录不存在：{root}")
    return root


def replace_package_source(path, before, after, marker):
    content = path.read_text(encoding="utf-8")
    if marker in content:
        return False
    if content.count(before) != 1:
        raise ValueError(f"鸿蒙补丁与依赖源码不匹配：{path}")
    path.write_text(content.replace(before, after), encoding="utf-8")
    return True


def patch_flutter_secure_storage(workspace):
    config = read_json(
        ROOT / "ohos" / "flutter" / "patches" / "plugins" / "secure-storage.json",
        "安全存储兼容补丁",
    )
    package = package_root(workspace, "flutter_secure_storage")
    pubspec = package / "pubspec.yaml"
    version = pubspec.read_text(encoding="utf-8")
    if re.search(
        rf"^version:\s*{re.escape(config['version'])}\s*$", version, re.MULTILINE,
    ) is None:
        raise ValueError(f"鸿蒙安全存储补丁版本不匹配：{pubspec}")
    for edit in config["edits"]:
        replace_package_source(
            package / edit["path"], edit["before"], edit["after"], edit["marker"],
        )
    print("已校验并应用鸿蒙安全存储兼容补丁。", flush=True)


def validate_ohos_plugins(workspace, required_plugins=REQUIRED_OHOS_PLUGINS):
    metadata_path = workspace / ".flutter-plugins-dependencies"
    metadata = read_json(metadata_path, "Flutter 插件解析结果")
    plugins = metadata.get("plugins", {}).get("ohos", [])
    names = {
        plugin.get("name") for plugin in plugins if isinstance(plugin, dict)
    }
    missing = sorted(set(required_plugins) - names)
    if missing:
        raise ValueError("鸿蒙插件未进入生成注册列表：" + "、".join(missing))


def validate_harmony_toolchain(sdk, expected):
    component = read_json(
        sdk / "default" / "openharmony" / "ets" / "oh-uni-package.json",
        "HarmonyOS ETS SDK 信息",
    )
    component_fields = {
        "apiVersion": "apiVersion",
        "sdkVersion": "version",
        "releaseType": "releaseType",
    }
    for expected_key, actual_key in component_fields.items():
        actual = str(component.get(actual_key, ""))
        if actual != expected[expected_key]:
            raise ValueError(
                f"HarmonyOS {expected_key} 不匹配：需要 {expected[expected_key]}，当前为 {actual}。"
            )

    deveco = sdk.parent
    product = read_json(deveco / "product-info.json", "DevEco Studio 版本信息")
    if product.get("version") != expected["devecoStudioVersion"]:
        raise ValueError(
            "DevEco Studio 版本不匹配："
            f"需要 {expected['devecoStudioVersion']}，当前为 {product.get('version', '')}。"
        )
    package_versions = {
        "hvigorVersion": deveco / "tools" / "hvigor" / "hvigor" / "package.json",
        "ohpmVersion": deveco / "tools" / "ohpm" / "package.json",
    }
    for key, path in package_versions.items():
        actual = read_json(path, key).get("version", "")
        if actual != expected[key]:
            raise ValueError(f"{key} 不匹配：需要 {expected[key]}，当前为 {actual}。")

    node_name = "node.exe" if os.name == "nt" else "node"
    node = deveco / "tools" / "node" / node_name
    if not node.is_file():
        raise ValueError(f"缺少 DevEco Studio Node.js：{node}")
    actual_node = command_output([str(node), "--version"])
    if actual_node != expected["nodeVersion"]:
        raise ValueError(
            f"Node.js 版本不匹配：需要 {expected['nodeVersion']}，当前为 {actual_node}。"
        )

    hvigor_name = "hvigorw.bat" if os.name == "nt" else "hvigorw"
    configured_hvigor = shutil.which("hvigorw")
    expected_hvigor = (deveco / "tools" / "hvigor" / "bin" / hvigor_name).resolve()
    if configured_hvigor is None:
        raise ValueError("PATH 中找不到 hvigorw；请先在 PowerShell 中配置 DevEco Studio 工具。")
    if Path(configured_hvigor).resolve() != expected_hvigor:
        raise ValueError(
            f"PATH 中的 hvigorw 与锁定的 DevEco Studio 不一致：{configured_hvigor}。"
        )
    return deveco


def build_environment(sdk=None):
    env = os.environ.copy()
    if sdk is not None:
        env["PATH"] = str(sdk / "bin") + os.pathsep + env.get("PATH", "")
    # 与仓库两份锁文件记录的 hosted 源一致。
    env["PUB_HOSTED_URL"] = "https://pub.flutter-io.cn"
    env.setdefault("FLUTTER_STORAGE_BASE_URL", "https://storage.flutter-io.cn")
    return env


def materialize_flutter_tests(workspace):
    """Expose OH-only Dart tests inside the isolated package's test directory."""
    templates = workspace / "ohos" / "tests" / "flutter"
    for template in sorted(templates.rglob("*.dart.template")):
        relative = template.relative_to(templates).with_suffix("")
        destination = workspace / "test" / "ohos" / relative
        if destination.exists():
            raise ValueError(f"鸿蒙测试模板与已有测试文件冲突：{destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(template, destination)


def prepare_workspace(root):
    config = root / "ohos" / "flutter"
    for name in (
        "pubspec_overrides.yaml", "pubspec.lock", TOOLCHAIN_LOCK,
        PUBSPEC_DEPENDENCIES, "patches/source/manifest.json",
    ):
        if not (config / name).is_file():
            raise ValueError(f"缺少鸿蒙依赖配置：{config / name}")

    workspace_parent = root / "ohos" / "build" / "workspace"
    workspace_parent.mkdir(parents=True, exist_ok=True)
    # 每次创建新副本，避免旧源码残留，也允许多次构建彼此独立。
    workspace = Path(tempfile.mkdtemp(prefix="run-", dir=workspace_parent))
    for name in SOURCE_DIRECTORIES:
        source = root / name
        if source.is_dir():
            shutil.copytree(
                source, workspace / name,
                ignore=IGNORE_GENERATED if name == "ohos" else None,
            )
    for name in SOURCE_FILES:
        source = root / name
        if source.is_file():
            shutil.copy2(source, workspace / name)
    for name in ("pubspec_overrides.yaml", "pubspec.lock"):
        shutil.copy2(config / name, workspace / name)
    add_ohos_dependencies(
        workspace / "pubspec.yaml", config / PUBSPEC_DEPENDENCIES,
    )
    apply_source_patches(workspace, config)
    materialize_flutter_tests(workspace)
    build_profile = workspace / "ohos" / "build-profile.json5"
    build_profile_example = workspace / "ohos" / "build-profile.json5.example"
    if not build_profile.is_file() and build_profile_example.is_file():
        shutil.copy2(build_profile_example, build_profile)
    return workspace


def source_git_metadata(root):
    exact_tags = command_output(
        ["git", "tag", "--points-at", "HEAD", "--sort=-version:refname"], root,
    ).splitlines()
    if exact_tags:
        tag = exact_tags[0]
    else:
        tag = command_output(["git", "describe", "--tags", "--abbrev=0"], root)
    return {
        "GIT_TAG": tag,
        "GIT_COMMIT": command_output(["git", "rev-parse", "HEAD"], root),
        "GIT_COMMIT_DATE": command_output(["git", "log", "-1", "--format=%ci"], root),
    }


def dart_define_arguments(metadata):
    return [f"--dart-define={key}={value}" for key, value in metadata.items()]


def read_pubspec_version(pubspec):
    try:
        content = pubspec.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"无法读取应用版本声明：{pubspec}") from error
    match = re.search(
        r"^version:\s*([^\s+]+)\+(\d+)\s*$", content, re.MULTILINE,
    )
    if match is None:
        raise ValueError(f"无法从 {pubspec} 读取 versionName 和 versionCode。")
    return match.group(1), int(match.group(2))


def sync_workspace_version(root, workspace):
    version_name, version_code = read_pubspec_version(root / "pubspec.yaml")
    workspace_version = read_pubspec_version(workspace / "pubspec.yaml")
    if workspace_version != (version_name, version_code):
        raise ValueError("构建副本的 pubspec.yaml 与根版本声明不一致。")

    app_path = workspace / "ohos" / "AppScope" / "app.json5"
    app = read_json(app_path, "鸿蒙应用版本信息")
    app_info = app.get("app")
    if not isinstance(app_info, dict):
        raise ValueError(f"鸿蒙应用版本信息缺少 app 对象：{app_path}")
    app_info["versionName"] = version_name
    app_info["versionCode"] = version_code
    app_path.write_text(
        json.dumps(app, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    return version_name, version_code


def verify_hap_version(workspace):
    expected_name, expected_code = read_pubspec_version(workspace / "pubspec.yaml")
    app = read_json(workspace / "ohos" / "AppScope" / "app.json5", "鸿蒙应用版本信息")
    app_info = app.get("app", {})
    if app_info.get("versionName") != expected_name or app_info.get("versionCode") != expected_code:
        raise ValueError(
            "构建副本的鸿蒙版本未与根 pubspec.yaml 同步："
            f"需要 {expected_name}+{expected_code}，"
            f"当前为 {app_info.get('versionName')}+{app_info.get('versionCode')}。"
        )

    haps = list((workspace / "ohos" / "entry" / "build").glob("**/*.hap"))
    if not haps:
        raise ValueError("HAP 构建命令成功，但没有找到 .hap 产物。")
    hap = max(haps, key=lambda path: path.stat().st_mtime_ns)
    with zipfile.ZipFile(hap) as archive:
        try:
            pack_info = json.loads(archive.read("pack.info"))
        except (KeyError, json.JSONDecodeError) as error:
            raise ValueError(f"无法读取 HAP 包内版本信息：{hap}") from error
    try:
        packaged_version = pack_info["summary"]["app"]["version"]
    except (KeyError, TypeError) as error:
        raise ValueError(f"HAP 包内缺少版本信息：{hap}") from error
    if packaged_version.get("name") != expected_name or packaged_version.get("code") != expected_code:
        raise ValueError(
            f"HAP 包内版本不匹配：需要 {expected_name}+{expected_code}，"
            f"当前为 {packaged_version.get('name')}+{packaged_version.get('code')}。"
        )
    return hap


def build_hap(command, workspace, env):
    run(command, workspace, env)
    unsigned_haps = list(
        (workspace / "ohos" / "entry" / "build").glob("**/*-unsigned.hap")
    )
    if not unsigned_haps:
        raise ValueError("HAP 构建命令成功，但没有找到 unsigned HAP 产物。")
    return max(unsigned_haps, key=lambda path: path.stat().st_mtime_ns)


def run(command, workspace, env):
    print("> " + subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, cwd=workspace, env=env, check=True)


def resolve_dependencies(flutter, workspace, env, update_lockfile=False):
    command = [flutter, "pub", "get", "--no-example"]
    if not update_lockfile:
        command.append("--enforce-lockfile")
    run(command, workspace, env)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--flutter-sdk", type=Path, default=None,
        help="可选的 Flutter OH SDK 根目录；默认使用 PowerShell PATH 中的 flutter",
    )
    parser.add_argument(
        "--ohos-sdk", type=Path, default=None,
        help="可选的 HarmonyOS SDK 根目录；默认读取环境变量或 flutter config",
    )
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument(
        "--prepare-only", action="store_true", help="仅准备构建副本并校验锁文件",
    )
    actions.add_argument(
        "--update-lockfile", action="store_true",
        help="重新解析依赖并更新 ohos/flutter/pubspec.lock，然后退出",
    )
    parser.add_argument("--mode", choices=("debug", "profile", "release"), default="release")
    args = parser.parse_args(argv)
    explicit_flutter_sdk = args.flutter_sdk.expanduser().resolve() if args.flutter_sdk else None
    initial_flutter = resolve_flutter_command(explicit_flutter_sdk)
    env = build_environment(explicit_flutter_sdk)
    # 在临时目录运行版本查询，避免 Flutter 触碰主工程生成物。
    result = subprocess.run(
        [initial_flutter, "--version", "--machine"], cwd=tempfile.gettempdir(), env=env,
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    info = json.loads(result.stdout)
    sdk = Path(info["flutterRoot"]).resolve()
    flutter, dart = sdk_commands(sdk)
    env = build_environment(sdk)
    toolchain = load_toolchain(ROOT)
    version = validate_flutter_sdk(sdk, info, toolchain["flutter"], env)
    harmony_sdk = resolve_harmony_sdk(flutter, env, args.ohos_sdk)
    validate_harmony_toolchain(harmony_sdk, toolchain["harmonyOs"])
    for name in ("OHOS_SDK_HOME", "HOS_SDK_HOME", "DEVECO_SDK_HOME"):
        env[name] = str(harmony_sdk)
    print(
        f"Flutter OH: {version} ({info['frameworkRevision']})\n"
        f"HarmonyOS SDK: API {toolchain['harmonyOs']['apiVersion']} "
        f"({toolchain['harmonyOs']['sdkVersion']})",
        flush=True,
    )
    workspace = prepare_workspace(ROOT)
    prepare_embedding_runtime(workspace)
    # 插件补丁仅写入鸿蒙专用 Pub 缓存，不修改其他平台使用的缓存。
    env["PUB_CACHE"] = str(ROOT / "ohos" / "build" / "pub-cache")
    print(f"构建副本：{workspace}", flush=True)
    version_name, version_code = sync_workspace_version(ROOT, workspace)
    print(f"鸿蒙应用版本：{version_name}+{version_code}", flush=True)
    resolve_dependencies(flutter, workspace, env, args.update_lockfile)
    patch_flutter_secure_storage(workspace)
    apply_dependency_patches(workspace, ROOT / "ohos" / "flutter", package_root)
    validate_ohos_plugins(workspace)

    if args.update_lockfile:
        target = ROOT / "ohos" / "flutter" / "pubspec.lock"
        shutil.copy2(workspace / "pubspec.lock", target)
        print(f"已更新鸿蒙锁文件：{target}", flush=True)
        return 0
    if args.prepare_only:
        print("依赖准备完成。此步骤不代表 HAP 已构建或通过真机验证。", flush=True)
        return 0

    run([dart, "run", "build_runner", "build", "--delete-conflicting-outputs"], workspace, env)
    run([flutter, "gen-l10n"], workspace, env)
    metadata = source_git_metadata(ROOT)
    build_hap(
        [flutter, "build", "hap", f"--{args.mode}", "--no-pub", "--no-codesign",
         *dart_define_arguments(metadata)],
        workspace, env,
    )
    hap = verify_hap_version(workspace)
    print(f"构建完成：{hap}", flush=True)
    return 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"鸿蒙构建失败：{error}", file=sys.stderr)
        sys.exit(1)
