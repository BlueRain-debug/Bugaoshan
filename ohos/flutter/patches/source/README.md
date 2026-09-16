# 上游源码补丁

本目录保存鸿蒙对共享 Dart 源码和 ARB 文案的适配。补丁由构建脚本按顺序应用到
`ohos/build/workspace/` 中的独立副本，新增的适配文件也通过补丁创建。

[manifest.json](manifest.json) 定义应用顺序，`upstreamRevision` 记录补丁制作时的上游基线。
后续上游提交只要满足补丁上下文即可应用；上下文不匹配时，应重新审查适配并更新补丁。

通知页的最终实现由整条补丁链共同决定：`0013` 至 `0016` 提供移动布局和加载前遮罩，
`0018` 移除 `0017` 引入的主题刷新，改用 ArkWeb 原生主题更新和上游深浅 CSS。
`0017` 仍为后续补丁提供上下文，不能单独删除或跳过。

WebView 原生节点的主题更新还依赖 [嵌入层补丁](../embedding/README.md) 和
[插件配置补丁](../plugins/webview-configuration-update.patch)。调整主题行为时，应同时检查这三层。

## 补丁清单

| 补丁 | 副本中涉及的路径（相对 `lib/`） |
| --- | --- |
| `0001-flutter-sdk-compat.patch` | `pages/settings/set_dock_page.dart`、`theme.dart` |
| `0002-mobile-plugin-scope.patch` | `pages/dev/environment_info_page.dart`、`services/update_asset_selector.dart`、`services/exit_service.dart`、`services/window_state_service.dart`；新增 `utils/mobile_device_info.dart` |
| `0003-file-and-gallery.patch` | `utils/calendar_export_utils.dart`、`widgets/common/image_viewer.dart`；新增 `utils/file_save.dart`、`utils/gallery_save.dart` |
| `0004-webview-downloads.patch` | `widgets/webview/captcha_webview_dialog.dart`、`widgets/webview/webview_notice_handlers.dart`、`widgets/webview/webview_notice_page.dart`；新增 `widgets/webview/download_webview.dart` |
| `0005-external-links.patch` | `utils/open_link.dart`、`pages/about/about_page.dart`、`pages/about/team_page.dart`、`pages/profile/profile_menu_card.dart`、`widgets/eula_content.dart` |
| `0006-files-images-and-share.patch` | 选图涉及报修、办事大厅和背景设置页面；附件打开涉及下载弹窗及下载管理；分享涉及 `utils/share_utils.dart` 和日志导出页面；新增 `utils/image_pick.dart`、`utils/open_file.dart` |
| `0007-calendar-handoff.patch` | `utils/calendar_export_utils.dart`；启用 OH 日历入口并调用现有原生通道 |
| `0008-passpoint-results.patch` | `providers/passpoint_provider.dart`、`services/api/new_service_api_service.dart`；操作互斥及失败结果处理 |
| `0009-session-recovery.patch` | `services/auth/scu_auth.dart`、`providers/scu_auth_provider.dart`、`pages/auth/scu_login_page.dart`；登录恢复与持久化并发保护 |
| `0010-subsystem-session-guards.patch` | SSO、CCYL、报修认证和公共 API 重试，以及办事大厅、Passpoint、报修请求入口；阻止跨会话重试 |
| `0011-form-upload-lifecycle.patch` | 办事大厅表单、报修表单及项目选择器、背景裁剪；提交快照和页面/账号生命周期检查 |
| `0012-upload-responses.patch` | `services/api/service_api_service.dart`、`services/api/zhhq_api_service.dart`；上传响应状态、空文件与响应体超时 |
| `0013-tuanwei-mobile-layout.patch` | `widgets/webview/webview_notice_page.dart`；新增 `widgets/webview/tuanwei_mobile_layout.dart` 和 `widgets/webview/tuanwei_notice_loader.dart`，处理布局、禁用缩放、首帧遮罩、DOM 就绪重试和美化失败界面 |
| `0014-notice-dark-and-scroll.patch` | `widgets/webview/webview_notice_page.dart` 和 `widgets/webview/download_webview.dart`；通知页跟随系统主题，以及全部 WebView 共用的禁用回弹设置 |
| `0015-webview-theme-and-lifecycle.patch` | `widgets/webview/download_webview.dart`、`widgets/webview/webview_notice_page.dart`；新增 `widgets/webview/notice_webview_scripts.dart`，补齐教务处搜索框配色、青春川大离页确认、保留 WebView 实例及主题切换诊断 |
| `0016-notice-layout-before-display.patch` | 共用通知组件和 WebView、既有青春川大加载器及布局脚本；新增 `widgets/webview/notice_layout_ready.dart`，三个通知页等布局稳定后展示 |
| `0017-notice-reload-on-theme-change.patch` | `widgets/webview/download_webview.dart`、`widgets/webview/webview_notice_page.dart`、`widgets/webview/tuanwei_notice_loader.dart`；主题变化后刷新当前通知文档，刷新前先绘制不透明遮罩 |
| `0018-notice-native-theme.patch` | 共用 WebView 和通知组件；使用 ArkWeb 原生 AUTO 和上游媒体查询，移除 `0017` 的主题刷新及通知页主题 JS 探测 |
| `0019-ohos-dynamic-icon.patch` | 图标服务和设置项；启用 API 26 官方备用图标原生通道 |
| `0020-ohos-course-cards.patch` | 组件更新服务、DI、设置入口与添加页；新增课表快照和生命周期同步辅助文件，补充 `l10n/app_en.arb` / `app_zh.arb` 文案 |
| `0021-ohos-environment-info.patch` | 将 `0002` 的设备信息占位接口接入鸿蒙原生通道，补齐开发者页设备信息、复制全部、失败重试；鸿蒙显示原生设备类型，避免 `os_type` 未初始化的断言；新增中英文复制提示 |
| `0022-ohos-icon-confirmation.patch` | 仅修改中英文图标切换确认文案，去掉“应用将重启”，保留切换确认 |
| `0023-ohos-remove-ui-preview.patch` | `pages/dev/dev_page.dart` 移除 UI Preview 入口、对应分隔线及不再使用的 import |
| `0024-ohos-icon-api-gate.patch` | 点击应用图标入口时查询原生 API 支持；低于 26 提示鸿蒙 7 以下不支持该功能 |

