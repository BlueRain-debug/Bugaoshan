# 上游与鸿蒙依赖清单

更新日期：2026-09-15。本文区分共享 Dart 依赖、只在鸿蒙构建中使用的覆盖、
需要 OH 原生实现的 Flutter 插件，以及 OHPM 依赖。

根 `pubspec.yaml` 当前声明 39 个运行依赖和 8 个开发依赖。根 `pubspec.lock` 共解析
205 个包；当前鸿蒙锁共 194 个包。全部直接和传递包的逐项版本对照见
[Dart 依赖完整锁表](lock-inventory.md)，全部直接依赖的 CPF 替代结论见
[鸿蒙依赖替代矩阵](replacements.md)。

锁文件本身还约束 SDK：根锁要求 Dart `>=3.12.0 <4.0.0`、Flutter `>=3.44.0`；
鸿蒙锁要求 Dart `>=3.11.0 <4.0.0`、Flutter `>=3.38.0`。实际鸿蒙构建使用下文固定的
Flutter OH `3.41.10-ohos-1.0.1` / Dart `3.11.5`。

## 1. 共享运行依赖

| 依赖 | 根声明 | 根解析 | 当前 OH 解析 | 类型 / OH 要求 |
| --- | --- | --- | --- | --- |
| `flutter` | SDK | SDK | Flutter OH SDK | Flutter 框架 |
| `flutter_localizations` | SDK | SDK | Flutter OH SDK | 本地化 SDK |
| `photo_view` | `^0.15.0` | 0.15.0 | 0.15.0 | 纯 Dart/Flutter |
| `get_it` | `^9.2.0` | 9.2.1 | 9.2.1 | 纯 Dart |
| `injectable` | `any` | 3.0.0 | 3.0.0 | 纯 Dart |
| `shared_preferences` | `any` | 2.5.5 | 2.5.4 Git | CPF OH 实现已解析和注册 |
| `flutter_app_group_directory` | `^1.1.0` | 1.1.0 | 1.1.0 | 仅 iOS 路径使用，OH 无需实现 |
| `intl` | `any` | 0.20.2 | 0.20.2 | 纯 Dart |
| `flutter_colorpicker` | `any` | 1.1.0 | 1.1.0 | 纯 Flutter |
| `url_launcher` | `any` | 6.3.2 | 6.3.2 Git | CPF OH 实现已解析和注册，默认网页打开方式仍需调用适配 |
| `package_info_plus` | `any` | 10.2.1 | 9.0.0 Git | CPF OH 实现已解析和注册 |
| `async` | `any` | 2.13.1 | 2.13.1 | 纯 Dart |
| `http` | `^1.2.0` | 1.6.0 | 1.6.0 | 纯 Dart |
| `sqflite` | `^2.4.2` | 2.4.3 | 2.4.2 Git | CPF `sqflite_ohos` 已解析和注册 |
| `sqflite_common_ffi` | `^2.3.4` | 2.4.2 | 2.4.0+3 | 仅桌面端，OH 使用 `sqflite_ohos` |
| `path_provider` | `^2.1.5` | 2.1.6 | 2.1.5 Git | 数据库初始化必需，CPF OH 实现已解析和注册 |
| `path` | `^1.9.0` | 1.9.1 | 1.9.1 | 纯 Dart |
| `dart_sm` | `^0.1.4` | 0.1.5 | 0.1.5 | 纯 Dart，国密算法 |
| `flutter_secure_storage` | `^10.0.0` | 10.3.1 | 9.2.4 Git | 认证必需 OH 实现，已接入并通过 HAP 编译 |
| `scu_ocr_lite` | Git | 2.0.0 | 2.0.0 | 纯 Dart，Git 依赖 |
| `archive` | `^4.0.9` | 4.0.9 | 4.0.9 | 纯 Dart |
| `os_type` | `^0.2.2` | 0.2.2 | 0.2.2 | 已有 OH 实现并进入注册列表 |
| `crypto` | `^3.0.0` | 3.0.7 | 3.0.7 | 纯 Dart |
| `file_picker` | `^12.0.0` | 12.0.0 | file_picker_ohos 10.3.8 Git | 已迁移 OH 保存接口，并修复原生 bytes 保存 |
| `fl_chart` | `^1.2.0` | 1.2.0 | 1.2.0 | 纯 Flutter |
| `flutter_markdown_plus` | `^1.0.7` | 1.0.12 | 1.0.12 | 纯 Dart/Flutter |
| `image_picker` | `^1.2.2` | 1.2.3 | 1.2.1 Git | CPF OH 实现已解析和注册 |
| `window_manager` | `^0.5.1` | 0.5.2 | - | 已从 OH 副本排除，窗口状态和退出服务通过 OH 补丁适配 |
| `screen_retriever` | `^0.2.0` | 0.2.2 | - | 已从 OH 副本排除，OH 不执行桌面窗口位置校验 |
| `system_theme` | `^3.2.0` | 3.3.0 | 3.2.0 | 系统强调色，尚无 OH 实现 |
| `google_fonts` | `^8.1.0` | 8.2.1 | 8.2.1 | Dart/Flutter，使用网络与文件缓存 |
| `share_plus` | `^13.1.0` | 13.3.0 | 12.0.1 Git | CPF OH 实现已解析和注册 |
| `gal` | `^2.3.0` | 2.3.3 | image_gallery_saver_plus 3.0.5 Git | 已迁移为系统确认保存原始图片文件 |
| `open_filex` | `^4.7.0` | 4.7.0 | 4.7.0 Git | CPF OH 实现已解析和注册 |
| `flutter_inappwebview` | Git commit | 6.2.0-beta.3 | 6.1.5 Git | 已接入 OH 1.1.3，并通过窄组件适配下载回调 |
| `tyme` | `^1.4.4` | 1.5.0 | 1.5.0 | 纯 Dart |
| `json_annotation` | `^4.12.0` | 4.12.0 | 4.12.0 | 纯 Dart |
| `device_info_plus` | `^13.2.0` | 13.2.0 | - | 已从 OH 副本排除，以 OH 源码补丁引入空结果接口 |
| `encrypt` | `^5.0.3` | 5.0.3 | 5.0.3 | 纯 Dart |

