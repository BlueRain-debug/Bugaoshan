import fs from 'fs';
import path from 'path';
import { spawnSync } from 'child_process';
import { HvigorNode } from '@ohos/hvigor';
import { flutterHvigorPlugin, injectNativeModules } from '../.flutter-workspace/tooling/flutter-hvigor-plugin';

function readRuntime(nativeProject: string) {
  const workspace = path.join(nativeProject, '.flutter-workspace');
  const runtimePath = path.join(nativeProject, '.flutter-runtime.json');
  if (!fs.existsSync(runtimePath)) {
    throw new Error('请先运行 python ohos/tool/build_ohos.py --prepare-only，再用 DevEco 打开仓库 ohos/。');
  }
  const runtime = JSON.parse(fs.readFileSync(runtimePath, 'utf8'));
  if (runtime.schemaVersion !== 1 || path.resolve(runtime.workspace) !== workspace ||
      path.resolve(runtime.nativeProject) !== nativeProject || typeof runtime.python !== 'string') {
    throw new Error('鸿蒙工作目录配置已失效，请重新执行 --prepare-only。');
  }
  return runtime;
}

function runHelper(nativeProject: string, args: string[]) {
  const runtime = readRuntime(nativeProject);
  const helper = path.join(nativeProject, 'tool', 'ohos_native.py');
  const result = spawnSync(runtime.python, [helper, ...args], {
    cwd: nativeProject, stdio: 'inherit', windowsHide: true,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`鸿蒙 Flutter 准备失败：${result.error?.message ?? result.status}，请查看上方日志。`);
  }
}

// Both Sync and Build use the OH package. Refresh links and generators before
// Hvigor evaluates module dependencies. Unchanged generator inputs are reused.
export function injectFlutterModules(nativeProject: string) {
  runHelper(nativeProject, ['--refresh']);
  injectNativeModules(nativeProject, path.join(nativeProject, '.flutter-workspace'));
}

export function linkedFlutterPlugin(nativeProject: string) {
  const plugin = flutterHvigorPlugin(path.join(nativeProject, '.flutter-workspace'), 0, nativeProject, (args: string[]) => {
    runHelper(nativeProject, ['--assemble', JSON.stringify(args)]);
  });
  return {
    ...plugin,
    apply(node: HvigorNode) {
      // Do not cache preparation globally: a DevEco daemon can reuse this module.
      runHelper(nativeProject, ['--refresh']);
      plugin.apply(node);
    },
  };
}
