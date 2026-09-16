import 'package:flutter/services.dart';

const _environmentChannel = MethodChannel('bugaoshan/environment_info');

Future<List<String>> getAndroidSupportedAbis() async => const [];

/// OH-only device constants; failure is shown by the developer page.
Future<Map<String, dynamic>> getMobileDeviceInfo() async {
  final info = await _environmentChannel
      .invokeMapMethod<String, String>('getDeviceInfo')
      .timeout(const Duration(seconds: 5));
  if (info == null || info.isEmpty) {
    throw StateError('HarmonyOS returned no device information');
  }
  return info;
}