两个 Git 直接依赖的来源也由锁文件记录：

| 依赖 | 声明 | 当前锁定提交 |
| --- | --- | --- |
| `scu_ocr_lite` | Git `HEAD` | `6fa09e88676505e2e55376456c1b7716f07a6112` |
| `flutter_inappwebview` | Git 固定 ref | `666bc33f776285076327e4a94aafc103c693e17a` |

`flutter_inappwebview 6.2.0-beta.3` 是根工程现有上游依赖；鸿蒙方案没有另行引入预览版 SDK
或预览版 OH 插件。

## 2. 共享开发依赖

| 依赖 | 根声明 | 根解析 | 当前 OH 解析 | 用途 |
| --- | --- | --- | --- | --- |
| `flutter_test` | SDK | SDK | Flutter OH SDK | Widget / unit test |
| `flutter_driver` | SDK | SDK | Flutter OH SDK | Integration driver |
| `flutter_lints` | `^6.0.0` | 6.0.0 | 6.0.0 | Lints |
| `build_runner` | `any` | 2.15.1 | 2.15.1 | 代码生成 |
| `injectable_generator` | `any` | 3.1.1 | 3.0.2 | DI 生成 |
| `json_serializable` | `any` | 6.14.1 | 6.14.1 | JSON 生成 |
| `flutter_launcher_icons` | `^0.14.1` | 0.14.4 | 0.14.4 | 图标生成，当前不生成 OH 资源 |
| `fake_async` | `^1.3.0` | 1.3.3 | 1.3.3 | 时序测试 |

## 3. OH 基础插件依赖

| 共享主包 | OH 实现或形式 | 正式来源 | 当前状态 |
| --- | --- | --- | --- |
| `shared_preferences 2.5.4` | `shared_preferences_ohos 2.5.4` | `flutter_packages` tag `shared_preferences-v2.5.4-ohos-1.0.1` / `19bd50f…` | 已解析和注册 |
| `path_provider 2.1.5` | `path_provider_ohos 2.2.17` | `flutter_packages` tag `provider-v2.1.5-ohos-1.0.1` / `7cc9f4c…` | 已解析和注册 |
| `sqflite 2.4.2` | `sqflite_ohos 2.4.2` | `flutter_sqflite` tag `2.4.2-ohos-1.0.0` / `5ef0761…` | 已解析和注册 |
| `package_info_plus 9.0.0` | OH 实现在主包内 | `flutter_plus_plugins` tag `package_info_plus-9.0.0-ohos-1.0.0` / `bc4df81…` | 已解析和注册 |
| `flutter_secure_storage 9.2.4` | `flutter_secure_storage_ohos 1.2.2` + platform interface 1.1.2 | `fluttertpc_flutter_secure_storage` tag `9.2.4-ohos-1.0.0` / `ecc4257…` | 已解析和注册 |
| `os_type 0.2.2` | 主包自带 OH 实现 | Pub | 已注册 |

上表的版本是已核对的正式 tag，不是 beta/canary/dev。`shared_preferences`、
`path_provider`、`url_launcher` 和 `image_picker` 的主包内部引用可移动 Git 分支，
当前已将各自的 `*_ohos` 包与主包固定到同一完整提交；`sqflite_ohos` 也已显式固定。

## 4. 其他 OH 功能插件

