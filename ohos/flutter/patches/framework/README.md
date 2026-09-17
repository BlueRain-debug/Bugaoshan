# Flutter framework 诊断补丁记录（已移除）

2026-09-17 后续审计发现，本机平台 `.dill` 缓存中的 ABI 排序与当前编译器不一致，
已核验的官方同版本缓存具有正确排序。因此不能把此前的地址截断直接归为锁定引擎版本
本身的缺陷。首选修复及本诊断补丁的退出步骤见
[Release 平台缓存修复方案](../../../docs/audits/release-aot-cache-repair.md)。尚待重新构建及真机验证。

当前 `build_ohos.py` 已撤销补丁接入，依赖解析后直接使用锁定 SDK 的 `packages/flutter`，
恢复原始 `RootIsolateToken` 和后台 isolate 平台通道选择逻辑。工具链锁增加了 OH 产物提交和
两份平台缓存的 SHA-256，首次准备和 DevEco 增量构建都会检查；旧缓存会在编译前被拒绝。
锁文件变动会让旧工作区重新准备，增量入口也会拒绝仍指向诊断副本的 Flutter package。

本目录仅保留诊断结论；补丁、清单、暂存脚本及其专用测试已移除，历史实现可从 Git 记录复查。
以下为此前诊断过程，不代表当前构建行为。

两份完整的 Release NativeCrash 表明，锁定的 Flutter OH `3.41.10-ohos-1.0.1` 在 AOT
调用 `PlatformConfigurationNativeApi::GetRootIsolateToken` 时跳转到了被截断的原生函数地址。
这是已确认的一个触发点，但还不能证明问题只影响这个 getter。

此前 `root-isolate-token.patch` 让鸿蒙构建直接使用根 isolate 的
`ServicesBinding.defaultBinaryMessenger`，避开上述 native getter。补丁后的 Release 产物
（`libapp.so` Build ID `e0344fe1e4ef657c0e4f83392bb27a23`）仍在另一个 AOT native 调用处
崩溃，因此该补丁只能用于诊断性绕过，不能视为 native resolver 或启动崩溃的发布修复。
Bugaoshan 没有在后台 isolate 使用平台通道；这个补丁明确不支持鸿蒙构建中的后台 isolate
平台通道。

此前 `build_ohos.py` 在依赖解析后校验锁定提交和源文件哈希，将 SDK 的 `packages/flutter` 复制到
`ohos/.flutter-workspace/tooling/flutter-framework/`，应用补丁，并只改工作区
`.dart_tool/package_config.json` 的 `flutter` 路径。SDK 安装目录不会被修改。
