import 'package:shared_preferences/shared_preferences.dart';

/// 鸿蒙不恢复桌面窗口位置和大小，也不注册桌面窗口监听器。
class WindowStateService {
  WindowStateService(SharedPreferences prefs);

  static Future<WindowStateService> create(SharedPreferences prefs) async =>
      WindowStateService(prefs);

  void dispose() {}
}
