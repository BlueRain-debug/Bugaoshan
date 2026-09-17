# 第三方插件补丁

[manifest.json](manifest.json) 记录 OH 原生插件的包名、版本、Git 提交和补丁文件。
构建脚本严格解析鸿蒙锁文件后，由 `ohos/tool/ohos_patches.py` 在鸿蒙专用 Pub 缓存中应用。
补丁路径相对本目录；上下文或版本不匹配时停止，已经完整应用的补丁允许重入。

[secure-storage.json](secure-storage.json) 单独描述 `flutter_secure_storage 9.2.4`
主包的 options 回退及 macOS 参数兼容修改，由 `build_ohos.py` 在解析依赖后应用。

`legacy/` 的安全存储补丁仍被清单中的 `previousPatch` 引用，用于识别之前的缓存状态，
随后通过 `upgradePatch` 升级。它属于维护输入，不能当作历史生成物删除。

`sqflite-main-thread-channel.patch` 关闭 `sqflite_ohos 2.4.2` 新增的自管理
`ThreadWorker`，恢复同版本代码线原有的 `MethodChannel` 处理。当前 worker 会在 Release
冷启动时加载整个 `modules.abc`，在 worker 环境解析 Flutter ArkUI 模块；设备日志同时出现
`Observed is not defined`、`@ohos:app.ability.Want` 加载失败，随后发生 Native SIGSEGV。
此补丁保留当前版本的数据库实现，仅改变平台通道的调度位置；代价是超大 batch 的解码
和数据库调用重新占用平台主线程。

共享 Dart 覆盖文件见 [overrides/](../../overrides/README.md)，翻译条目见 [l10n/](../../l10n/README.md)；Flutter OH HAR 补丁见
[embedding/](../embedding/README.md)。完整行为与历史依据见
[Flutter 适配说明](../../../docs/flutter-adaptation.md)。

更新插件版本时，应同步检查补丁上下文和清单中的版本、Git 提交，重新生成鸿蒙锁文件，
并通过构建与对应能力的真机回归。提交变更时注明验证环境和结果。
