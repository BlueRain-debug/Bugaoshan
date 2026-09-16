# Flutter OH 适配输入

此目录只维护鸿蒙依赖配置、工具链版本和补丁。开发与构建命令见
[鸿蒙开发入口](../README.md)，实现机制见 [Flutter 适配说明](../docs/flutter-adaptation.md)。

| 位置 | 用途 |
| --- | --- |
| [pubspec_dependencies.json](pubspec_dependencies.json) | 在副本增加或排除依赖 |
| [pubspec_overrides.yaml](pubspec_overrides.yaml) | 鸿蒙专用依赖覆盖 |
| [pubspec.lock](pubspec.lock) | 鸿蒙稳定 SDK 的独立依赖锁 |
| [toolchain.lock.json](toolchain.lock.json) | 正式 Flutter OH、Dart 与原生工具链版本 |
| [patches/source/](patches/source/README.md) | 按清单顺序应用的共享 Dart / ARB 补丁 |
| [patches/plugins/](patches/plugins/README.md) | 第三方插件补丁、版本约束及旧缓存迁移 |
| [patches/embedding/](patches/embedding/README.md) | Flutter OH HAR 补丁、包版本与源码哈希 |

源码补丁仅应用到 `ohos/build/workspace/` 内的副本；插件补丁仅应用到鸿蒙专用缓存，
嵌入层 HAR 在副本内生成。根源码、根锁文件和 SDK 安装目录不保存这些适配结果。

测试位于 [ohos/tests/](../tests/README.md)；阶段说明、兼容性审查和依赖对照已集中到
`ohos/docs/`，从 [开发入口](../README.md) 查阅。
