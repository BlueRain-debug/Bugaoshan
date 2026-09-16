# HarmonyOS 开发指南

本目录包含不高山上（Bugaoshan）的 HarmonyOS 原生工程、Flutter OH 适配配置和开发工具。
鸿蒙端与其他平台在同一分支维护，共享仓库根目录的业务代码；平台适配通过补丁应用到独立构建副本。

上游与 Flutter OH 使用不同的 SDK 和依赖锁。构建鸿蒙版本时，请使用本目录的构建入口，
由脚本加载 `ohos/flutter/` 中的配置，保持根目录的源码、依赖锁和生成文件供上游环境使用。

## 环境要求

| 工具 | 当前要求 |
| --- | --- |
| Python | 3.10 或更新版本，构建脚本仅依赖标准库 |
| Git | 可通过 `PATH` 调用 |
| Flutter OH | `3.41.10-ohos-1.0.1` 正式版，配套 Dart `3.11.5` |
| HarmonyOS SDK | API 26，`26.0.0.105` Release |
| DevEco Studio | `26.0.0.821`，使用配套 Node、OHPM 和 Hvigor |

精确版本、Flutter 仓库来源及 framework/engine 提交见
[toolchain.lock.json](flutter/toolchain.lock.json)。构建脚本会校验这些信息，
仅支持锁定的正式工具链。

应用最低安装版本配置为 HarmonyOS API 20，编译和目标 SDK 使用 API 26。
API 20 的能力差异及验证范围见 [兼容性说明](docs/compatibility/api20.md)；
动态图标切换采用 API 26 接口，低版本点击入口时显示不支持提示。

以下命令以 PowerShell 为例。在当前终端的 `PATH` 中配置 `python`、Flutter OH 的 `flutter`、
`git`，以及 DevEco 配套的 `hvigorw`、`ohpm` 和 `node`。通过 `DEVECO_SDK_HOME`，
或 `flutter config --ohos-sdk <SDK目录>` 指定 HarmonyOS SDK。
依赖解析需要能够访问配置中的 Pub 镜像和 Git 仓库。

脚本继承终端环境，也支持通过 `--flutter-sdk` 和 `--ohos-sdk` 参数指定 SDK 根目录。
本机路径和签名材料不应写入受版本控制的文件。

## 构建

完整参数、执行阶段、产物与签名说明及常见问题见 [构建脚本使用说明](tool/README.md)。

在仓库根目录执行：

```powershell
# 可选：仅准备独立副本、解析依赖并检查插件注册
python ohos/tool/build_ohos.py --prepare-only

# 构建 Debug HAP
python ohos/tool/build_ohos.py --mode debug

# 构建 Release HAP
python ohos/tool/build_ohos.py --mode release
```

每次调用都会创建新的 `ohos/build/workspace/run-*/` 副本。脚本依次完成：

1. 校验工具链，复制应用源码和原生工程。
2. 加载鸿蒙依赖配置、独立锁文件和有序源码补丁。
3. 严格解析依赖，应用插件补丁并检查 OH 插件注册。
4. 生成 Dart 代码和本地化资源，构建 HAP 并校验应用版本。

`--prepare-only` 在依赖准备完成后退出，不执行代码生成和 HAP 构建；该入口同样需要上表中的完整工具链。
补丁上下文、依赖锁或工具链不匹配时，脚本会停止并报告原因。

应用版本来自根 `pubspec.yaml`。构建使用 `--no-codesign`，产物位于本次副本内；
真机部署需在 DevEco 中配置调试签名，正式发布与覆盖升级流程见 [同步计划](docs/sync-plan.md)。

本机 `ohos/build-profile.json5` 存在时会复制到副本；否则使用
[build-profile.json5.example](build-profile.json5.example)。`local.properties` 由 Flutter
根据当前环境在副本中生成。

## DevEco 真机调试

1. 通过构建脚本生成 Debug 副本，记录终端输出的副本目录。
2. 在 DevEco Studio 中打开该副本的 `ohos/`，即 `ohos/build/workspace/run-*/ohos/`。
3. 配置设备与调试签名，然后使用 DevEco 的运行和调试功能。

仓库根 `ohos/` 保存维护输入；调试副本还包含补丁后的 Dart 源码、独立 Pub 解析结果和生成的插件模块。
DevEco 必须打开完整的调试副本，才能使用这套适配结果。

在副本中调试得到的修改需要整理回 `ohos/` 的原生源码或补丁，再重新生成副本验证。
副本不会自动回写源码，也不会自动跟随仓库更新。重新生成后，应在 DevEco 中切换到新副本。

## 目录结构