| 依赖 | 业务能力 | OH 要求 |
| --- | --- | --- |
| `url_launcher` | 打开外链/本地文件 | CPF 实现已解析和注册，默认网页模式需适配，见下文 |
| `file_picker` | ICS 导出与文件选择 | OH 接口与原生保存补丁已接入，待真机验证 |
| `image_picker` | 背景图、报修与办事大厅上传 | CPF 实现已解析和注册，待真机验证 |
| `share_plus` | 日志、ICS 和附件分享 | CPF 12.0.1 已解析和注册；待真机验证 |
| `gal` | 保存图片到系统相册 | 已迁移至 image_gallery_saver_plus，待真机验证 |
| `open_filex` | 用系统应用打开附件 | CPF 实现已解析和注册，待真机验证 |
| `flutter_inappwebview` | 三类通知、JS bridge、Cookie 下载 | OH 6.1.5 与下载回调适配已接入，待真机验证 |
| `system_theme` | 系统强调色 | 需 OH 实现或共享代码回退 |

`flutter_app_group_directory` 和 `sqflite_common_ffi` 的现有调用被 iOS/桌面平台判断隔离，
当前 OH 不需为它们注册实现，但仍参与 OH 依赖解析。
`device_info_plus`、`window_manager` 和 `screen_retriever` 已通过构建副本依赖排除和窄接口
源码补丁移出 OH 依赖图；`screen_retriever` 的四个平台/接口传递包也已移除。

## 5. 当前鸿蒙专用解析

`ohos/flutter/pubspec_dependencies.json` 对隔离副本执行：

- `flutter_secure_storage_ohos` -> Git `ecc4257040163da3c4dd64d4fced5d4d24676a53` / path `flutter_secure_storage_ohos`。
- 排除根直接依赖 `device_info_plus`、`window_manager`、`screen_retriever`、`file_picker` 和 `gal`。
- 加入正式 `file_picker_ohos 10.3.8` 和 `image_gallery_saver_plus 3.0.5`；固定提交见覆盖配置和锁表。

[平台隔离补丁](../../flutter/patches/source/0002-mobile-plugin-scope.patch) 让副本中的
`WindowStateService` 不执行桌面窗口操作，`ExitService` 保留移动端等待 300 ms 后
`exit(0)` 的行为；根服务和其他平台依赖保持原样。

`ohos/flutter/pubspec_overrides.yaml` 当前覆盖：

- `flutter_secure_storage` -> 同一正式提交 / path `flutter_secure_storage`。
- `flutter_secure_storage_ohos` -> 同一正式提交 / path `flutter_secure_storage_ohos`。
- `path_provider` 和 `path_provider_ohos` -> `flutter_packages` 正式提交 `7cc9f4cfbd464943096dc7c87288252c543df5cb`。
- `share_plus` 和 `share_plus_platform_interface` -> `flutter_plus_plugins` 稳定 OH 分支固定提交 `bfd882da6893c4c8bfa1648ac637c2d557e6f4fa`。
- `shared_preferences` 和 `shared_preferences_ohos` -> `flutter_packages` 正式提交 `19bd50ff6d5eaa96f18c63796c51e1b4e78a7480`。
- `url_launcher` 和 `url_launcher_ohos` -> `flutter_packages` 正式提交 `f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b`。
- `image_picker` 和 `image_picker_ohos` -> `flutter_packages` 正式提交 `1a027ce4c1739b26356fe30556c027bfad47aa94`。
- `package_info_plus` -> `flutter_plus_plugins` 正式提交 `bc4df814a726042a9dad1a267ebb1d2973544e24`。
- `sqflite` 和 `sqflite_ohos` -> `flutter_sqflite` 正式提交 `5ef0761001378455e872e46d1c0620d39dcc1002`。
- `open_filex` -> `fluttertpc_open_filex` 正式提交 `850a9abd0220316dc2bb45924315cb2304ff4ab6`。
- `flutter_inappwebview` 及配套接口/OH 实现 -> 正式提交 `528fa913763148719cde7dae2dc22dc33f15da36`。
- 已移除临时 `win32` 覆盖，依赖自然解析为 `5.15.0`。

当前安全存储相关锁定结果：

| Package | Root | OH |
| --- | --- | --- |
| `flutter_secure_storage` | 10.3.1 | 9.2.4 Git `ecc4257…` |
| `flutter_secure_storage_ohos` | - | 1.2.2 Git `ecc4257…` |
| `flutter_secure_storage_platform_interface` | 2.0.3 | 1.1.2 |
| `flutter_secure_storage_windows` | 4.2.2 | 3.1.2 |
| `win32` | 6.4.0 | 5.15.0（自然解析） |

