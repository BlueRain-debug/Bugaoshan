import 'dart:typed_data';

import 'package:file_picker_ohos/file_picker_ohos.dart';

/// 保存字节到用户选择的位置；取消时返回 false，失败时抛出异常。
Future<bool> saveFileBytes({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
}) async {
  return await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
      ) !=
      null;
}