## 应用规则

构建脚本先复制共享源码，再在副本内的独立 Git 临时目录应用补丁。
补丁只允许修改 `lib/` 下的 Dart 文件及 `lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb`；
不修改生成的本地化文件，也不向 `app_zh_Hans_CN.arb` 添加文案。

全部补丁成功后才将结果写回构建副本。每次构建使用新副本，避免旧适配叠加。

## 维护方式

1. 同步上游时，检查补丁涉及的 Flutter API、业务逻辑及插件接口是否变化。
2. 新增或更新补丁时，以前置补丁已应用后的源码为基准。新增文件使用 `/dev/null` 的新文件 diff。
   文件中段的修改应保留前后上下文，避免被识别为文件末尾匹配；不要通过放宽应用参数绕过冲突。
3. 在副本中完成适配后，将差异保存回本目录并更新清单。仅提交补丁及相关维护文件，
   不将构建副本复制回根源码。
4. 保持补丁顺序与依赖关系，完成同步后更新基线记录。
5. 执行相关分析、测试和 HAP 构建，记录源码提交、SDK、依赖锁与结果；平台能力变化还需真机回归。

第三方插件补丁见 [plugins/](../plugins/README.md)，测试入口见
[测试说明](../../../tests/README.md)。业务和权限说明见
[第三阶段说明](../../../docs/phases/phase3.md)，认证及旧数据处理依据见
[代码审查记录](../../../docs/audits/phase3-code.md)。
