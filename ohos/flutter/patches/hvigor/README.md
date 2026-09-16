# Flutter OH Hvigor 路径适配

锁定的 SDK Hvigor 插件默认从 `Flutter包/ohos/local.properties` 读取 SDK 和版本。
本项目的 Flutter 包位于 `ohos/.flutter-workspace/`，原生工程直接使用仓库 `ohos/`，
因此需要显式传递两个路径，工作目录中不创建第二份原生工程。

[manifest.json](manifest.json) 保存锁定 SDK 的七个 Hvigor 工具文件哈希及精确替换规则。
准备入口核对 framework 提交、全部输入哈希和替换次数后，将适配结果保存到本地
`.flutter-workspace/tooling/flutter-hvigor-plugin/`，不修改 SDK 安装目录。
这几个工具文件的本地副本不属于应用 Dart 源码，也不是另一个原生工程。

适配增加两个参数：显式原生工程路径、Flutter assemble 执行回调。
SDK 仍负责按模式和架构选择引擎 HAR、注入依赖、注册编译任务，以及把 Flutter 资源和 AOT
复制到实际 `entry/`。执行回调通过 Python 参数数组调用 Flutter，保留带空格的路径与参数。
`injectNativeModules` 原本就支持分开的路径，其逻辑不变。

根 Hvigor 文件通过 `ohos/tool/flutter_project.ts` 接入适配层。
Sync/Build 配置阶段先刷新源码链接、合并翻译和生成代码，再使用独立 OH Pub 解析结果。
依赖或工具链配置变化时要求重新执行 `--prepare-only`，不自动采用根工程的解析结果。
无需安装 SDK 工具目录中的旧 Hvigor 开发依赖；使用当前 DevEco 提供的 Hvigor。

升级 Flutter OH SDK 时，需要重新审查路径假设、任务依赖和复制流程，更新哈希及替换规则。
本次接入的构建与真机验证由维护者执行，尚无新入口通过验证的记录。
