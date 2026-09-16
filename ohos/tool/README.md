# 鸿蒙构建脚本使用说明

[build_ohos.py](build_ohos.py) 使用锁定的正式 Flutter OH 工具链，在独立副本中应用鸿蒙适配、
解析依赖并构建 HAP。以下命令均以 **PowerShell、仓库根目录** 为运行环境。
工程结构与平台适配约定见 [鸿蒙开发指南](../README.md)。

## 快速使用

配置好当前终端的工具链后，执行：

```powershell
# 默认构建 Release HAP
python ohos/tool/build_ohos.py

# 构建 Debug HAP，用于 DevEco 真机调试
python ohos/tool/build_ohos.py --mode debug

# 构建 Profile HAP，用于性能调试
python ohos/tool/build_ohos.py --mode profile

# 显式构建 Release HAP
python ohos/tool/build_ohos.py --mode release

# 仅准备副本和依赖，不执行代码生成或 HAP 构建
python ohos/tool/build_ohos.py --prepare-only

# 查看参数帮助
python ohos/tool/build_ohos.py --help
```

每条命令独立使用。每次调用都会创建新的 `ohos/build/workspace/run-*/`；
先执行 `--prepare-only` 再执行构建命令，会得到两个副本，后者不会复用前者。

## 环境与 SDK 选择

需要 Python 3.10 或更新版本、Git、Flutter OH，以及配套的 DevEco Studio 原生工具链。
在当前 PowerShell 的 `PATH` 中配置 `python`、`git`、Flutter OH 的 `flutter`，
以及 DevEco 配套的 `hvigorw`、`ohpm` 和 `node`。

当前编译基线为 Flutter OH `3.41.10-ohos-1.0.1`、Dart `3.11.5` 和 HarmonyOS API 26。
精确版本和提交以 [toolchain.lock.json](../flutter/toolchain.lock.json) 为准。
脚本会校验 Flutter 版本、仓库来源、正式标签、framework/engine 提交和 Dart 版本，
并校验 HarmonyOS SDK、DevEco、Hvigor、OHPM 和 Node 版本。
安装兼容下限为 API 20；这不表示可以用 API 20 SDK 编译，详见 [兼容性说明](../docs/compatibility/api20.md)。

SDK 按以下优先级选择：

| SDK | 查找顺序（从左到右） |
| --- | --- |
| Flutter OH | `--flutter-sdk` → 当前 `PATH` 中的 `flutter` |
| HarmonyOS | `--ohos-sdk` → `OHOS_SDK_HOME` → `HOS_SDK_HOME` → `DEVECO_SDK_HOME` → `flutter config` 的 `ohos-sdk` |

如果 PowerShell 已配置这些环境，直接运行快速使用中的命令即可。
也可仅为本次调用指定路径，下面的占位内容需替换为实际 SDK 根目录：

```powershell
python ohos/tool/build_ohos.py --mode debug --flutter-sdk '<Flutter OH SDK 根目录>' --ohos-sdk '<DevEco SDK 根目录>'
```

`--flutter-sdk` 指向包含 `bin/` 的 Flutter OH 根目录。
`--ohos-sdk` 指向包含 `default/openharmony/` 的 DevEco SDK 根目录，不能直接指向 `default/openharmony/`。
脚本按 DevEco 安装布局查找 SDK 上一级的 `product-info.json` 和 `tools/`，
当前 `PATH` 中的 `hvigorw` 也必须来自同一套 DevEco 安装。

构建继承当前终端环境，并为子进程设置以下值：

| 项目 | 行为 |
| --- | --- |
| `PATH` | 将选定 Flutter OH 的 `bin/` 放在前面 |
| `PUB_CACHE` | 使用仓库内的 `ohos/build/pub-cache/` |
| `PUB_HOSTED_URL` | 固定为 `https://pub.flutter-io.cn`，与锁文件来源一致 |
| `FLUTTER_STORAGE_BASE_URL` | 未配置时使用 `https://storage.flutter-io.cn` |
| 三个 HarmonyOS SDK 环境变量 | 统一为本次选定的 SDK 路径 |

