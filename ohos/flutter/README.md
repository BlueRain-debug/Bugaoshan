# Flutter OH 适配输入

此目录维护鸿蒙依赖配置、工具链版本、Dart 覆盖文件和插件/嵌入层补丁。开发与构建命令见
[鸿蒙开发入口](../README.md)，实现机制见 [Flutter 适配说明](../docs/flutter-adaptation.md)。

| 位置 | 用途 |
| --- | --- |
| [pubspec_dependencies.json](pubspec_dependencies.json) | 在副本增加或排除依赖 |
| [pubspec_overrides.yaml](pubspec_overrides.yaml) | 鸿蒙专用依赖覆盖 |
| [pubspec.lock](pubspec.lock) | 鸿蒙稳定 SDK 的独立依赖锁 |
| [toolchain.lock.json](toolchain.lock.json) | 正式 Flutter OH、Dart 与原生工具链版本 |
| [overrides/lib/](overrides/README.md) | 适配后的完整 Dart 文件，只覆盖同路径文件或新增 OH 文件 |
| [source-manifest.json](source-manifest.json) | 覆盖清单、逐文件及翻译条目的上游基线 |
| [l10n/](l10n/README.md) | 按键合并的鸿蒙 ARB 条目 |
| [patches/plugins/](patches/plugins/README.md) | 第三方插件补丁、版本约束及旧缓存迁移 |
| [patches/framework/](patches/framework/README.md) | Flutter framework Release AOT 兼容补丁及源码哈希 |
| [patches/embedding/](patches/embedding/README.md) | Flutter OH HAR 补丁、包版本与源码哈希 |
| [patches/hvigor/](patches/hvigor/README.md) | SDK Hvigor 路径适配及锁定源码哈希 |

`ohos/.flutter-workspace/` 通过文件链接引用共用及鸿蒙适配 Dart，翻译合并和代码生成写入本地普通文件；
插件补丁仅应用到鸿蒙专用缓存，嵌入层 HAR 在工程内生成。根锁文件和 SDK 安装目录不保存这些适配结果。
原生工程直接使用仓库 `ohos/`，DevEco 打开此目录；Flutter 工作目录中不再放置原生工程。

测试位于 [ohos/tests/](../tests/README.md)；阶段说明、兼容性审查和依赖对照已集中到
`ohos/docs/`，从 [开发入口](../README.md) 查阅。
