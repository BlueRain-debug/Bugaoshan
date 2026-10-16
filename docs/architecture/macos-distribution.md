# macOS App Store 分发与原生控件

macOS 与 iOS 共用 App Store Connect 应用记录 `6813305962`。主应用 Bundle ID 为 `io.github.thebrotherhoodofscu.bugaoshan.ios`，Widget 为该 ID 加 `.CourseWidget`，两者使用 `group.io.github.thebrotherhoodofscu.bugaoshan.ios` 共享课表数据库与显示设置。共用商店条目不代表跨设备同步课表；iPhone 与 Mac 各自保存本地数据。

最低系统为 macOS 13，课表小组件需要 macOS 14。应用、小组件及 Flutter 引擎以 universal binary 支持 Apple Silicon 和 Intel。签名团队与 iOS 一致；私钥和描述文件只存入本机受限目录及专用签名仓库的 GitHub Secrets，不提交 Git。

## Liquid Glass

`Runner/LiquidGlass.swift` 使用 `NSHostingView` 承载 SwiftUI 控件，通过 `AppKitView` 接入 Flutter。macOS 26+ 只对导航、开关与滑块采用原生呈现：设置使用系统 Toggle / Slider，宽窗口使用系统 List 侧栏，图标与文案横排且只有当前入口高亮；窄窗口使用可横向滚动的导航，并用 `GlassEffectContainer` 管理玻璃按钮。课程、表单及列表内容继续由 Flutter 绘制。

Flutter 维护选中入口与开关值，原生层仅回传稳定入口 ID、开关值或滑块开始/变化/结束事件，避免入口重排与旧事件错选页面。主题、RTL、文字缩放、减少动态效果和高对比度参数通过现有桥接同步；系统减少透明度由原生控件处理。macOS 13–25、旧 SDK 或桥接失败时恢复 Material 导航和控件。开关与滑块复用 iOS 的调用点，登录/登出、重试、确认等操作按钮统一保留原有 Material 样式。原生绑定先更新自身值，再通知 Flutter；相同值的回传不重启动效，也不额外叠加玻璃或切换动画。

拖动期间保留系统滑块的当前位置，延迟的 Flutter 回传不能把滑块拉回旧值；范围或主题变更仍会同步，松手后恢复以 Flutter 业务值为准。普通控件配置与同值回传不额外启动 SwiftUI 动画。

桥接单测使用模拟通道，不能证明真实材质、鼠标或键盘行为。`tool/test_macos_glass_state.py --framework-dir <FlutterMacOS.framework 的父目录>` 在 macOS 26+ 编译并执行实际 Swift 状态模型，覆盖开关同值回传、滑块拖动期间的旧值回传、开始/结束回调去重与中途禁用。发布前在签名 release 应用中检查宽窄窗口、导航、设置值同步、滚动、弹窗及路由切换；旧 macOS 与 Intel 的实际运行需要相应设备验收。

## 构建与签名

