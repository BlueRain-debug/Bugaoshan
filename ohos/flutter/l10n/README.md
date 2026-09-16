# 鸿蒙翻译条目

`app_en.arb`、`app_zh.arb` 只保存鸿蒙新增或替换的条目，不复制整份上游翻译。
组装时先读取根 `lib/l10n/` 的对应 ARB，再按键合并本目录内容，因此上游无关文案可直接更新。
`app_zh_Hans_CN.arb` 继续由上游维护；生成的本地化 Dart 文件交给副本的 `flutter gen-l10n`。

每个键都需要在 [源码清单](../source-manifest.json) 的 `localizations[].entries` 登记基线：
上游不存在时为 `null`；替换既有文案时为原 JSON 值的 SHA-256（UTF-8、键排序、紧凑 JSON）。
条目元数据 `@key` 如需适配也要一并维护和登记。
上游新增同名键、修改被覆盖值、清单遗漏条目或 JSON 出现重复键都会阻止组装。

使用 `python ohos/tool/ohos_sources.py --check` 检查；冲突时先合并文案和占位符定义，
再记录输出的当前哈希。现有迁移为每种语言 8 项：7 项新增、1 项替换。
