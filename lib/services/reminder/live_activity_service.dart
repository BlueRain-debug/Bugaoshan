import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// MARK: - 异常体系定义

/// 实时活动相关的基类异常。
sealed class LiveActivityException implements Exception {
  const LiveActivityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 当前系统或设备不支持实时活动（非 iOS 平台、版本低于 iOS 16.1 等）。
class LiveActivityUnsupportedException extends LiveActivityException {
  const LiveActivityUnsupportedException([
    super.message = '当前系统或设备不支持实时活动（需 iOS 16.1+）',
  ]);
}

/// 用户在系统设置中禁用了实时活动权限。
class LiveActivityNotAuthorizedException extends LiveActivityException {
  const LiveActivityNotAuthorizedException([
    super.message = '用户未在系统设置中开启实时活动权限',
  ]);
}

/// 尝试在后台启动实时活动（违反系统必须在前台调用的硬约束）。
class LiveActivityForegroundRequiredException extends LiveActivityException {
  const LiveActivityForegroundRequiredException([
    super.message = '实时活动只能在应用处于前台活跃状态时启动',
  ]);
}

/// 当前没有活跃的实时活动可更新。
class LiveActivityNoActiveSessionException extends LiveActivityException {
  const LiveActivityNoActiveSessionException([super.message = '当前没有活跃中的实时活动']);
}

/// 原生操作执行失败（如系统抛错）。
class LiveActivityOperationException extends LiveActivityException {
  const LiveActivityOperationException(
    super.message, {
    this.code,
    this.details,
  });

  final String? code;
  final dynamic details;

  @override
  String toString() {
    if (code != null) {
      return '$message (code: $code)';
    }
    return message;
  }
}

// MARK: - 服务实现

/// 灵动岛与锁屏 Live Activity 服务。
///
/// 遵循设计约束（详见 issue #358）：
/// - 纯通信服务，无持久化依赖，可独立单测与构造；
/// - 失败时区分「不支持」「未授权」「非前台」「无活跃活动」「操作失败」，不吞异常；
/// - 倒计时依赖系统自带的自更新视图，无需频繁下发 `update`。
class LiveActivityService {
  LiveActivityService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bugaoshan/live_activity');

  final MethodChannel _channel;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 检测当前设备与系统是否支持并启用了实时活动（iOS 16.1+ 且开关打开）。
  Future<bool> isSupported() async {
    if (!_isIos) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 在前台启动一节课程的 Live Activity。
  ///
  /// - [courseName] 当前课程名
  /// - [location] 教室位置
  /// - [endAt] 下课时间
  /// - [startAt] 上课时间（默认当前时刻）
  /// - [nextCourseName] 下一节课程名（若有）
  /// - [nextLocation] 下一节课教室（若有）
  ///
  /// 成功时返回原生返回的 Activity ID。
  ///
  /// 抛出：
  /// - [LiveActivityUnsupportedException] 平台不支持
  /// - [LiveActivityForegroundRequiredException] 应用不在前台
  /// - [LiveActivityNotAuthorizedException] 用户在系统设置关闭权限
  /// - [LiveActivityOperationException] 原生层创建失败
  Future<String?> start({
    required String courseName,
    required String location,
    required DateTime endAt,
    DateTime? startAt,
    String? nextCourseName,
    String? nextLocation,
  }) async {
    if (!_isIos) {
      throw const LiveActivityUnsupportedException('实时活动仅在 iOS 平台受支持');
    }

    try {
      final activityId = await _channel.invokeMethod<String>('start', {
        'courseName': courseName,
        'location': location,
        'endAtMillis': endAt.millisecondsSinceEpoch,
        if (startAt != null) 'startAtMillis': startAt.millisecondsSinceEpoch,
        'nextCourseName': ?nextCourseName,
        'nextLocation': ?nextLocation,
      });
      return activityId;
    } on MissingPluginException {
      throw const LiveActivityUnsupportedException('原生未提供 Live Activity 通道');
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'UNSUPPORTED_PLATFORM':
          throw LiveActivityUnsupportedException(e.message ?? '当前平台不支持实时活动');
        case 'NOT_IN_FOREGROUND':
          throw LiveActivityForegroundRequiredException(
            e.message ?? '实时活动必须在前台启动',
          );
        case 'NOT_AUTHORIZED':
          throw LiveActivityNotAuthorizedException(
            e.message ?? '系统设置未启用实时活动权限',
          );
        default:
          throw LiveActivityOperationException(
            e.message ?? '启动实时活动失败',
            code: e.code,
            details: e.details,
          );
      }
    }
  }

  /// 更新进行中的 Live Activity 状态。
  ///
  /// 抛出：
  /// - [LiveActivityUnsupportedException] 平台不支持
  /// - [LiveActivityNoActiveSessionException] 无活跃活动可更新
  /// - [LiveActivityOperationException] 原生更新失败
  Future<void> update({
    String? courseName,
    String? location,
    DateTime? endAt,
    DateTime? startAt,
    String? nextCourseName,
    String? nextLocation,
  }) async {
    if (!_isIos) {
      throw const LiveActivityUnsupportedException('实时活动仅在 iOS 平台受支持');
    }

    try {
      await _channel.invokeMethod<void>('update', {
        'courseName': ?courseName,
        'location': ?location,
        if (endAt != null) 'endAtMillis': endAt.millisecondsSinceEpoch,
        if (startAt != null) 'startAtMillis': startAt.millisecondsSinceEpoch,
        'nextCourseName': ?nextCourseName,
        'nextLocation': ?nextLocation,
      });
    } on MissingPluginException {
      throw const LiveActivityUnsupportedException('原生未提供 Live Activity 通道');
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'UNSUPPORTED_PLATFORM':
          throw LiveActivityUnsupportedException(e.message ?? '当前平台不支持实时活动');
        case 'NO_ACTIVE_ACTIVITY':
          throw LiveActivityNoActiveSessionException(
            e.message ?? '没有进行中的实时活动可更新',
          );
        default:
          throw LiveActivityOperationException(
            e.message ?? '更新实时活动失败',
            code: e.code,
            details: e.details,
          );
      }
    }
  }

  /// 结束所有进行中的 Live Activity。
  ///
  /// 若当前平台不支持，静默返回无操作。
  Future<void> end() async {
    if (!_isIos) return;

    try {
      await _channel.invokeMethod<void>('end');
    } on MissingPluginException {
      // 结束时若通道未接线，作为安全兜底静默处理
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED_PLATFORM') return;
      throw LiveActivityOperationException(
        e.message ?? '结束实时活动失败',
        code: e.code,
        details: e.details,
      );
    }
  }
}
