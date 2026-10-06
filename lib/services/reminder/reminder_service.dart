import 'dart:async';

import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/providers/course_provider.dart';
import 'package:bugaoshan/services/reminder/reminder_plan_builder.dart';
import 'package:bugaoshan/services/reminder/reminder_transport.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:flutter/foundation.dart';

/// 排期协调器：把课表与设置的变化翻译成「重新算一份计划并下发给原生」。
///
/// 设计约束（详见 issue #358 的 I1–I4）：
/// - 本类与原生之间只有一条通路 [ReminderTransport]，原生不做任何业务推断；
/// - 每次下发都是全量替换，不做增量 diff——增量在「课程被删/改周次」时极易漏撤销；
/// - 计划内容哈希不变时短路，避免每次前台恢复都惊动系统调度器。
///
/// 之所以监听 `CourseProvider` 的 ValueNotifier 而不是复用
/// `CourseProvider.onCoursesChanged`：后者是单值回调，已被 `WidgetUpdateService`
/// 占用（见 injector.dart），再赋一次会静默把桌面小组件的刷新顶掉。
class ReminderService {
  ReminderService({
    required CourseProvider courseProvider,
    required AppConfigProvider appConfig,
    required ReminderTransport transport,
    Duration? debounceDuration,
  }) : _courseProvider = courseProvider,
       _appConfig = appConfig,
       _transport = transport,
       _debounceDuration =
           debounceDuration ?? const Duration(milliseconds: 800);

  final CourseProvider _courseProvider;
  final AppConfigProvider _appConfig;
  final ReminderTransport _transport;
  final Duration _debounceDuration;

  /// 最近一次成功下发的计划，按 planId 短路用。
  String? _lastPushedPlanId;

  /// 最近一次下发的计划，供设置页展示「已排期 N 条」。
  final ValueNotifier<ReminderPlan?> lastPlan = ValueNotifier<ReminderPlan?>(
    null,
  );

  /// 排期失败原因。设置页据此给出可操作的提示，而不是静默失败。
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// 用户尚未授予通知权限（或授权被撤销）。
  ///
  /// 与 [lastError] 分开：这是用户可处理的状态，设置页应显示「去授权」，
  /// 而不是把它当成故障报错。授权后调用 [onPermissionGranted] 立即重排。
  final ValueNotifier<bool> needsPermission = ValueNotifier<bool>(false);

  Timer? _debounceTimer;
  bool _inFlight = false;
  bool _needsRunAgain = false;
  bool _disposed = false;

  /// 挂监听并做一次初始排期。
  Future<void> start() async {
    if (_disposed) return;
    _courseProvider.courses.addListener(_onSourceChanged);
    _courseProvider.scheduleConfig.addListener(_onSourceChanged);
    _appConfig.reminderEnabled.addListener(_onSourceChanged);
    _appConfig.reminderLeadMinutes.addListener(_onSourceChanged);
    _appConfig.reminderQuietStart.addListener(_onSourceChanged);
    _appConfig.reminderQuietEnd.addListener(_onSourceChanged);
    _appConfig.reminderWindowDays.addListener(_onSourceChanged);
    // 隐私开关变化会改变通知正文（锁屏上同样可见），必须重排。
    _appConfig.showLocation.addListener(_onSourceChanged);
    _appConfig.showTeacherName.addListener(_onSourceChanged);
    await reschedule(force: true);
  }

