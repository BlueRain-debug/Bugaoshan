# Flutter framework 补丁

锁定的 Flutter OH `3.41.10-ohos-1.0.1` 在 Release AOT 中解析
`PlatformConfigurationNativeApi::GetRootIsolateToken` 时会截断 64 位原生函数指针，首次通过
默认 `MethodChannel` 查找 messenger 即跳转到未映射地址。

`root-isolate-token.patch` 让鸿蒙构建直接使用根 isolate 的
`ServicesBinding.defaultBinaryMessenger`，避开损坏的 native getter。Bugaoshan 没有在后台
isolate 使用平台通道；这个补丁因此明确不支持鸿蒙构建中的后台 isolate 平台通道。

`build_ohos.py` 在依赖解析后校验锁定提交和源文件哈希，将 SDK 的 `packages/flutter` 复制到
`ohos/.flutter-workspace/tooling/flutter-framework/`，应用补丁，并只改工作区
`.dart_tool/package_config.json` 的 `flutter` 路径。SDK 安装目录不会被修改。
