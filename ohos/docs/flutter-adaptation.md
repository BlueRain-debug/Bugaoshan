# 鸿蒙 Flutter 适配

根工程维护共享业务、上游依赖和上游锁文件。`ohos/tool/build_ohos.py` 将当前源码复制到
`ohos/build/workspace/run-*/`，再应用 `ohos/flutter/` 的配置和补丁。环境及 DevEco 调试入口见
[鸿蒙开发说明](../README.md)。根源码不保留鸿蒙适配修改。

| 位置 | 用途 |
| --- | --- |
| `ohos/flutter/pubspec_dependencies.json` | 仅在副本增加 OH 依赖、排除不使用的根依赖 |
| `ohos/flutter/pubspec_overrides.yaml` | 固定 CPF 主包和平台接口/实现的 Git 提交 |
| `ohos/flutter/pubspec.lock` | 鸿蒙稳定 SDK 对应的依赖锁 |
| `ohos/flutter/patches/source/manifest.json` | 源码补丁顺序与制作时的上游基线提交 |
| `ohos/flutter/patches/source/*.patch` | SDK 与平台调用适配，以及第四阶段通知页布局适配 |
| `ohos/flutter/patches/plugins/manifest.json` | 原生插件补丁的包名、版本、Git 提交和补丁文件 |
| `ohos/flutter/patches/plugins/*.patch` | 可直接审查的原生源码差异 |
| `ohos/flutter/patches/embedding/` | Flutter OH 嵌入层的主题配置补丁、HAR 包版本和源码哈希 |
| `ohos/flutter/patches/plugins/secure-storage.json` | 安全存储 9.2.4 options 回退与 macOS 参数兼容补丁 |
| `ohos/tests/flutter/platform_adapters_test.dart.template` | 仅在 OH 依赖副本中运行的文件保存和相册适配测试 |
| `ohos/tests/python/test_*.py` | 从原 `.github/scripts/tests/` 迁入的 OH 构建和补丁脚本测试 |

## 源码补丁

全部 Dart 适配维护为 [有序补丁](../flutter/patches/source/README.md)，不再维护 `source_overrides/`。
以下辅助文件由补丁创建在构建副本中，根目录不保存这些文件：

- `lib/utils/file_save.dart`：使用 `file_picker_ohos`，
  将其 `String?` 返回值统一为保存成功/取消。
- `lib/utils/gallery_save.dart`：将 PNG/JPEG/GIF/WebP/BMP 原始字节
  写入临时文件，经 `image_gallery_saver_plus.saveFile` 和系统保存确认弹窗保存。
  取消返回 false，失败抛出异常，结束后清理临时文件；不进行 PNG 重编码。
- `lib/widgets/webview/download_webview.dart`：副本中的页面以 `Future<bool>` 表达下载接管结果，
  映射到 CPF 6.1.5 的 `onDownloadStartRequest`，并启用 OH WebView 入口。
  `0014` 在此统一复制页面设置并强制 `OverScrollMode.NEVER`，覆盖当前全部 WebView，
  包括通知、志愿四川和附件验证码窗口；后续新增 WebView 入口也应复用此组件。
  `0015` 在 State 中保留同一 `InAppWebView`，回调转发给最新页面状态；控制器只由插件释放。
  增加离页确认回调和一次性的主题切换诊断。`0018` 移除 `0017` 的主题刷新并关闭通知页探测，
  三个通知页由 ArkWeb AUTO 切换；其他页面保留诊断。Cookie、请求头、任务状态和验证码业务继续来自上游。
- `lib/utils/mobile_device_info.dart`：`0021` 将设备信息接入原生 `bugaoshan/environment_info`
  通道，读取品牌、型号、系统版本、API 等级及 ABI；安卓专用 ABI 查询仍为空，不引回 `device_info_plus`。
- `lib/widgets/webview/tuanwei_mobile_layout.dart`：在上游美化脚本前后补充青春川大移动端视口和布局，
  关闭网页缩放，宽表格局部滚动；只处理匹配站点及通知结构的文档。实现与待验收范围见
  [通知页说明](audits/notice-webview.md)。
- `lib/widgets/webview/tuanwei_notice_loader.dart`：首帧不透明遮罩、等待通知 DOM、确认美化完成后显示，
  以及失败/超时后的重试界面。`0016` 提取共用的 `NoticeLayoutLoader`，让教务处和学工部
  复用该显示时序；青春川大子类继续使用自己的移动端布局。手动 retry 先启动遮罩并等待
  Flutter 帧完成，再调用当前控制器的 reload，失败显示重试；主题切换不调用 retry。
- `lib/widgets/webview/notice_webview_scripts.dart`：在教务处美化脚本后追加搜索框的动态深浅色规则，
  并提供主题切换后的媒体查询和动画帧诊断。三个通知页使用 `ForceDark.AUTO` 跟随系统；
  青春川大通知页定向接管本域名、空消息的离页确认。原理及验收边界见 [通知页说明](audits/notice-webview.md)。
- `lib/widgets/webview/notice_layout_ready.dart`：三个通知页文档开始时隐藏原网页，等待美化、
  资源及字体就绪、布局稳定后撤销网页隐藏，再经过两个动画帧通知 Flutter 撤掉遮罩。
  复用同一原生 WebView；重复注入不会重新隐藏已显示的文档，超时保留失败重试界面。

