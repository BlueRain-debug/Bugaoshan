# 鸿蒙启动后内容加载与开屏配色

2026-09-16：现象为 Release 包主页已出现，随后内容才加载。本记录基于代码阅读；
本轮未执行补丁应用、格式化、分析、测试或 HAP 构建，真机效果待验证。

## 启动阶段

根 `main.dart` 在 `runApp` 之前等待 `ensureBasicDependencies()`，其内部调用
`getIt.allReady()`，包含配置、数据库和认证存储恢复。`CourseProvider` 从已经初始化的
数据库内存缓存读取课表。这些发生在主页显示前，不能直接解释本次“主页出现后”的等待。

主页创建时继续执行自动登录或子系统预热，远端业务结果随后返回。
原有版本检查在鸿蒙因不支持应用内更新而直接返回，并不发起 GitHub 请求；
`0026` 移除了主页这次无效调用。
设置了自定义背景时，图片解码完成后才显示背景；启用 Google Fonts 时字体也可能稍后加载。
这些异步内容更新需要与动画掉帧区分。

确定存在的额外开销是：上游 `AuthScopedIndexedStack` 在 `build()` 中为所有导航项创建页面，
再用 `Offstage` 隐藏非当前项。`Offstage` 仍会挂载和布局子树，各页面会执行初始化，
登录状态跨越认证边界时又会重新创建。自定义导航里加入 WebView 等页面时，影响会更明显。

鸿蒙课表卡片还会在启动期间发起快照同步；原生 `CourseCardStore` 使用同步文件写入及
`fsyncSync`，这是需要真机耗时数据进一步确认的候选因素。本轮未改动卡片同步和存储行为。

## 修改

- [首页适配文件](../../flutter/overrides/lib/widgets/common/auth_scoped_indexed_stack.dart)（原 `0025`）让导航页在首次访问时创建，
  减少隐藏页面的启动初始化。已访问页面保留状态，重排时按页面 ID 识别，移除导航项时回收；
  登录、退出等认证边界变化仍清理全部页面缓存。
- 隐藏页暂停 Flutter ticker 动画，切页动画涉及的当前页和上一页继续运行。
- 原生 `start_window_background` 补充深色资源 `#FF1C1C1E`，浅色沿用 `#FFFFFF`；
  系统启动窗口依照现有模块配置按系统深浅模式选取颜色。
- 原生 `Index` 使用同一背景资源并铺满承载区域，覆盖 Flutter 首帧前的背景。
  开屏仍使用系统动画；配色通过资源限定目录切换，不读取 Flutter 中尚未初始化的设置。

源码适配只应用于鸿蒙隔离副本。网络请求耗时、背景解码和实际掉帧比例尚未测量，
上述修改不代表已经定位并消除了所有启动停顿。

## 清理非鸿蒙启动调用

