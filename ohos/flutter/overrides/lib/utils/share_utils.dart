import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar, Text;
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/widgets.dart' show BuildContext, View;
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, ShareResultStatus, XFile;

/// share_plus 的 Windows 兼容垫片。
///
/// [fluttercommunity/plus_plugins#3619](https://github.com/fluttercommunity/plus_plugins/issues/3619)
/// 报告 `share_plus ^11.0.0` 的新 API `SharePlus.instance.share(...)` 在
/// Windows 10/11 上无法调起分享面板，根因疑似 Windows 原生层对路径分隔符
/// 的处理（`/` vs `\`）。把路径里的 `/` 全部替换成 `\` 后即可正常工作。
///
/// 其他平台（macOS / Linux / Android / iOS）不受影响，路径原样透传。

/// 把 [path] 在 Windows 上规整成反斜杠形式；其他平台直接返回原值。
String normalizeSharePath(String path) =>
    Platform.isWindows ? path.replaceAll('/', '\\') : path;

XFile _toXFile(String path) => XFile(normalizeSharePath(path));

/// 计算分享面板的弹出锚点。iPad 要求该区域非空且位于当前视图坐标内。
Rect sharePositionOriginForContext(BuildContext context, {Rect? preferred}) {
  if (preferred != null && !preferred.isEmpty) return preferred;

  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      !renderObject.size.isEmpty) {
    final origin = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    if (!origin.isEmpty) return origin;
  }

  final view = View.of(context);
  final logicalSize = view.physicalSize / view.devicePixelRatio;
  return Rect.fromLTWH(logicalSize.width / 2, logicalSize.height / 2, 1, 1);
}

/// 分享单个文件。封装 `SharePlus.instance.share(...)`，自动处理 Windows
/// 路径分隔符问题。
Future<bool> shareSingleFile(
  String path, {
  required BuildContext context,
  String? text,
  Rect? sharePositionOrigin,
}) {
  return _shareFiles(
    [path],
    context: context,
    text: text,
    sharePositionOrigin: sharePositionOrigin,
  );
}

bool _sharing = false;

Future<bool> _shareFiles(
  List<String> paths, {
  required BuildContext context,
  String? text,
  Rect? sharePositionOrigin,
}) async {
  if (!context.mounted || _sharing) return false;
  _sharing = true;
  try {
    if (paths.isEmpty) throw ArgumentError('No files to share');
    for (final path in paths) {
      if (!await File(path).exists()) {
        throw const FileSystemException('Shared file does not exist');
      }
    }
    if (!context.mounted) return false;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [for (final path in paths) _toXFile(path)],
        text: text,
        sharePositionOrigin: sharePositionOriginForContext(
          context,
          preferred: sharePositionOrigin,
        ),
      ),
    );
    // unavailable 表示系统未报告用户选择，不将其误判为插件失败。
    return result.status != ShareResultStatus.dismissed;
  } catch (error) {
    AppLog.e('Share', 'File sharing failed: $error');
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.share}: ${l10n.operationFailed}')),
      );
    }
    return false;
  } finally {
    _sharing = false;
  }
}

/// 分享多个文件。封装 `SharePlus.instance.share(...)`，自动处理 Windows
/// 路径分隔符问题。
Future<bool> shareMultipleFiles(
  List<String> paths, {
  required BuildContext context,
  String? text,
  Rect? sharePositionOrigin,
}) {
  return _shareFiles(
    paths,
    context: context,
    text: text,
    sharePositionOrigin: sharePositionOrigin,
  );
}