  /// 幂等：重复调用（例如调用方显式释放后又走了一次统一清理）不会再碰已释放的
  /// notifier，否则会抛 `was used after being disposed`。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _courseProvider.courses.removeListener(_onSourceChanged);
    _courseProvider.scheduleConfig.removeListener(_onSourceChanged);
    _appConfig.reminderEnabled.removeListener(_onSourceChanged);
    _appConfig.reminderLeadMinutes.removeListener(_onSourceChanged);
    _appConfig.reminderQuietStart.removeListener(_onSourceChanged);
    _appConfig.reminderQuietEnd.removeListener(_onSourceChanged);
    _appConfig.reminderWindowDays.removeListener(_onSourceChanged);
    _appConfig.showLocation.removeListener(_onSourceChanged);
    _appConfig.showTeacherName.removeListener(_onSourceChanged);
    lastPlan.dispose();
    lastError.dispose();
    needsPermission.dispose();
  }

  void _onSourceChanged() {
    // 用户手动改设置时希望立刻看到效果；程序性变更（导入课表）则会连续触发，
    // 由 debounce 合并成一次。
    unawaited(reschedule());
  }

  /// 重算并下发。同一时刻只跑一次，期间到达的请求合并成一次补跑。
  Future<void> reschedule({bool force = false}) async {
    if (_disposed) return;
    _debounceTimer?.cancel();
    if (!force) {
      _debounceTimer = Timer(_debounceDuration, () => unawaited(_runOnce()));
      return;
    }
    await _runOnce();
  }

  Future<void> _runOnce() async {
    if (_disposed) return;
    if (_inFlight) {
      _needsRunAgain = true;
      return;
    }
    _inFlight = true;
    try {
      do {
        _needsRunAgain = false;
        await _pushOnce();
        // 第一轮执行期间又来了变更，补一轮；补跑期间再来就继续循环。
      } while (_needsRunAgain && !_disposed);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _pushOnce() async {
    final plan = buildPlan(now: DateTime.now());

    // 总开关关闭：清空而非保留。用户关掉提醒后锁屏上还冒出旧提醒是最糟的体验。
    if (!_appConfig.reminderEnabled.value) {
      try {
        await _transport.cancelAll();
        lastPlan.value = plan;
        lastError.value = null;
        _lastPushedPlanId = plan.planId;
      } catch (e, stack) {
        if (e is ReminderTransportUnavailable) {
          AppLog.w('ReminderService', 'cancelAll 跳过：$e');
          lastPlan.value = plan;
          return;
        }
        AppLog.e('ReminderService', 'cancelAll FAILED: $e\n$stack');
        lastError.value = '$e';
      }
      return;
    }

    if (plan.planId == _lastPushedPlanId) {
      lastPlan.value = plan;
      return;
    }

    try {
      await _transport.syncPlan(plan);
      _lastPushedPlanId = plan.planId;
      lastPlan.value = plan;
      lastError.value = null;
      needsPermission.value = false;
      if (plan.droppedCount > 0) {
        AppLog.w(
          'ReminderService',
          '排期被平台上限裁剪 ${plan.droppedCount} 条（原 ${plan.reminders.length + plan.droppedCount} 条）',
        );
      }
    } catch (e, stack) {
      // 失败时不更新 _lastPushedPlanId，下次触发会重试同一份计划。
      //
      // 「未授权」「原生尚未接线」与「真正投递失败」要分开：前两者是用户/开发期
      // 常态，记 warn 且不污染 lastError，否则设置页会对用户无能为力的原因报警。
      if (e is ReminderPermissionDenied) {
        AppLog.w('ReminderService', 'syncPlan 跳过：$e');
        lastPlan.value = plan;
        needsPermission.value = true;
        return;
      }
      if (e is ReminderTransportUnavailable) {
        AppLog.w('ReminderService', 'syncPlan 跳过：$e');
        lastPlan.value = plan;
        return;
      }
      AppLog.e('ReminderService', 'syncPlan FAILED: $e\n$stack');
      lastError.value = '$e';
    }
  }

  /// 按当前课表与设置构建计划。抽成公开方法便于设置页预览与单测。
  ///
  /// [now] 可注入以便测试；生产调用一律用系统时钟。
  ReminderPlan buildPlan({required DateTime now}) => ReminderPlanBuilder.build(
    courses: _courseProvider.courses.value,
    config: _courseProvider.scheduleConfig.value,
    settings: _appConfig.reminderSettings,
    now: now,
  );

  /// 供设置页在用户授权后立即重排（授权状态变化不在监听列表里）。
  Future<void> onPermissionGranted() => reschedule(force: true);

  /// 请求通知权限并在获得后立即重排。
  ///
  /// 返回是否已获得。调用方负责在 false 时给出「去系统设置」的引导——
  /// 被拒绝后系统不会再弹第二次，重复请求只会静默返回 false。
  Future<bool> requestPermission({bool provisional = false}) async {
    try {
      final granted = await _transport.requestAuthorization(
        provisional: provisional,
      );
      if (granted) {
        needsPermission.value = false;
        await reschedule(force: true);
      } else {
        needsPermission.value = true;
      }
      return granted;
    } on ReminderTransportUnavailable catch (e) {
      AppLog.w('ReminderService', 'requestPermission 跳过：$e');
      return false;
    }
  }

  /// 查询系统授权状态：`authorized` / `provisional` / `denied` /
  /// `notDetermined` / `unknown`。
  Future<String> permissionStatus() async {
    try {
      return await _transport.getPermissionStatus();
    } on ReminderTransportUnavailable {
      return MethodChannelReminderTransport.permissionUnknown;
    }
  }
}