使用 Flutter 3.44.9、支持 macOS 26 API 的 Xcode 和 CocoaPods。先在 Xcode 登录发布 iOS 时使用的开发者账号，并确保主应用和 Widget 的 App ID 均启用上述 App Group。

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export MACOS_BUILD_NAME=2.5.3
export MACOS_BUILD_NUMBER=<App-Store-Connect-中未使用的递增构建号>
bash tool/macos_distribution.sh archive
bash tool/macos_distribution.sh export
```

脚本依次执行依赖解析、build_runner、本地化生成、Flutter 配置和 Xcode 归档，输出 `build/macos/archive/Bugaoshan.xcarchive`；导出到 `build/macos/appstore/`。归档本身必须正确签名，主应用和内嵌 Widget 必须使用同一证书。`tool/verify_macos_bundle.py` 检查实际包中的版本、Bundle ID、隐私清单、双架构及签名中的 Sandbox/App Group/Keychain/文件/日历权限，拒绝 release 中的调试 JIT 和服务端网络权限。

导出的 Mac App Store 安装包还需使用 `pkgutil --check-signature` 核实安装器签名，并在 Xcode Organizer Validate App 后上传，或通过 Transporter 上传 `.pkg`。App Store Connect 处理成功后才可选择构建；上传、处理、提交审核和正式可下载是不同状态。加密问卷沿用实际 SM2/AES 用途，参见 [iOS 分发说明](ios-distribution.md#隐私清单与加密问卷)，不能声明应用仅使用 HTTPS。

主应用和 Widget 包含 required-reason API 隐私清单。主应用保留 App Sandbox，仅授权出站网络、用户选取的文件、日历和应用自身的 Keychain/App Group；导入日历会请求系统权限，不能把声明权限视为用户已经授权。

## CI 与既有安装

PR 与 build-only 调用 `build-macos.yml` 的无证书 universal 构建，验证制品保留 7 天。商店归档、安装器签名和上传通过上述本机流程处理。

站外安装使用独立的 Developer ID Application 证书（团队 `2MDTD66RDG`），并为主应用和 Widget 分别嵌入 Developer ID 描述文件。App Store 签名不能直接用于 GitHub DMG。专用仓库 [wjlfish/Bugaoshan-macos](https://github.com/wjlfish/Bugaoshan-macos) 的默认分支 `macos-signing` 保存发布工具，每 10 分钟同步上游 `main` / `preview` 并寻找尚未签名的新 tag；同步不会覆盖签名分支。仅接受上游发布分支已包含、且带有 `.github/macos-signing.json` 的 tag，旧版不自动补发。

`signed-macos-release.yml` 将无凭据构建与签名分为两个 job。签名 job 使用专用分支上的工具，临时钥匙串导入证书，逐层签名所有 Mach-O、Framework、Widget 和主应用，启用 Hardened Runtime 与安全时间戳。随后分别公证并装订 app / DMG，执行 `codesign` / `stapler` / Gatekeeper 校验。签名仓库发布 `macos-vX.Y.Z...` 暂存 Release，包含 universal DMG 和记录上游 tag / commit / 构建版本 / SHA-256 / 公证状态的 `macos-manifest.json`。

所需 Secrets：`MACOS_CERTIFICATE_P12_BASE64`、`MACOS_CERTIFICATE_PASSWORD`、`MACOS_APP_PROFILE_BASE64`、`MACOS_WIDGET_PROFILE_BASE64`、`NOTARY_KEY_P8`、`NOTARY_KEY_ID`、`NOTARY_ISSUER_ID`。公证使用独立的 App Store Connect **团队 API 密钥**（Developer 角色）；个人 API 密钥不能用于 notarytool。无需把 GitHub 个人 PAT 交给上游或签名仓库。

原仓库变量 `MACOS_SIGNING_ENABLED=true` 启用必需的签名制品门禁。`build-macos.yml` 等待专用仓库发布同一 tag / commit 的 DMG，复核 manifest、校验和、Developer ID、双架构、实际包内版本与公证票据，通过后才上传 `macos-release` 制品。`release.yml` 在发布 Release 前将 DMG 与 Android / Windows 安装包一起上传；超时、错版本、错签名、缺失公证均阻止发布，不回退未签名包。变量未启用时只执行原有构建验证。可通过签名工作流的 `tag` 输入重试待处理 tag。

macOS 凭据统一使用 Data Protection Keychain，服务名独立于插件默认值，权限由签名和描述文件中的 access group 决定。旧实现 `usesDataProtectionKeychain: false` 使用登录钥匙串，其 ACL 绑定旧应用签名，更新后会对多个凭据反复弹授权。新版不自动读取、删除或迁移旧钥匙串项目；既有 Mac 用户需重新登录一次，本地课表和设置保留。iOS 的服务名和可访问性设置保持原样。

旧 Mac 包名为 `io.github.thebrotherhoodofscu.bugaoshan`，App Group 和签名团队也不同。共用条目版使用新的容器，无法直接读取旧容器或 Keychain；旧版用户应先导出课表，再在新版导入并重新登录。不要为迁移删除旧版数据或放宽 Sandbox。共用 Bundle ID 的 iOS 与 macOS App Group 名称一致，但不会自动跨设备共享数据库。

参考：[Flutter macOS 发布](https://docs.flutter.dev/deployment/macos)、[Flutter macOS 平台视图](https://docs.flutter.dev/platform-integration/macos/platform-views)、[Apple macOS 分发](https://developer.apple.com/macos/distribution/)。
