# Flutter OH 嵌入层补丁

## Dart 入口执行

锁定 embedding 通过 `FlutterEngineGroup.createAndRunEngineByOptions()` 创建默认引擎时已经执行
Dart 入口，但 `onWindowStageCreate()` 随后又无条件调用 `doInitialFlutterViewRun()`，设备日志因此
出现 `Attempted to run a DartExecutor that is already running`。补丁先读取 DartExecutor 的实际
运行状态，仅在入口尚未执行时启动；默认、缓存或宿主引擎已经运行时都不会重复执行。

## 主题切换

系统切换深浅色时，锁定的 Flutter OH 嵌入层在
`FlutterAbilityAndEntryDelegate.changeColorMode()` 对平台节点调用 `rebuild()`。
`EmbeddingNodeController.makeNode()` 会重新创建 BuilderNode；CPF WebView 的
`aboutToDisappear()` 又会释放 Web 资源，可能造成文档重新加载或控制器失效。

`ohos/flutter/patches/embedding/color-mode-update.patch` 将该主题分支改为对已有 BuilderNode 调用
`updateConfiguration()`。API 从 12 起可用，当前工具链为 API 26。
它传递当前系统配置并更新已有节点，不走 `makeNode()` 的新建流程。
平台视图尺寸、方向和渲染表面的其他重建入口保持原逻辑。

WebView 内部另持有一个 BuilderNode，因此还需
[`webview-configuration-update.patch`](../plugins/webview-configuration-update.patch)：
外层组件的 `onWillApplyTheme()` 将配置更新传给已有的 WebBuilderNode。
三个通知页的 `WebDarkMode.Auto` 和上游深浅媒体查询继续负责网页配色，
不新增 JS 配色、reload 或加载遮罩处理。

## 未处理的 ArkTS 异常

锁定的 Flutter OH `FlutterAbility.onCreate()` 注册了进程级 `errorManager` 观测器，
但回调在记录异常后会调用 `appRecovery.saveAppState()` 和 `restartApp()`。
启动期间只要出现一次未处理的 ArkTS 异常，应用就会被主动重启，并可能重复进入同一路径。

[HarmonyOS `errorManager.on('error')` API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-errormanager)
说明，观测器捕获异常时应用进程不会退出。补丁保留进程级观测器、错误日志以及
`onDestroy()` 中的注销，只移除应用状态保存和主动重启。这样异常仍可通过 HiLog 和系统
`JsError` 信息定位，同时不会被 embedding 转换成自动重启循环。

该改动修复的是异常后的恢复行为，不代表已经定位或修复触发异常的业务代码。若 Release
启动仍出现页面未完成初始化，应以同一构建产物的 `onUnhandledException` 日志和 `JsError`
调用栈继续定位首个异常。

## 构建接入

1. `build_ohos.py` 在仓库 `ohos/.flutter-embedding-runtime.json` 记录本次
   Python 解释器、Git 程序与工程路径。该文件仅为本机生成物，不提交；下次准备时更新。
   位置避开 Hvigor Clean 的输出目录，DevEco 后续构建可复用当前环境。
2. `flutterHvigorPlugin` 按 SDK、目标架构和构建模式选择原始嵌入层 HAR。
3. 排在它之后的 `flutterEmbeddingPlugin` 读取选定的 override，调用
   `ohos_embedding.py`。脚本只读取 SDK HAR，校验包名、版本、锁定引擎提交和
   待改文件的 SHA-256，在副本的临时目录应用补丁，再打包新 HAR。
4. 新 HAR 位于 `ohos/.flutter-workspace/build/flutter-embedding/`，
   位于 Flutter 工作目录内、原生 `ohos/build/` 外，避免被 Hvigor Clean 删除输入包。
   文件名包含 SDK HAR、清单、补丁及应用脚本的内容摘要；内容变化会更换依赖 URL，
   防止 OHPM 继续选用旧的输入。所有模块通过同一个 override 使用它。
5. SDK 安装目录和 SDK 原始 HAR 不写入补丁，不另行编译或更换引擎二进制。
   插件源码补丁仍由既有流程应用到鸿蒙专用 Pub 缓存。

`--prepare-only` 记录运行配置、准备插件依赖及生成代码；实际选择和修改 HAR 发生在 Hvigor
配置阶段，覆盖命令行和 DevEco 构建。更新脚本、SDK 或补丁后，
需要重新运行准备入口。脚本向嵌入层工具分别传入根原生工程和 Flutter 工作目录，
DevEco 和命令行构建均使用同一接入。

## 维护和验收

[manifest.json](manifest.json) 固定目标包、引擎提交以及主题和异常处理源文件的哈希。
升级 SDK 时，应核对所用架构及 debug/profile/release 模式的 HAR，重新审查源码、补丁和哈希，
保持版本匹配检查有效。

真机回归应覆盖网页加载前后切换主题、连续切换、前后台切换及旋转或尺寸变化，
并检查通知页、志愿四川和验证码窗口的内容、滚动位置及交互。
修复背景与已有验证记录见 [第四阶段说明](../../../docs/phases/phase4.md)。