按用户要求，本次仅清理与鸿蒙无关的路径，由
[启动适配文件](../../flutter/overrides/lib/main.dart)及主题相关覆盖文件维护，
完整范围见 [原 0026 的文件映射](source-overlay-migration.md#0026)：

- 启动入口移除桌面 SQLite FFI、窗口位置恢复、Android 安装包清理及对应 import。
  FFI 和窗口恢复原本已有平台判断，安装包清理原本在非 Android 直接返回，
  此项主要精简入口，不能将它们计为鸿蒙实际发生的磁盘操作。
- 移除没有 OH 实现的 `system_theme` 调用。启动、应用主题、主题预览、设置恢复及
  删除背景时统一使用原来的蓝色回退值；避免仅删除显式 `load()` 后，
  `SystemTheme.accentColor` 的静态初始化再次隐式调用插件。
  系统深浅模式仍由 `ThemeMode.system` 处理。依赖锁文件保持现状，包存在不代表执行插件调用。
- 主页移除自更新检查，以及仅更新 Android/iOS/macOS 小组件的生命周期监听。
  OH 卡片继续由 `OhosCourseCardSync` 接管启动、前台及课表设置变化。
- 从 OH 隔离依赖图排除 `sqflite_common_ffi`，并从 OH 锁文件移除其独占的
  `sqlite3` native-asset 构建链。OH 数据库使用 `sqflite_ohos` 和系统 `relationalStore`。
  已有构建副本、`entry/libs` 和 HAP 属于旧生成物，不能用来验证排除结果，也不能仅凭
  此项认定已经修复 Release 启动故障。

本次保留依赖就绪等待、认证恢复、课表数据库、卡片快照、字体及背景处理。
不以延后业务初始化或改变存储规则换取首屏提前。仍未执行构建、格式化或测试，
需要通过新的隔离副本构建才能应用这些代码；已有副本和 HAP 不会自动更新。

## 待验证

- [ ] 使用 Release 包确认首次进入主页与连续切页的流畅度。
- [ ] 首次打开未访问页能正常加载，返回已访问页保留滚动位置和输入状态。
- [ ] 导航重排、删除、登录、退出与账号切换后页面状态符合现有隔离约定。
- [ ] 系统浅色和深色下冷启动，开屏背景及原生承载区域配色正确。
- [ ] 后台切换系统主题再返回应用，页面和 WebView 正常显示。
- [ ] 冷启动、系统主题色预览、恢复主题及删除背景不再触发 `system_theme` 通道；自定义配色与系统深浅切换正常。
- [ ] 从后台返回及修改课表后，鸿蒙服务卡片继续正常同步。

自动化回归入口见 [测试说明](../../tests/README.md)。本次变更发生在首次 19 批提交完成后，
不修改此前提交清单和验证记录。

## Debug / Release 启动差异审计

2026-09-17 用户确认 Release 在 API 26 设备上同样闪退，因此最低 API 20 兼容路径不是
该现象的必要条件。用户已经确认签名无关，本节不再把签名状态列为故障原因或诊断依据。
本轮仅检查已有构建日志、源码和产物，没有运行构建、测试或真机操作。

### 官方开发规范

- [UIAbility 生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-lifecycle)
  规定前台启动依次触发 `onCreate()`、`onWindowStageCreate()`、`onForeground()`；生命周期
  回调运行在主线程，只应执行必要的轻量操作。当前 `EntryAbility` 没有在这些回调中增加
  Release 专属耗时任务，Flutter 基类负责窗口和引擎初始化。
- [NDK 开发导读](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ndk-development-overview)
  说明 HarmonyOS 标准 C 库基于 musl；
  [NDK 工程构建概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/build-with-ndk-overview)
  要求通过 `hmos.toolchain.cmake` 生成符合 HarmonyOS ABI 的目标文件；
  [三方动态链接库集成](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/integrate-third-party-dlls)
  要求按目标架构放入 `entry/libs/<ABI>` 并链接对应产物。旧 `libsqlite3.so` 依赖
  Linux/glibc 的 `libc.so.6` 和 `ld-linux-aarch64.so.1`，不符合这组要求，已经从 OH
  隔离依赖图排除。
- [ArkGuard 混淆开启指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/source-obfuscation-guide)
  说明 DevEco Studio 5.0.3.600 及以后新建工程默认关闭源码混淆；混淆只对 Release 生效，
  是否由混淆引发差异应通过开关判断。当前工程没有启用 `arkOptions.obfuscation`，Flutter
  embedding 和引擎 HAR 元数据均为 `obfuscated: false`，Release 缓存也没有名称映射产物，
  因此没有证据把本次闪退归因于 ArkGuard。
- [崩溃事件介绍](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hiappevent-watcher-crash-events)
  将未处理 Native 信号归为 `NativeCrash`，将未处理 ArkTS/JS 异常归为 `JsError`。
  [JS Crash 分析方法](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-stability-app-crash-js-way)
  要求结合异常信息、`StackTrace` 和 Source Map 定位；
  [CppCrash 分析方法](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-stability-app-crash-cpp-way)
  指明 DevEco FaultLog 从 `/data/log/faultlog/faultlogger/` 收集故障日志，Release 栈需要与
  同版本符号匹配。SIGABRT 还应按
  [官方说明](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-stability-cppcrash-sigabrt-fault-mode)
  优先检查 `LastFatalMessage`。

### 现有产物与源码证据

- 02:03 至 02:05 的历史日志明确以 `buildMode=release` 构建。对应补丁 embedding HAR 的
  `BUILD_MODE_NAME` 为 `release`、`DEBUG=false`，Release ArkTS 编译缓存也保留了相同值。
  Flutter loader 因而走 AOT 分支，将 `libapp.so` 作为 `aot-shared-library-name`；同一轮
  日志记录了 Release `libflutter.so` 和 ARM64/x86_64 `libapp.so` 进入打包目录，最后
  `BUILD SUCCESSFUL`。没有证据表明当时混入 Debug embedding 或 Debug 引擎。
- Release ARM64 `app.so` 是 AArch64 共享对象，包含 VM 与 isolate 的 data/instructions
  四项 AOT snapshot 导出，动态段没有 `NEEDED` 依赖。未发现缺少 AOT 入口或依赖 glibc。
- 当前 `entry-default-unsigned.hap`、`entry/oh-package-lock.json5` 和 `oh_modules` 已被 10:23
  的后续 Debug 构建覆盖：当前 HAP 含 `kernel_blob.bin` 和 snapshot 数据，不含 `libapp.so`。
  它不能代表 02:05 安装测试的 Release HAP，也不能用于反推该 Release 包的运行内容。
- 应用没有 `kReleaseMode` 分支。`kDebugMode` 只改变日志输出和首次 EULA/向导默认值；
  Release 首次启动会显示 EULA，源码中唯一相关的 `exit(0)` 需要用户点击“不同意”，
  没有自动退出路径。
- 生成的插件注册器整体使用 `try/catch`，注册列表只有 `sqflite_ohos`，没有
  `sqflite_common_ffi`。旧 HAP 和 `entry/libs` 中的 glibc SQLite 库是确定的打包违规项，
  但当前入口没有显式加载它的路径，静态证据不能证明它在启动时实际进入动态链接过程。
- 锁定的 Flutter embedding 在 `onCreate()` 注册全局未处理异常监听器；收到 ArkTS 未处理
  异常后原本会调用 `appRecovery.saveAppState()` 和 `appRecovery.restartApp()`，使一次启动
  异常表现为退出或反复重启。当前 embedding 补丁保留 `errorManager` 观测器与错误日志，
  只移除状态保存和主动重启；官方 API 说明观测器捕获异常时进程不会退出，因此后续构建
  不会再由该回调触发重启循环。监听器在 Debug 与 Release 都存在，这项修复仍不能证明
  最初异常来源。
- HAP 同时声明 x86_64 Flutter/AOT 库，但 WebView 原生库只构建 ARM64；这会阻断
  x86_64 环境，不能解释同一 ARM64 API 26 真机上的 Debug/Release 差异。

后续两份同设备 Release NativeCrash 已提供运行阶段证据。最低 API、签名、ArkGuard、AOT
入口、Debug/Release HAR 混用、glibc SQLite 打包和 embedding 自动恢复都不是这次主线程
非法跳转的直接原因。glibc SQLite 排除与异常重启处理仍是有效的独立修复。

## Release NativeCrash 定位

2026-09-17 11:29 的 MatePad Mini Release 故障在启动 3 秒后触发
`SIGSEGV(SEGV_MAPERR)`。故障线程是进程主线程，`#01` 至 `#31` 位于 AOT
`libapp.so`，之后进入 `libflutter.so`。进程映射只包含系统 `libsqlite.z.so`，没有加载此前
误打包的 `libsqlite3.so`。

移除 `sqflite_ohos` worker 后，12:48 的新包不再出现 `SqfliteWorker`、
`Observed is not defined` 或 RDB schema 迁移日志，但仍在相同 AOT 偏移崩溃。新包的
`libapp.so` Build ID 为 `e0344fe19d5aef890e4f83396f3e5676`；这次结果证伪了 SQLite
worker 是 NativeCrash 原因的假设。保留主线程调度补丁仍可避免已观察到的 ArkTS worker
错误，但不能作为本次 SIGSEGV 的修复依据。

两份故障报告都指向同一个被截断的 Flutter 原生函数地址：

- `libapp.so+0x4ca5c8` 的指令是 `blr x9`；崩溃时 `x9` 与故障地址相同；
- 12:48 的故障地址为 `0xffffffffb4f64728`。恢复被丢失的高 32 位后是
  `0x5bb4f64728`；减去该进程中 `libflutter.so` 基址 `0x5bb4300000`，固定偏移为
  `0xc64728`；
- 11:29 的故障地址为 `0xffffffffb5264728`，对应当次 `libflutter.so` 基址
  `0x5bb4600000`，恢复后仍是 `libflutter.so+0xc64728`；
- `libflutter.so+0xc64728` 是有效函数入口，反汇编行为与
  `PlatformConfigurationNativeApi::GetRootIsolateToken` 一致；寄存器还保留了
  `RootIsolateToken` 的分段 ASCII 内容。

因此，锁定工具链的 Release AOT native resolver 返回了有效的 64 位函数指针，但调用前只
保留低 32 位并进行了符号扩展，最终跳转到未映射地址。Debug 使用不同执行路径，所以没有
复现。Flutter framework 的首个触发点是 `platform_channel.dart` 中
`_findBinaryMessenger()` 读取 `ServicesBinding.rootIsolateToken`；应用及解析后的依赖没有
其他显式读取，唯一 `compute()` 也不在后台 isolate 使用平台通道。

[framework 补丁](../../flutter/patches/framework/root-isolate-token.patch)让鸿蒙构建直接使用
根 `ServicesBinding.defaultBinaryMessenger`，从而不再调用损坏的 native getter。构建脚本
把锁定 SDK 的 Flutter package 复制到忽略的工作目录，校验 framework 提交和源文件哈希后
应用补丁，再改写工作区 `package_config.json`；本机 SDK 保持只读。代价是该鸿蒙构建不支持
后台 isolate 平台通道，当前应用没有这种用法。

同一轮日志还确认了两个独立启动缺陷：

- `EntryAbility.ets` 的旧 `@ohos.app.ability.Want` 导入在 API 26 上无法加载；入口和卡片
  Ability 已统一迁移到 `@kit.AbilityKit`；
- 默认引擎已由 `createAndRunEngineByOptions()` 执行 Dart 入口，随后
  `onWindowStageCreate()` 又重复执行，产生 `Attempted to run a DartExecutor that is already
  running`。embedding 补丁现先检查 DartExecutor 的实际状态，仅在尚未运行时执行入口。

修复后的 Release 包仍需在同一设备冷启动验证。验收重点是主线程不再访问
`libflutter.so+0xc64728` 对应的截断地址、首屏平台通道正常工作，并确认没有旧 Want 模块
加载错误和 DartExecutor 重复执行日志。