此前的 AOT 阻塞来自 Windows 传递依赖的 win32 5/6 API 冲突。迁移文件选择器后，
`windows_file_picker` 已移出 OH 依赖图，`win32` 自然解析为 5.15.0，当前 Dart AOT 已通过。
文件导出、相册和 WebView 的接口均由源码补丁在副本中创建，相关调用也只在副本修改。
补丁与专用缓存机制见 [../flutter-adaptation.md](../flutter-adaptation.md)。前述 AOT 通过是补丁迁移前
的记录，迁移后的流程尚待用户验证。

CPF `url_launcher_ohos` 对 HTTP(S) 的默认模式会进入应用内网页，要求
`harmony_browser_page` header 和宿主 ArkTS 页面。第三阶段 `0005-external-links.patch`
已将 OH 副本中的 `openLink`、EULA 等默认调用改为 `LaunchMode.externalApplication`，
并处理打开失败。选图、分享和附件打开也已有调用层及原生插件结果处理补丁，
具体见 [第三阶段代码说明](../phases/phase3.md)。这些新增补丁尚未编译或真机验证。

## 6. OHPM 和 Flutter OH 原生依赖

### 固定工具链

| 组件 | 固定版本 / 提交 |
| --- | --- |
| Flutter OH | `3.41.10-ohos-1.0.1`，framework `adaf911c35c9136a7d18fc424d714c9ec7724e60` |
| Flutter Engine | `42d3d75a56efe1a2e9902f52dc8006099c45d937` |
| Dart SDK | `3.11.5` |
| HarmonyOS SDK | API `26`，SDK `26.0.0.105`，Release |
| DevEco Studio | `26.0.0.821` |
| Hvigor | `6.26.4` |
| OHPM | `26.0.0.630` |
| DevEco Node.js | `v24.14.1` |

以上版本来自 `ohos/flutter/toolchain.lock.json`。该文件只锁版本和提交，不记录本机路径。

### 原生包与系统 Kit

| 位置 | 依赖 | 用途 |
| --- | --- | --- |
| `ohos/oh-package.json5` | `@ohos/hypium 1.0.6` (dev) | OH 原生测试框架 |
| Flutter OH 生成的 entry 依赖 | `@ohos/flutter_ohos` -> 本地 embedding HAR | Flutter Engine / MethodChannel 宿主 |
| Flutter OH 生成的 entry 依赖 | `flutter_native_arm64_v8a` / `flutter_native_x86_64` -> 本地 engine HAR | 真机与模拟器 Flutter Engine |
| OH 插件模块 | 各插件的本地 HAR / source module | 由 Flutter 工具按 `plugins.ohos` 生成 |
| `flutter_secure_storage_ohos` | `@kit.ArkData`、`@kit.CryptoArchitectureKit`、`@kit.ArkTS` | Preferences、加密和 Base64/TypedArray API |
| 应用原生代码 | HarmonyOS SDK Kit | Ability、ArkUI、日志、日历等系统 API，不是 OHPM 三方包 |

源码中的 `ohos/entry/oh-package.json5` 目前没有手写第三方 dependencies。Flutter OH 在构建副本中
根据 `.flutter-plugins-dependencies` 生成插件模块、HAR 引用和 `GeneratedPluginRegistrant.ets`。
`@ohos/hvigor-ohos-plugin` 由 DevEco/Hvigor 构建环境提供，不是应用的 OHPM 运行依赖。

当前最新隔离构建副本的 `plugins.ohos` 及 ArkTS 注册文件包含全部 13 项：
`file_picker_ohos`、`flutter_inappwebview_ohos`、`image_gallery_saver_plus`、
`flutter_secure_storage_ohos`、`image_picker_ohos`、`open_filex`、`os_type`、`package_info_plus`、
`path_provider_ohos`、`share_plus`、`shared_preferences_ohos`、`sqflite_ohos`、`url_launcher_ohos`。
构建脚本会验证这 13 项全部存在，缺失任意一项即停止。
源码目录中被忽略的旧 `GeneratedPluginRegistrant.ets` 曾列出 8 个插件，但构建脚本会排除并重新生成，
因此不能把旧文件当作当前依赖接入状态。

## 7. 生成和核对

本次迁移通过严格依赖解析、代码生成、文件/相册及下载处理的 8 个 Dart 测试，
18 个构建入口测试和 1 个补丁应用测试。已生成包含 13 个 OH 插件的 unsigned release HAP（2.5.1+20501，API 26，约 33.5 MB）；真机状态见
[同步计划](../sync-plan.md)。根依赖声明及锁文件未改动。

完整锁表通过以下命令更新：

```powershell
python ohos/tool/generate_ohos_dependency_inventory.py
python ohos/tool/generate_ohos_dependency_inventory.py --check
```

更新任一锁文件后应重新生成本文引用的完整锁表，并审查所有 `different`、`root only`和 `OH only` 项。
