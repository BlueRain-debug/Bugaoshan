import 'dart:async';

import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/providers/course_provider.dart';
import 'package:bugaoshan/services/reminder/live_activity_service.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/utils/semester_week.dart';
import 'package:flutter/material.dart';

/// 「当前正在上的课」的判定结果。抽成独立类型便于单测，也避免协调器把
/// 「算哪节课」与「什么时候开/关 Activity」两件事混在一处。
@immutable
class LiveCourseSnapshot {
  /// 正在上的课，没有则为 null。
  final Course? current;

  /// 本节课的下课时刻。
  final DateTime? endAt;

  /// 下一节课（按开始时刻取最近的一节），没有则为 null。
  final Course? next;

  /// 下一节课的开始时刻。
  final DateTime? nextStartAt;

  const LiveCourseSnapshot({
    this.current,
    this.endAt,
    this.next,
    this.nextStartAt,
  });

  static const LiveCourseSnapshot empty = LiveCourseSnapshot();

  bool get hasCurrent => current != null;
}

/// 从课表算「此刻在上什么课」。纯函数：不读时钟（`now` 由调用方注入）、
/// 不碰存储、不抛异常。
///
/// 与 `ReminderPlanBuilder` 共用同一套周次口径（ADR-0006 周日成行）与
/// `Course.isActiveInWeek`，不另立一份判断——两份口径漂移正是 ADR-0008 要避免的事。
class LiveCourseResolver {
  const LiveCourseResolver._();

  static LiveCourseSnapshot resolve({
    required List<Course> courses,
    required ScheduleConfig? config,
    required DateTime now,
  }) {
    if (config == null || courses.isEmpty) return LiveCourseSnapshot.empty;

    final today = DateTime(now.year, now.month, now.day);
    final semesterStart = config.semesterStartDate;
    if (today.isBefore(
      DateTime(semesterStart.year, semesterStart.month, semesterStart.day),
    )) {
      return LiveCourseSnapshot.empty;
    }
    final week = courseWeekOf(semesterStart, today);
    if (week < 1 || week > config.totalWeeks) return LiveCourseSnapshot.empty;

    final todayCourses = <Course>[];
    for (final course in courses) {
      if (course.dayOfWeek != today.weekday) continue;
      if (!course.isActiveInWeek(week)) continue;
      if (_startAt(config, course, today) == null) continue;
      todayCourses.add(course);
    }
    if (todayCourses.isEmpty) return LiveCourseSnapshot.empty;

    Course? current;
    DateTime? endAt;
    for (final course in todayCourses) {
      final start = _startAt(config, course, today)!;
      final end = _endAt(config, course, today);
      if (end == null) continue;
      // 半开区间 [start, end)：下课瞬间即视为已结束，避免 Live Activity 在
      // 下课铃响后还挂着「后下课 0:00」。
      if (!now.isBefore(start) && now.isBefore(end)) {
        current = course;
        endAt = end;
        break;
      }
    }

    Course? next;
    DateTime? nextStartAt;
    for (final course in todayCourses) {
      final start = _startAt(config, course, today)!;
      if (!start.isAfter(now)) continue;
      if (nextStartAt == null || start.isBefore(nextStartAt)) {
        next = course;
        nextStartAt = start;
      }
    }

    return LiveCourseSnapshot(
      current: current,
      endAt: endAt,
      next: next,
      nextStartAt: nextStartAt,
    );
  }

  static DateTime? _startAt(
    ScheduleConfig config,
    Course course,
    DateTime day,
  ) {
    final slot = _slotOf(config, course.startSection);
    if (slot == null) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      slot.startTime.hour,
      slot.startTime.minute,
    );
  }

  static DateTime? _endAt(ScheduleConfig config, Course course, DateTime day) {
    final slot = _slotOf(config, course.endSection);
    if (slot == null) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      slot.endTime.hour,
      slot.endTime.minute,
    );
  }

  static TimeSlot? _slotOf(ScheduleConfig config, int section) {
    if (section < 1 || section > config.timeSlots.length) return null;
    return config.timeSlots[section - 1];
  }
}

/// 把「此刻在上什么课」翻译成 Live Activity 的 start / update / end。
///
/// 三条平台约束决定了本类的形态：
///
/// 1. **只能在应用处于前台时启动**（ActivityKit 硬约束）。因此它由前台恢复与
///    课表变更驱动，而不是后台定时任务——iOS 上不存在可靠的后台定时能力。
/// 2. **应用进程不在时无法开启**。用户如果在没打开过应用的情况下直接去上课，
///    不会自动出现灵动岛；这是方案已知的限制，不是缺陷。
/// 3. **倒计时由系统渲染**，所以本类只在「课程切换」这类状态真正变化时才下发给
///    原生，不做分钟级心跳。
class LiveActivityCoordinator {
  LiveActivityCoordinator({
    required CourseProvider courseProvider,
    LiveActivityService? service,
    Duration? pollInterval,
  }) : _courseProvider = courseProvider,
       _service = service ?? LiveActivityService(),
       _pollInterval = pollInterval ?? const Duration(seconds: 60);

