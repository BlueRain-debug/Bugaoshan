import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 原样保存图片文件，由系统保存弹窗授权；取消时不显示成功提示。
Future<bool> saveImageBytesToGallery(Uint8List bytes) async {
  final extension = _imageExtension(bytes);
  final temporaryRoot = await getTemporaryDirectory();
  final directory = await temporaryRoot.createTemp('gallery-');
  try {
    final file = File('${directory.path}/image.$extension');
    await file.writeAsBytes(bytes, flush: true);
    final result = await ImageGallerySaverPlus.saveFile(file.path);
    if (result is Map && result['isSuccess'] == true) return true;
    if (result is Map && result['message'] == 'user refuses permission') {
      return false;
    }
    throw PlatformException(
      code: 'GALLERY_SAVE_FAILED',
      message: result is Map ? result['message']?.toString() : null,
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

String _imageExtension(Uint8List bytes) {
  bool startsWith(List<int> signature) =>
      bytes.length >= signature.length &&
      List.generate(
        signature.length,
        (i) => bytes[i] == signature[i],
      ).every((matches) => matches);

  if (startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'png';
  }
  if (startsWith([0xff, 0xd8, 0xff])) return 'jpg';
  if (startsWith(ascii.encode('GIF87a')) ||
      startsWith(ascii.encode('GIF89a'))) {
    return 'gif';
  }
  if (bytes.length >= 12 &&
      startsWith(ascii.encode('RIFF')) &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'webp';
  }
  if (startsWith([0x42, 0x4d])) return 'bmp';
  throw const FormatException('Unsupported image format');
}
