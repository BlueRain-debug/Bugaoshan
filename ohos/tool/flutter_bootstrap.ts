import fs from 'fs';
import path from 'path';
import { spawnSync } from 'child_process';
import { hvigor } from '@ohos/hvigor';

type PythonCommand = {
  command: string;
  prefixArgs: string[];
};

function runtimePython(nativeProject: string): string | undefined {
  const runtimePath = path.join(nativeProject, '.flutter-runtime.json');
  if (!fs.existsSync(runtimePath)) {
    return undefined;
  }
  try {
    const runtime = JSON.parse(fs.readFileSync(runtimePath, 'utf8'));
    return typeof runtime.python === 'string' && runtime.python.length > 0
      ? runtime.python
      : undefined;
  } catch (_) {
    return undefined;
  }
}

function findPython(nativeProject: string): PythonCommand {
  const candidates: PythonCommand[] = [];
  const configured = runtimePython(nativeProject);
  if (configured) {
    candidates.push({ command: configured, prefixArgs: [] });
  }
  const environmentPython = process.env.PYTHON;
  if (environmentPython) {
    candidates.push({ command: environmentPython, prefixArgs: [] });
  }
  if (process.platform === 'win32') {
    candidates.push(
      { command: 'python', prefixArgs: [] },
      { command: 'py', prefixArgs: ['-3'] },
      { command: 'python3', prefixArgs: [] },
    );
  } else {
    candidates.push(
      { command: 'python3', prefixArgs: [] },
      { command: 'python', prefixArgs: [] },
    );
  }
  for (const candidate of candidates) {
    const result = spawnSync(
      candidate.command,
      [
        ...candidate.prefixArgs,
        '-c',
        'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)',
      ],
      { stdio: 'ignore', windowsHide: true },
    );
    if (!result.error && result.status === 0) {
      return candidate;
    }
  }
  throw new Error(
    'DevEco Sync 找不到 Python 3。请将 Python 3.10+ 加入系统 PATH，或设置 PYTHON 环境变量。',
  );
}

function runBootstrap(nativeProject: string): void {
  const python = findPython(nativeProject);
  const helper = path.join(nativeProject, 'tool', 'ohos_native.py');
  const result = spawnSync(
    python.command,
    [...python.prefixArgs, helper, '--bootstrap'],
    { cwd: nativeProject, stdio: 'inherit', windowsHide: true },
  );
  if (result.error || result.status !== 0) {
    throw new Error(
      `DevEco Sync 初始化 Flutter OH 失败：${result.error?.message ?? result.status}，请查看上方日志。`,
    );
  }
}

function relativePath(basePath: string, filePath: string): string {
  let result = path.relative(basePath, filePath);
  const absolute = path.isAbsolute(result);
  result = result.replaceAll('\\', '/');
  if (
    !absolute &&
    result !== '.' &&
    !result.startsWith('./') &&
    !result.startsWith('../')
  ) {
    result = './' + result;
  }
  return result;
}

function injectResolvedPlugins(nativeProject: string): void {
  const workspace = path.join(nativeProject, '.flutter-workspace');
  const dependenciesPath = path.join(workspace, '.flutter-plugins-dependencies');
  if (!fs.existsSync(dependenciesPath)) {
    throw new Error(`鸿蒙 Flutter 插件清单不存在：${dependenciesPath}`);
  }
  const dependencies = JSON.parse(fs.readFileSync(dependenciesPath, 'utf8'));
  const plugins = dependencies?.plugins?.ohos;
  if (!Array.isArray(plugins)) {
    throw new Error('鸿蒙 Flutter 插件清单缺少 plugins.ohos。');
  }
  const config = hvigor.getHvigorConfig();
  plugins
    .filter(plugin => plugin.native_build !== false)
    .forEach(plugin => {
      if (typeof plugin.name !== 'string' || typeof plugin.path !== 'string') {
        throw new Error('鸿蒙 Flutter 插件清单包含无效条目。');
      }
      config.includeNode(
        plugin.name,
        relativePath(nativeProject, path.join(plugin.path, 'ohos')),
      );
    });
}

export function bootstrapFlutterModules(nativeProject: string): void {
  runBootstrap(nativeProject);
  injectResolvedPlugins(nativeProject);
}
