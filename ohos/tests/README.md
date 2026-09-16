# 鸿蒙测试

本目录包含鸿蒙构建脚本测试和 Flutter 平台适配测试。请先按
[开发指南](../README.md) 配置工具链，并根据测试类型选择运行目录。

## Python 脚本测试

`python/` 包含构建和插件补丁脚本的测试。在仓库根目录执行：

```powershell
python -m unittest discover -s ohos/tests/python -p "test_*.py"
```

## Flutter 适配测试

`flutter/` 维护 `*.dart.template`，避免上游整仓分析直接解析依赖 OH 插件的测试。
`ohos/tool/build_ohos.py` 准备副本时将模板复制为副本的 `test/ohos/*.dart`，
保留模板内相对目录；遇到已有同名测试即停止，不覆盖上游文件。

在完成依赖解析、源码补丁及代码生成的鸿蒙副本根目录中，使用同一 Flutter OH SDK 执行：

```powershell
flutter test --no-pub test/ohos/platform_adapters_test.dart test/webview_notice_handlers_test.dart
```

这些测试模拟平台通道，不替代真机操作。DevEco 原生测试仍按工程约定放在
[entry/src/ohosTest/](../entry/src/ohosTest/)。构建和调试入口见 [鸿蒙开发说明](../README.md)。
