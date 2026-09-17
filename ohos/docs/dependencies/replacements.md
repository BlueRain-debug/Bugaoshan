# 鸿蒙依赖替代矩阵

更新日期：2026-09-15。

本文以根 [pubspec.yaml](../../../pubspec.yaml) 声明的 39 个运行依赖和 8 个开发依赖为范围，
核对 CPF-Flutter 的 [flutter_packages](https://gitcode.com/CPF-Flutter/flutter_packages)、
[三方库兼容清单](https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.en.md)
以及清单链接到的独立仓库。完整的 205 个根锁包和 194 个 OH 锁包见
[lock-inventory.md](lock-inventory.md)；传递依赖跟随主包选择，不单独寻找 OH 插件。

状态含义：

- **可替换**：存在非 beta/dev/preview/canary 的 CPF 实现，且项目使用的 API 可保持或只需已记录的兼容补丁。
- **不能直接替换**：有 OH 功能实现，但包名、版本或项目所用 API 不同，必须修改 OH 构建副本源码。
- **不采用**：CPF 有实现，但该能力仅供其他平台使用，或项目已经决定从 OH 构建移除。
- **无需替换**：纯 Dart/Flutter、Flutter SDK 包，或上游包已经自带 OH 支持。
- **无稳定替代**：两个来源中没有可采用的正式 OH 实现；保留上游回退或另做平台实现。

“可替换”只表示源码与接口审查通过。只有依赖解析、HAP 构建和真机功能都通过后，
才能把对应功能记为已完成。

当前 `shared_preferences`、`path_provider`、`url_launcher`、`image_picker`、`package_info_plus`、
`share_plus`、`flutter_secure_storage`、`sqflite`、`open_filex` 九项均已替换为下表的 CPF 来源，
主包和 OH 平台包均固定完整提交。严格依赖解析、代码生成、应用 `lib/` 静态分析及插件生成注册通过；
后三项也已完成接口迁移和 OH 接入，`win32` 冲突已解决；“已替换”不代表真机功能通过。

## 1. 可用的正式来源

以下提交均来自正式 tag 或非 dev 稳定分支，未选择任何预览标签。

| 上游依赖 | CPF 版本 | 固定来源 | 本项目结论 |
| --- | --- | --- | --- |
| `shared_preferences` | 2.5.4 / `shared_preferences_ohos` 2.5.4 | `flutter_packages` tag `shared_preferences-v2.5.4-ohos-1.0.1`，`19bd50ff6d5eaa96f18c63796c51e1b4e78a7480` | 可替换；项目只用通用键值 API |
| `path_provider` | 2.1.5 / `path_provider_ohos` 2.2.17 | `flutter_packages` tag `provider-v2.1.5-ohos-1.0.1`，`7cc9f4cfbd464943096dc7c87288252c543df5cb` | 可替换，已进入 OH 锁和插件注册表 |
| `url_launcher` | 6.3.2 / `url_launcher_ohos` 6.3.2 | `flutter_packages` tag `url_launcher_v6.3.2-ohos-1.0.2`，`f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b` | 可替换；项目使用的 `canLaunchUrl`、`launchUrl` 和 `LaunchMode` 均存在 |
| `image_picker` | 1.2.1 / `image_picker_ohos` 0.8.13+7 | `flutter_packages` tag `image_picker-v1.2.1-ohos-1.0.1`，`1a027ce4c1739b26356fe30556c027bfad47aa94` | 可替换；项目只使用 `pickImage(source: ImageSource.gallery)` |
| `package_info_plus` | 9.0.0 | `flutter_plus_plugins` tag `package_info_plus-9.0.0-ohos-1.0.0`，`bc4df814a726042a9dad1a267ebb1d2973544e24` | 可替换；项目只使用 `PackageInfo.fromPlatform()` 和数据字段 |
| `device_info_plus` | 12.3.0 | `flutter_plus_plugins` tag `device_info_plus-12.3.0-ohos-1.0.0`，`8b5ba6a9ef3a28558177e9193319a0700f9cc640` | 有正式实现，但按项目决策不采用，OH 构建已排除 |
| `share_plus` | 12.0.1 | `flutter_plus_plugins` 非 dev 分支 `br_share_plus-v12.0.1_ohos`，固定 `bfd882da6893c4c8bfa1648ac637c2d557e6f4fa` | 可替换，已进入 OH 锁和插件注册表；该版本没有独立 OH 正式 tag |
| `flutter_secure_storage` | 9.2.4 / `flutter_secure_storage_ohos` 1.2.2 | `fluttertpc_flutter_secure_storage` tag `9.2.4-ohos-1.0.0`，`ecc4257040163da3c4dd64d4fced5d4d24676a53` | 可替换，已接入；构建副本补 `_selectOptions()` 回退和 10.x 参数别名 |
| `sqflite` | 2.4.2 / `sqflite_ohos` 2.4.2 | `flutter_sqflite` tag `2.4.2-ohos-1.0.0`，`5ef0761001378455e872e46d1c0620d39dcc1002` | 可替换；项目使用的 `openDatabase` 和通用数据库 API 兼容 |
| `open_filex` | 4.7.0 | `fluttertpc_open_filex` tag `4.7.0-ohos-1.0.0`，`850a9abd0220316dc2bb45924315cb2304ff4ab6` | 可替换；版本及 `OpenFilex.open` API 与根工程一致 |
| `file_picker` | `file_picker_ohos` 10.3.8 | `fluttertpc_file_picker` tag `10.3.8-ohos-1.0.0`，`1a38f43d7c2e976c2add2c057da79223a0913f84` | 不能直接 override；CPF 包名和 import 为 `file_picker_ohos`，`saveFile` 从实例调用并返回 `String?`，根工程 12.x 使用静态调用并返回 `Uri?` |
| `flutter_inappwebview` | 6.1.5 | `flutter_inappwebview` tag `6.1.5-ohos-1.0.0`，`528fa913763148719cde7dae2dc22dc33f15da36` | 不能直接 override；项目 fork 使用 `onDownloadStarting` / `DownloadStartResponse`，CPF 稳定版只有 `onDownloadStartRequest` |
| `screen_retriever` | 0.1.9 | `fluttertpc_screen_retriever` tag `0.1.9-ohos-1.0.0`，`a8ddc543e0839b2e56c565bc3d33ddd9653b8d5e` | 有旧版正式实现，当前 OH 不采用；已从 OH 构建排除根包及其平台/接口传递包 |
| `window_manager` | `window_manager_plus` 1.0.5 | `fluttertpc_window_manager_plus` tag `1.0.5-ohos-1.0.0`，`9c47e819888a93443f5e84e880a2723c274dc414` | 候选包名/API 不同，当前 OH 不采用；已从 OH 构建排除根包 |
| `gal` | `image_gallery_saver_plus` 3.0.5 | `fluttertpc_image_gallery_saver_plus` tag `3.0.5-ohos-1.0.0`，`163bd578508fcf99a11e699e2bea8a6140218f93` | 只有功能替代；可保存字节，但没有 `Gal.requestAccess` / `Gal.putImageBytes` 同名 API，需迁移权限和调用代码 |

## 2. 全部运行依赖

| 根依赖 | 根锁版本 | CPF/OH 结论 | 处理方式 |
| --- | --- | --- | --- |
| `flutter` | SDK | 无第三方替代 | 使用固定 Flutter OH `3.41.10-ohos-1.0.1` |
| `photo_view` | 0.15.0 | 无需替换 | 纯 Flutter，保留上游 |
| `get_it` | 9.2.1 | 无需替换 | 纯 Dart，保留上游 |
| `injectable` | 3.0.0 | 无需替换 | 纯 Dart，保留上游 |
| `shared_preferences` | 2.5.5 | 可替换，已解析注册 | OH 已固定 CPF 2.5.4 主包和 `shared_preferences_ohos` |
| `flutter_app_group_directory` | 1.1.0 | 不采用 | 仅 `Platform.isIOS` 分支调用，OH 不注册实现 |
| `flutter_localizations` | SDK | 无第三方替代 | 使用 Flutter OH SDK 自带版本 |
| `intl` | 0.20.2 | 无需替换 | 纯 Dart，保留上游 |
| `flutter_colorpicker` | 1.1.0 | 无需替换 | 纯 Flutter，保留上游 |
| `url_launcher` | 6.3.2 | 可替换，已解析注册 | 已固定 CPF 6.3.2 主包和 `url_launcher_ohos`；HTTP(S) 默认模式仍需应用调用适配，见下文 |
| `package_info_plus` | 10.2.1 | 可替换，已解析注册 | OH 已固定 CPF 9.0.0；win32 冲突已解决，待真机验证 |
| `async` | 2.13.1 | 无需替换 | 纯 Dart，保留上游 |
| `http` | 1.6.0 | 无需替换 | 纯 Dart，保留上游 |
| `sqflite` | 2.4.3 | 可替换，已解析注册 | OH 已固定 CPF 2.4.2 主包和 `sqflite_ohos` |
| `sqflite_common_ffi` | 2.4.2 | 不采用 OH 实现 | 已从 OH 副本排除；数据库由 `sqflite_ohos` 提供 |
| `path_provider` | 2.1.6 | 可替换，已接入 | OH 固定 CPF 2.1.5 和 `path_provider_ohos` 2.2.17 |
| `path` | 1.9.1 | 无需替换 | 纯 Dart，保留上游 |
| `dart_sm` | 0.1.5 | 无需替换 | 纯 Dart 国密实现，保留上游 |
| `flutter_secure_storage` | 10.3.1 | 可替换，已接入兼容补丁 | OH 固定 CPF 9.2.4 / OH 1.2.2；根工程仍用 10.3.1 |
| `scu_ocr_lite` | 2.0.0 | 无需替换 | 项目 Git 纯 Dart 依赖，保留根锁提交 |
| `archive` | 4.0.9 | 无需替换 | 纯 Dart，保留上游 |
| `os_type` | 0.2.2 | 无需替换 | Pub 主包已声明 OH 平台并已注册 |
| `crypto` | 3.0.7 | 无需替换 | 纯 Dart，保留上游 |
| `file_picker` | 12.0.0 | 已迁移接入 | OH 使用 file_picker_ohos 10.3.8；窄接口适配返回值，原生补丁正确保存本次 bytes |
| `fl_chart` | 1.2.0 | 无需替换 | 纯 Flutter，保留上游 |
| `flutter_markdown_plus` | 1.0.12 | 无需替换 | 纯 Dart/Flutter，保留上游 |
| `image_picker` | 1.2.3 | 可替换，已解析注册 | OH 已固定 CPF 1.2.1 和 `image_picker_ohos` 0.8.13+7 |
| `window_manager` | 0.5.2 | 不采用，已从 OH 排除 | OH 补丁适配窗口状态及退出服务，退出保留移动端行为；根源码不变 |
| `screen_retriever` | 0.2.2 | 不采用，已从 OH 排除 | OH 不执行桌面窗口位置校验，四个平台/接口传递包也已移除 |
| `system_theme` | 3.3.0 | 无稳定 CPF 替代 | OH `0026` 补丁移除调用，直接使用原有蓝色回退；深浅模式继续跟随系统，依赖锁暂保留该包 |
| `google_fonts` | 8.2.1 | 无稳定 CPF 替代 | CPF 文档仅列为 Developing；包本身是 Dart/Flutter 逻辑，继续使用上游并验证网络字体与缓存 |
| `share_plus` | 13.3.0 | 可替换，已接入 | OH 固定 CPF 稳定分支的 12.0.1；项目使用的 `SharePlus.instance.share(ShareParams(...))` 存在 |
| `gal` | 2.3.3 | 已迁移接入 | OH 使用 image_gallery_saver_plus 3.0.5；经系统确认保存临时原始图片文件，处理取消/错误和清理 |
| `open_filex` | 4.7.0 | 可替换，已解析注册 | 已固定同版本 CPF 实现 |
| `flutter_inappwebview` | 6.2.0-beta.3 Git fork | 已迁移接入 | OH 使用 CPF 稳定 6.1.5；DownloadWebView 适配 6.1 下载回调，共享 Cookie、下载和导航逻辑 |
| `tyme` | 1.5.0 | 无需替换 | 纯 Dart，保留上游 |
| `json_annotation` | 4.12.0 | 无需替换 | 纯 Dart，保留上游 |
| `device_info_plus` | 13.2.0 | 不采用，已从 OH 排除 | OH 补丁引入空设备信息接口；Android/iOS 继续使用根源码和依赖 |
| `encrypt` | 5.0.3 | 无需替换 | 纯 Dart，保留上游 |

## 3. 全部开发依赖

| 根依赖 | 根锁版本 | CPF/OH 结论 | 处理方式 |
| --- | --- | --- | --- |
| `flutter_test` | SDK | 无需替换 | 使用 Flutter OH SDK 自带版本 |
| `flutter_driver` | SDK | 无需替换 | 使用 Flutter OH SDK 自带版本 |
| `flutter_lints` | 6.0.0 | 无需替换 | 静态规则包，不进入 HAP 运行时 |
| `build_runner` | 2.15.1 | 无需替换 | Dart 代码生成工具；OH 锁选择 Dart 3.11 可解析版本 |
| `injectable_generator` | 3.1.1 | 无需替换 | Dart 代码生成工具；OH 锁可独立降级 |
| `json_serializable` | 6.14.1 | 无需替换 | Dart 代码生成工具；OH 锁独立解析 |
| `flutter_launcher_icons` | 0.14.4 | 无需替换 | 仅开发期生成其他平台图标，当前不负责 OH 资源 |
| `fake_async` | 1.3.3 | 无需替换 | 纯 Dart 测试工具 |

## 4. 剩余接入与验证顺序

1. 三项迁移与窄接口现在保存为 OH 完整 Dart 覆盖文件，说明见 [../flutter-adaptation.md](../flutter-adaptation.md)；
   OH 锁自然选择 win32 5.15.0，未使用强制覆盖。此前构建记录属于补丁迁移前，新的流程待用户验证。
2. 第三阶段已编写 OH external 模式、选图、附件打开、分享和日历调用补丁，并修复
   open_filex、share_plus、image_picker_ohos 的原生结果处理。见
   [第三阶段代码说明](../phases/phase3.md)，新增代码尚未构建或测试。
3. 在真机验证 ICS 实际文件内容、取消/覆盖保存、相册确认弹窗和原图格式，以及通知页 JS bridge、
   Cookie、验证码、下载去重和导航。当前测试使用模拟平台，不能替代这些验证。
4. 每组变更由用户在新副本验证补丁和插件注册；只有依赖有意变更时才更新 OH 锁。
   签名留在全部功能验证之后。

不应接入 CPF 的 beta/dev 标签。CPF 仓库内部如果引用可移动 Git 分支，OH 覆盖文件必须同时把对应平台包固定到完整提交，最终以 `ohos/flutter/pubspec.lock` 的 `resolved-ref` 为准。
