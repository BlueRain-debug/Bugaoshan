import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/utils/app_log.dart';

Future<void> openLocalFile(String path, {required BuildContext context}) async {
  if (!context.mounted) return;
  try {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw PlatformException(
        code: 'OPEN_FILE_FAILED',
        message: result.message,
      );
    }
  } catch (error) {
    AppLog.e('OpenFile', 'File handoff failed: $error');
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.open}: ${l10n.operationFailed}')),
      );
    }
  }
}