这些设置只作用于脚本的子进程环境。依赖解析需要能够访问对应 Pub 镜像和 Git 仓库。
完整构建还会读取应用仓库的 Git 提交和标签作为版本元数据，请使用保留相关标签历史的 Git 检出目录。

## 参数说明

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `--flutter-sdk PATH` | 从 `PATH` 查找 | 指定 Flutter OH SDK 根目录 |
| `--ohos-sdk PATH` | 从环境或 Flutter 配置查找 | 指定 HarmonyOS SDK 根目录 |
| `--mode debug\|profile\|release` | `release` | 设置 HAP 编译模式 |
| `--prepare-only` | 关闭 | 完成副本、依赖和插件准备后退出 |
| `--update-lockfile` | 关闭 | 重新解析依赖，回写鸿蒙锁文件后退出 |
| `-h` / `--help` | — | 显示帮助并退出 |

`--prepare-only` 与 `--update-lockfile` 不能同时使用。
这两个操作均需要完整工具链；添加 `--mode` 不会让它们执行 HAP 构建。

## 执行流程

| 步骤 | 普通构建 | `--prepare-only` | `--update-lockfile` |
| --- | --- | --- | --- |
| 校验 Flutter OH 与完整原生工具链 | 是 | 是 | 是 |
| 新建副本、加载依赖配置、应用源码补丁 | 是 | 是 | 是 |
| 复制 OH 测试模板、同步应用版本 | 是 | 是 | 是 |
| 解析依赖 | 强制遵循锁文件 | 强制遵循锁文件 | 允许更新锁文件 |
| 应用插件补丁、检查 OH 插件注册 | 是 | 是 | 是 |
| 回写维护目录的鸿蒙锁文件 | 否 | 否 | 是 |
| 运行 `build_runner` 和 `gen-l10n` | 是 | 否 | 否 |
| 构建 HAP、校验包内版本 | 是 | 否 | 否 |

副本的依赖来自根 `pubspec.yaml` 加上 [鸿蒙依赖配置](../flutter/README.md)，
使用 `ohos/flutter/pubspec.lock`，源码适配按 [补丁清单](../flutter/patches/source/manifest.json) 顺序应用。
根源码、根锁文件及根目录的 Pub 解析结果保持独立。

普通构建在副本中执行的主要命令如下，SDK 路径和 Git 元数据由脚本填充：

```text
flutter pub get --no-example --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter build hap --<mode> --no-pub --no-codesign --dart-define=...
```

脚本将根 `pubspec.yaml` 的 `version: x.y.z+N` 同步为副本的 `versionName: x.y.z` 和
`versionCode: N`，构建后检查原生配置与 HAP 内 `pack.info` 是否一致。
它不会自动增加版本号，也不会读取设备上旧安装包的版本。

