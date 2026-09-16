import fs from 'fs';
import path from 'path';
import { spawnSync } from 'child_process';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

/** Runs after flutterHvigorPlugin selects the mode/architecture's SDK HAR. */
export function flutterEmbeddingPlugin(nativeProject: string): HvigorPlugin {
  return {
    pluginId: 'bugaoshan-flutter-embedding',
    apply(rootNode: HvigorNode) {
      rootNode.afterNodeEvaluate(() => {
        const context = rootNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
        const overrides = context.getOverrides() ?? {};
        const selected = overrides['@ohos/flutter_ohos'];
        if (typeof selected !== 'string' || !selected.startsWith('file:')) {
          throw new Error('Flutter 未选择嵌入层 HAR；请检查 Hvigor 插件顺序。');
        }
        const runtimePath = path.join(nativeProject, '.flutter-embedding-runtime.json');
        if (!fs.existsSync(runtimePath)) {
          throw new Error('Flutter OH 尚未初始化，请先在 DevEco 中执行 Sync。');
        }
        const runtime = JSON.parse(fs.readFileSync(runtimePath, 'utf8'));
        if (runtime.schemaVersion !== 1 || typeof runtime.python !== 'string' || !runtime.python) {
          throw new Error('鸿蒙副本缺少有效的 Python 运行配置。');
        }
        const source = path.resolve(nativeProject, selected.slice('file:'.length));
        const result = spawnSync(runtime.python, [
          path.join(nativeProject, 'tool', 'ohos_embedding.py'),
          '--source', source,
          '--workspace', runtime.workspace,
          '--native-project', nativeProject,
        ], { encoding: 'utf8', windowsHide: true, timeout: 60000 });
        if (result.error || result.status !== 0) {
          throw new Error(`准备 Flutter 嵌入层失败：${result.error?.message || result.stderr || result.stdout || result.status}`);
        }
        const artifact = JSON.parse(result.stdout).archive;
        if (typeof artifact !== 'string' || !fs.existsSync(artifact)) {
          throw new Error('嵌入层补丁没有返回有效的 HAR。');
        }
        overrides['@ohos/flutter_ohos'] = `file:${artifact}`;
        context.setOverrides(overrides);
        console.info(`Flutter 嵌入层：使用本地主题更新补丁 ${path.basename(artifact)}`);
      });
    },
  };
}
