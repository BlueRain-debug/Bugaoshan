import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/utils/app_log.dart';

bool _imagePickerActive = false;

/// 使用系统图库选择器；取消不修改表单，失败通过当前页面提示。
Future<XFile?> pickGalleryImage(BuildContext context) async {
  if (!context.mounted || _imagePickerActive) return null;
  _imagePickerActive = true;
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return null;
    if (!await File(picked.path).exists()) {
      throw const FileSystemException('Selected image is not readable');
    }
    return context.mounted ? picked : null;
  } catch (error) {
    AppLog.e('ImagePicker', 'Gallery selection failed: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.operationFailed)),
      );
    }
    return null;
  } finally {
    _imagePickerActive = false;
  }
}
