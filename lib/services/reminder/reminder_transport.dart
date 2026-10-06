import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 排期计划的投递通道。把「原生怎么排」与「计划怎么算」隔开，
/// 使 [ReminderService] 可以对着一个可替换的接口测试。
abstract class ReminderTransport {
  /// 全量替换为 [plan]（I2）：计划里没有的 id 必须被撤销。
  Future<void> syncPlan(ReminderPlan plan);

  /// 撤销全部已排期提醒（I4：总开关关闭时调用）。
  Future<void> cancelAll();

  /// 请求系统通知权限，返回是否已获得。
  ///
  /// [provisional] 为 true 时走「安静投递」——不弹授权框，通知只进通知中心
  /// （仅 iOS 支持，Android 忽略该参数）。用于「先让用户看到价值再要授权」的场景。
  Future<bool> requestAuthorization({bool provisional = false});

  /// 查询当前授权状态。返回值与原生状态字符串一一对应
  /// （`authorized` / `provisional` / `denied` / `notDetermined` / `unknown`）。
  Future<String> getPermissionStatus();

  /// 系统当前实际登记的提醒条数。
  ///
  /// 与下发的 `plan.reminders.length` 之差就是被系统丢掉的部分（未授权、超上限、
  /// 时刻已过）。排期类问题几乎都出在这个差值上，所以它必须可观测。
  Future<int> getPendingCount();

  /// 打开本应用的系统通知设置页。
  ///
  /// 用途：权限被拒后系统不再弹授权框，唯一出路是让用户自己去设置里开。
  /// 返回是否成功跳转。
  Future<bool> openNotificationSettings();
}

/// 跨平台的 MethodChannel 实现。
///
/// 平台差异只体现在方法名上，Dart 侧不判断「当前能不能投递」——原生侧不支持时
/// 应回一个 `UNSUPPORTED_PLATFORM` 错误，由这里统一收敛成 no-op 并记日志。
class MethodChannelReminderTransport implements ReminderTransport {
  static const MethodChannel _channel = MethodChannel('bugaoshan/reminder');

  const MethodChannelReminderTransport();

  @override
  Future<void> syncPlan(ReminderPlan plan) async {
    try {
      await _channel.invokeMethod<void>('syncPlan', plan.toChannelPayload());
    } on MissingPluginException {
      throw const ReminderTransportUnavailable();
    } on PlatformException catch (e) {
      if (e.code == unsupportedPlatformCode) {
        throw const ReminderTransportUnavailable();
      }
      if (e.code == notAuthorizedCode) {
        throw const ReminderPermissionDenied();
      }
      rethrow;
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      throw const ReminderTransportUnavailable();
    } on PlatformException catch (e) {
      if (e.code == unsupportedPlatformCode) {
        throw const ReminderTransportUnavailable();
      }
      rethrow;
    }
  }

  /// 原生侧在尚未接线或平台不支持时返回的错误码。
  static const String unsupportedPlatformCode = 'UNSUPPORTED_PLATFORM';

  /// 用户尚未授予通知权限时返回的错误码。
  static const String notAuthorizedCode = 'NOT_AUTHORIZED';

  @override
  Future<bool> requestAuthorization({bool provisional = false}) async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestAuthorization',
        {'provisional': provisional},
      );
      return granted ?? false;
    } on MissingPluginException {
      throw const ReminderTransportUnavailable();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> getPermissionStatus() async {
    try {
      final status = await _channel.invokeMethod<String>('getPermissionStatus');
      return status ?? permissionUnknown;
    } on MissingPluginException {
      throw const ReminderTransportUnavailable();
    } on PlatformException {
      return permissionUnknown;
    }
  }

  /// 原生状态无法取得时的兜底值。不假设已授权——假设已授权会让设置页
  /// 显示「已开启」而实际不投递。
  static const String permissionUnknown = 'unknown';

  @override
  Future<int> getPendingCount() async {
    try {
      final count = await _channel.invokeMethod<int>('getPendingCount');
      return count ?? 0;
    } on MissingPluginException {
      throw const ReminderTransportUnavailable();
    } on PlatformException {
      return 0;
    }
  }

  @override
  Future<bool> openNotificationSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// 用户尚未授予通知权限。
///
/// 这是用户可处理的状态，不是程序缺陷：设置页应据此显示「去授权」入口，
/// 日志记 warn 而非 error——否则未授权期间每次重排都会刷一条错误日志。
class ReminderPermissionDenied implements Exception {
  const ReminderPermissionDenied();

  @override
  String toString() => '尚未获得通知权限';
}

/// 原生侧尚未提供投递能力（或该平台不支持）。
///
/// 与「真正的投递失败」区分开：这不是用户能处理的错误，设置页不该据此报警，
/// 但开发者需要能看到——调用方应记 warn 而非 error，且不清空已排期状态。
class ReminderTransportUnavailable implements Exception {
  const ReminderTransportUnavailable();

  @override
  String toString() => '原生侧未提供提醒投递能力（尚未接线或平台不支持）';
}

/// 未实现的平台（Windows / Linux / Web，以及原生尚未接线的阶段）使用的空实现。
///
/// 刻意返回成功而不是抛异常：Dart 侧的排期逻辑应当在所有平台都能跑通并留下
/// 可观测的 [ReminderService.lastPlan]，只是不产生系统通知。
class NoopReminderTransport implements ReminderTransport {
  const NoopReminderTransport();

  @override
  Future<void> syncPlan(ReminderPlan plan) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> requestAuthorization({bool provisional = false}) async => false;

  @override
  Future<String> getPermissionStatus() async =>
      MethodChannelReminderTransport.permissionUnknown;

  @override
  Future<int> getPendingCount() async => 0;

  @override
  Future<bool> openNotificationSettings() async => false;
}

/// 按当前平台选择实现。
///
/// 平台判断集中在这里，Dart 侧的排期与设置逻辑不再散落 `if (Platform.isX)`。
/// Windows / Linux 暂无原生投递实现（见 issue #358 的平台范围决策）。
ReminderTransport createReminderTransport() {
  if (kIsWeb) return const NoopReminderTransport();
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return const MethodChannelReminderTransport();
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return const NoopReminderTransport();
  }
}