```text
ohos/
├── README.md                          # 开发入口
├── AGENTS.md                          # 自动化编码工具的维护约定
├── AppScope/                          # 应用标识、版本与图标
├── entry/src/main/                    # 原生入口、平台通道、课表卡片与资源
├── entry/src/ohosTest/                 # DevEco 原生测试
├── hvigor/                            # Hvigor 配置
├── hvigorfile.ts                      # 原生构建任务
├── hvigorconfig.ts                    # Flutter 原生模块注入
├── oh-package.json5                   # 鸿蒙工程依赖
├── build-profile.json5.example        # 构建配置模板
├── flutter/
│   ├── pubspec_dependencies.json      # 鸿蒙依赖增减配置
│   ├── pubspec_overrides.yaml         # 鸿蒙依赖覆盖
│   ├── pubspec.lock                   # 鸿蒙独立依赖锁
│   ├── toolchain.lock.json            # 正式工具链版本与提交
│   └── patches/
│       ├── source/                    # 有序 Dart / ARB 补丁
│       ├── plugins/                   # 第三方插件补丁与版本约束
│       └── embedding/                 # Flutter OH HAR 补丁与源码哈希
├── tool/                              # 构建、补丁应用与依赖清单脚本
├── tests/
│   ├── python/                        # 构建与补丁脚本测试
│   └── flutter/                       # OH 专项测试模板
├── docs/
│   ├── sync-plan.md                   # 同步计划与验证进度
│   ├── flutter-adaptation.md          # 适配机制
│   ├── dependencies/                 # 依赖说明、完整锁表与替代矩阵
│   ├── compatibility/                # 系统版本兼容性
│   ├── audits/                       # 代码审查与问题排查记录
│   └── phases/                       # 各阶段实现与验收说明
└── build/                             # 本地生成物，不提交
    ├── workspace/run-*/               # 独立构建副本
    └── pub-cache/                     # 鸿蒙专用 Pub 缓存
```

DevEco 缓存、`oh_modules/`、`node_modules/`、模块构建目录及本机配置由 `.gitignore` 管理。
构建脚本复制维护输入时会排除生成目录，避免旧缓存和历史副本进入新构建。

## 测试与验证

在仓库根目录运行 Python 脚本测试：

```powershell
python -m unittest discover -s ohos/tests/python -p "test_*.py"
```

OH 专项 Flutter 测试以 `*.dart.template` 维护，准备副本时会复制为 `test/ohos/*.dart`。
在完成依赖解析和代码生成的鸿蒙副本根目录，使用同一 Flutter OH SDK 运行：

```powershell
dart analyze lib
flutter test --no-pub test/ohos/platform_adapters_test.dart test/webview_notice_handlers_test.dart
```

测试范围及原生测试入口见 [测试说明](tests/README.md)。平台通道测试使用模拟实现；
插件、WebView、数据库或认证存储发生变化时，还需要在对应系统版本的真机上回归。
提交变更时请记录源码提交、SDK 版本、检查命令和结果，并注明未验证的项目。

双 SDK 持续检查入口仍在计划中，当前命令不代表完整的跨平台验收；进度见
[持续同步检查](docs/sync-plan.md#阶段六建立持续同步检查)。

## 贡献与上游同步

鸿蒙适配的修改集中在 `ohos/`：原生功能修改对应 ArkTS 源码和资源，共享 Dart / ARB
适配保存为 [源码补丁](flutter/patches/source/README.md)。更新补丁时同步清单，保持应用顺序，
并按前置补丁后的源码核对上下文。构建副本用于调试和验证，不应作为维护源码提交。

调整插件版本时，更新鸿蒙依赖配置，并显式重新生成鸿蒙锁文件：

```powershell
python ohos/tool/build_ohos.py --update-lockfile
python ohos/tool/generate_ohos_dependency_inventory.py
```

审查锁文件、Git 提交和补丁差异，随后重新生成副本并执行相关检查。
依赖清单输出到 `ohos/docs/dependencies/lock-inventory.md`，应由脚本生成。
普通构建严格使用现有锁文件，不自动升级依赖。

## 参考文档

- [Flutter 适配机制](docs/flutter-adaptation.md)：源码、插件和嵌入层补丁的工作方式。
- [依赖替代矩阵](docs/dependencies/replacements.md)与[完整依赖对照](docs/dependencies/lock-inventory.md)。
- [API 20 兼容性说明](docs/compatibility/api20.md)。
- [通知页与 WebView 排查记录](docs/audits/notice-webview.md)。
- [课表卡片、动态图标和设备信息](docs/phases/phase5.md)。
- [同步计划](docs/sync-plan.md)：阶段进度、验证记录和发布安排。
