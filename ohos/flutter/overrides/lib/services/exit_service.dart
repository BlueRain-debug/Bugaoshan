import 'dart:io';

class ExitService {
  /// 保留移动端退出前的保存等待，不依赖桌面窗口插件。
  Future<void> exitApp() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}