补丁同时修改副本中的调用处、排序回调、主题 import、窗口状态和退出服务，隔离不使用的桌面插件。
应用器在独立临时 Git 目录中处理相关文件，全部补丁成功后才写回构建副本，不在副本中保留 `.git`。
只允许修改副本 `lib/` 下的 Dart 文件及明确列出的 `lib/l10n/app_en.arb`、
`lib/l10n/app_zh.arb` 文案；上下文不匹配即停止，要求更新补丁。

第五阶段 `0019`、`0020` 接入动态图标和安卓对齐课表服务卡片。
`0021` 补齐开发者页设备信息、完整复制及读取失败重试；`0022` 去掉鸿蒙切换图标的重启文案。
`0023` 移除开发者页 UI Preview 入口及对应分隔线。
`0024` 在点击应用图标入口时查询原生 API 支持；低于 26 提示“鸿蒙 7 以下不支持该功能”，停留在设置页。
卡片展示快照和生命周期同步辅助文件仅由补丁在副本中创建，原生实现维护在
`entry/src/main/ets/cards/` 和 `entry/src/main/ets/platform/`。
新文案由副本既有的 `flutter gen-l10n` 步骤生成，不手工修改生成的 Dart 本地化文件。
第五阶段已获用户整体验收确认，代码与验收记录见 [第五阶段说明](phases/phase5.md)。

## 插件补丁

`webview-configuration-update.patch` 将系统主题配置更新传给现有的 WebBuilderNode，
与 [Flutter 嵌入层补丁](../flutter/patches/embedding/README.md) 配合，移除主题变化导致的原生节点重建。
嵌入层 HAR 由 Hvigor 在副本中准备，不写入 SDK；这一补丁不属于 Pub 缓存补丁。

`file-picker-save-bytes.patch` 让保存操作直接使用本次传入的 bytes 和文件名，
不依赖此前选择文件产生的缓存；处理空内容、部分写入、取消和文件句柄关闭。

`gallery-save-result.patch` 保证重复调用和异常都返回 Flutter 结果，且在 finally 中恢复
保存状态，避免出错后后续保存永久等待。

第三阶段新增 `open-file-result.patch`、`share-files-result.patch`、`image-picker-result.patch`，
修复系统打开结果、分享文件准备及错误回复、选图取消和失败分类。
配套应用源码补丁是 `0005` 至 `0007`，行为和权限依据见 [第三阶段代码说明](phases/phase3.md)。
后续 `0008` 至 `0012` 补齐登录恢复、账号切换、表单和上传的异常路径；
`secure-storage-results.patch` 修复 OH 安全存储的错误回传和并发操作。
旧数据处理与逐项审查结果见 [代码审查记录](audits/phase3-code.md)。

`secure-storage.json` 保留 EasyNode 同类接入方式：OH 固定正式版 9.2.4，解析后为
`_selectOptions()` 增加空 options 回退，并补上根源码使用的 macOS 参数别名。
它校验包版本和待替换原文；根依赖继续使用 10.x。

上述插件补丁只应用到 `ohos/build/pub-cache/` 专用缓存。每次先校验包版本、提交及补丁上下文；
完整应用过的补丁允许重入，遇到源码漂移立即失败。不要直接修改全局 Pub 缓存作为维护方式。
安全存储补丁现将六处捕获后重新抛出的异常转换为明确的 `Error`，满足 ArkTS 的 `arkts-limited-throw` 限制。
已应用旧版的缓存通过清单中的 `previousPatch` 识别，再应用 `upgradePatch`；下一次运行构建入口时自动处理。
`legacy/secure-storage-results-untyped-throw.patch` 仅用于识别旧状态，不作为新构建的应用目标。
`secure-storage-error-types.patch` 仅用于将该旧状态升级到当前完整补丁，避免清空缓存或覆盖其他修改。
升级插件时必须重新审查补丁，更新锁文件并重跑测试和无签名构建。

## 验证命令

本次只迁移代码和维护位置，未执行验证。以下命令由用户在根目录执行，SDK 从 PowerShell 环境读取：

```powershell
python -m unittest discover -s ohos/tests/python -p "test_*.py"
python ohos/tool/build_ohos.py --mode release
python ohos/tool/generate_ohos_dependency_inventory.py
```

只有依赖有意变更时才执行 `python ohos/tool/build_ohos.py --update-lockfile`。
测试维护目录及运行位置见 [测试说明](../tests/README.md)。构建脚本将
`ohos/tests/flutter/*.dart.template` 复制为副本的 `test/ohos/*.dart`，遇到已有同名文件即停止。
在已应用补丁和完成代码生成的构建副本根目录中，使用同一 Flutter OH SDK 执行：

```powershell
flutter test --no-pub test/ohos/platform_adapters_test.dart test/webview_notice_handlers_test.dart
dart analyze lib
```

测试模拟文件选择和相册通道；它们不替代真机上的保存弹窗、文件内容、下载去重、Cookie
和验证码验证。构建入口只生成 unsigned HAP，发布签名在同步计划最后阶段处理。