该入口不自动执行格式检查、静态分析或测试；相关命令见 [测试说明](../tests/README.md)。
双 SDK 持续检查入口仍在 [阶段六计划](../docs/sync-plan.md#阶段六建立持续同步检查) 中。

## 副本、产物与 DevEco 调试

| 路径（相对仓库根目录） | 内容 |
| --- | --- |
| `ohos/build/workspace/run-*/` | 本次 Flutter 应用副本，包含补丁后的源码和独立 Pub 配置 |
| `ohos/build/workspace/run-*/ohos/` | DevEco 应打开的原生工程 |
| `ohos/build/workspace/run-*/ohos/entry/build/` | 原生编译输出与 HAP |
| `ohos/build/pub-cache/` | 鸿蒙专用 Pub 缓存，插件补丁也在此应用 |

HAP 通常位于本次副本的：

```text
ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
```

以终端中的 `构建副本：…` 和实际构建目录为准。脚本保留历史副本；旧副本不会自动跟随源码更新。

真机调试时，运行 `--mode debug`，然后在 DevEco 打开本次副本的 `ohos/`，配置设备和调试签名。
维护目录 `ohos/` 不包含完整的鸿蒙 Pub 解析结果和生成的插件模块，直接打开它构建可能出现插件
`Cannot find module`。副本中调整的适配应整理回维护目录的原生代码或源码补丁，再重新生成副本。

如果只运行了 `--prepare-only`，副本仍需完成代码生成与构建，不能视为可直接部署的产物。

### Release 与签名

`--mode release` 只选择 Release 编译模式。脚本始终传入 `--no-codesign`，并检查 unsigned HAP
是否存在；未签名 HAP 需要完成签名后才能安装。脚本没有签名或发布参数。

本机 `ohos/build-profile.json5` 存在时会被复制进副本，否则使用
[配置模板](../build-profile.json5.example)。本机配置可能使原生构建同时生成 signed HAP。
当前最终版本校验会选择修改时间最新的 `.hap`，因此 `构建完成：…` 也可能指向 signed 文件。
该输出只确认构建与版本校验通过，不验证签名类型、证书或可安装设备范围。

调试签名通常受描述文件中的设备范围约束；正式分发需要符合渠道要求的签名和描述文件。
文件名包含 `signed` 或采用 Release 模式，都不能单独证明可直接公开分发。
正式签名和覆盖升级安排见 [同步计划](../docs/sync-plan.md)。

## 更新鸿蒙依赖锁

在有意调整鸿蒙依赖时，先修改 `ohos/flutter/` 中的依赖配置及相关插件补丁约束，然后执行：

```powershell
# 在新副本中解析依赖，完成插件检查后回写 ohos/flutter/pubspec.lock
python ohos/tool/build_ohos.py --update-lockfile

# 根据根锁和鸿蒙锁生成依赖对照文档
python ohos/tool/generate_ohos_dependency_inventory.py

# 仅检查依赖对照文档是否与锁文件一致，不写文件
python ohos/tool/generate_ohos_dependency_inventory.py --check
```

`--update-lockfile` 使用 `flutter pub get --no-example`，不带 `--enforce-lockfile`；
它按依赖约束重新解析，不等同于将所有包升级到最新版本。此操作不生成 Dart 代码、不构建 HAP，
也不修改根 `pubspec.lock`。

审查鸿蒙锁文件、固定 Git 提交和 [依赖对照文档](../docs/dependencies/lock-inventory.md) 的变化后，
再进行普通构建与相关验证。普通构建遇到锁不匹配时会停止，不会自动回写鸿蒙锁。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| Flutter 或原生工具链版本不匹配 | 按工具链锁配置正式 SDK；检查当前 `PATH` 是否指向其他 Flutter 或 DevEco 安装 |
| 找不到 HarmonyOS SDK | 检查 SDK 查找优先级；确认当前进程能读取环境变量，路径包含 `default/openharmony/` |
| `hvigorw` 缺失或来自其他安装 | 将选定 DevEco 的 `tools/hvigor/bin/` 配置到当前 `PATH` |
| `--enforce-lockfile` 失败 | 核对上游依赖变化、鸿蒙覆盖和锁文件；需要调整依赖时按上一节显式更新 |
| 源码补丁与上游不匹配 | 更新报错指向的 `ohos/flutter/patches/source/` 补丁及其上下文，按顺序核对；不要直接改根源码 |
| 插件补丁或注册检查失败 | 核对鸿蒙插件版本、固定 Git 提交和 `ohos/flutter/patches/plugins/` 中的清单 |
| DevEco 报插件 `Cannot find module` | 确认打开的是本次隔离副本的 `ohos/`，且副本依赖准备成功 |
| 改动在设备上未生效 | 检查 DevEco 工程路径；旧副本不会自动同步维护目录的修改 |

命令成功返回 `0`；构建步骤或校验失败时通常输出 `鸿蒙构建失败：…` 并返回 `1`；
参数错误返回 `2`。失败时先查看首个失败步骤及其输出。

## 同目录辅助工具

| 文件 | 用途 |
| --- | --- |
| [generate_ohos_dependency_inventory.py](generate_ohos_dependency_inventory.py) | 生成或检查完整 Dart 依赖对照，仅依赖 Python 标准库 |
| [ohos_patches.py](ohos_patches.py) | 构建入口调用的补丁应用与插件校验辅助模块 |
| [ohos_embedding.py](ohos_embedding.py) | 在隔离副本中生成带适配补丁的 Flutter OH HAR |
| [flutter_embedding_plugin.ts](flutter_embedding_plugin.ts) | 将 HAR 适配接入 Hvigor 构建过程 |

后面三个工具由构建流程调用，日常构建使用 `build_ohos.py` 即可。