  final CourseProvider _courseProvider;
  final LiveActivityService _service;
  final Duration _pollInterval;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// 当前已下发的课程名。用它判断「是否需要 update」，而不是每次都下发——
  /// 每次前台恢复都对 Activity 调一次 update 是没必要的系统开销。
  String? _activeCourseName;

  /// 当前会话是否可用。不可用（非 iOS、系统关闭实时活动）时不再重试，
  /// 否则每次前台恢复都会撞一次 `UNSUPPORTED_PLATFORM` 并刷日志。
  bool _available = true;

  bool get isActive => _activeCourseName != null;

  /// 启动轮询。仅应在 iOS 上调用：其他平台的 [LiveActivityService] 会直接抛
  /// [LiveActivityUnsupportedException]，本类会把它收敛成「不可用」并停手。
  Future<void> start() async {
    if (_disposed || _running) return;
    _running = true;
    _available = await _service.isSupported();
    if (!_available) {
      AppLog.d('LiveActivity', '当前设备不支持实时活动，协调器停用');
      return;
    }
    _courseProvider.courses.addListener(_onSourceChanged);
    _courseProvider.scheduleConfig.addListener(_onSourceChanged);
    // 轮询的用途是「下课时自动收尾」。课程切换由课表变更与前台恢复覆盖，
    // 但没有任何事件会在课间自然到达，只能靠定时器兜住。
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(tick()));
    await tick();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_running) {
      _courseProvider.courses.removeListener(_onSourceChanged);
      _courseProvider.scheduleConfig.removeListener(_onSourceChanged);
    }
    _running = false;
  }

  void _onSourceChanged() => unawaited(tick());

  /// 按当前时刻对账一次：该开的开、该改的改、该关的关。
  Future<void> tick() async {
    if (_disposed || !_available) return;

    final snapshot = LiveCourseResolver.resolve(
      courses: _courseProvider.courses.value,
      config: _courseProvider.scheduleConfig.value,
      now: DateTime.now(),
    );

    try {
      final current = snapshot.current;
      if (current == null) {
        // 课间或当天已无课：结束会话。下一次 tick 若进入下一节课会重新开启。
        if (_activeCourseName != null) await _end();
        return;
      }

      if (_activeCourseName == current.name) return;

      final next = snapshot.next;
      if (_activeCourseName == null) {
        await _service.start(
          courseName: current.name,
          location: current.location,
          endAt: snapshot.endAt!,
          nextCourseName: next?.name,
          nextLocation: (next?.location.isEmpty ?? true)
              ? null
              : next!.location,
        );
      } else {
        // 连堂课（同一门课换节次）或相邻两节课之间切换：复用同一条 Activity，
        // 换内容比「关掉再开」体面——后者会在锁屏上闪一次空白。
        await _service.update(
          courseName: current.name,
          location: current.location,
          endAt: snapshot.endAt,
          nextCourseName: next?.name,
          nextLocation: (next?.location.isEmpty ?? true)
              ? null
              : next!.location,
        );
      }
      _activeCourseName = current.name;
    } on LiveActivityUnsupportedException catch (e) {
      AppLog.d('LiveActivity', '设备不支持，停止后续尝试：$e');
      _available = false;
    } on LiveActivityNotAuthorizedException catch (e) {
      // 用户在系统设置里关掉了实时活动。这是用户可处理的状态，不是故障；
      // 每次前台恢复都重试一次是合理的（用户可能刚刚打开）。
      AppLog.d('LiveActivity', '用户未开启实时活动：$e');
      await _end(swallowErrors: true);
    } on LiveActivityForegroundRequiredException catch (e) {
      // 前台恢复与课表变更都在前台发生，理论上到不了这里；真到了也不该刷错误日志。
      AppLog.d('LiveActivity', '非前台，跳过本轮：$e');
    } on LiveActivityNoActiveSessionException {
      // Dart 以为有会话、原生没有了（例如用户在系统里关掉）。对齐状态，
      // 下一轮重新 start。
      _activeCourseName = null;
    } catch (e) {
      AppLog.w('LiveActivity', '同步实时活动失败：$e');
    }
  }

  Future<void> _end({bool swallowErrors = false}) async {
    _activeCourseName = null;
    try {
      await _service.end();
    } catch (e) {
      if (!swallowErrors) AppLog.w('LiveActivity', '结束实时活动失败：$e');
    }
  }
}
