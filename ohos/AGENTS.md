# 鸿蒙维护约定

- 鸿蒙适配的持久修改范围严格限定为 `ohos/`，前两阶段亦适用。
- 原生代码、依赖配置、锁文件、文档、测试和源码补丁保存在 `ohos/`；相关脚本统一放在 `ohos/tool/`。
- 文档集中在 `ohos/docs/`；`README.md` 是开发总入口，各补丁目录的 README 仅说明就近配置。
- 插件补丁及其版本清单保存在 `ohos/flutter/patches/plugins/`，`legacy/` 仍参与旧缓存迁移。
- Python 测试位于 `ohos/tests/python/`；OH Dart 测试维护为 `ohos/tests/flutter/*.dart.template`，
  只由构建脚本复制为隔离副本的 `test/ohos/*.dart`，避免上游分析解析 OH 专用依赖。
- 构建副本放在 `ohos/build/workspace/`，专用 Pub 缓存放在 `ohos/build/pub-cache/`；生成物不提交。
- 根 `lib/`、依赖声明、锁文件及其他平台文件跟随上游，不为鸿蒙直接修改它们。
- Dart 适配维护为 `ohos/flutter/patches/source/` 的补丁，由 `ohos/tool/build_ohos.py`
  只在 `ohos/build/workspace/` 的副本中应用，不另存整套业务代码或源码覆盖目录。
- 只使用 `ohos/flutter/toolchain.lock.json` 固定的稳定 SDK，不使用预览版，不硬编码本机路径。
- 嵌入层适配保存为 `ohos/flutter/patches/embedding/` 的补丁；Hvigor 只在构建副本内生成
  修改后的 HAR，不直接修改 SDK 安装目录。接入脚本在 `ohos/tool/`。
- 同一分支维护；双 SDK 校验放在阶段六，发布签名放在最后阶段。
- 鸿蒙不提供应用内下载更新包及自安装流程，也不接入仅服务自更新的下载通知通道；这些内容已从后续计划移除。
- 当前用户负责测试、依赖解析、构建及真机调试；代理只修改代码和文档，不执行这些命令。
- 开发入口见 [README.md](README.md)，状态见 [docs/sync-plan.md](docs/sync-plan.md)。
