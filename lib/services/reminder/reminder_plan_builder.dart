import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:bugaoshan/utils/semester_week.dart';
import 'package:flutter/material.dart';

/// 提醒文案生成。抽出来是为了让 [ReminderPlanBuilder] 保持纯函数、可单测——
/// 真实实现依赖 `AppLocalizations`，测试用 [DefaultReminderNarrator] 或桩。
abstract class ReminderNarrator {
  /// 通知标题，通常是课程名。
  String titleFor(Course course);

  /// 通知正文。是否包含地点 / 教师由 [withLocation] / [withTeacher] 决定，
  /// 二者必须与隐私开关同源——锁屏通知同样受「隐藏教师姓名」约束。
  String bodyFor({
    required Course course,
    required TimeSlot slot,
    required bool withLocation,
    required bool withTeacher,
  });
}

/// 无本地化依赖的中文实现。生产环境应传入基于 `AppLocalizations` 的实现。
class DefaultReminderNarrator implements ReminderNarrator {
  const DefaultReminderNarrator();

  @override
  String titleFor(Course course) => course.name;

  @override
  String bodyFor({
    required Course course,
    required TimeSlot slot,
    required bool withLocation,
    required bool withTeacher,
  }) {
    final buffer = StringBuffer(_hhmm(slot.startTime));
    if (withLocation && course.location.isNotEmpty) {
      buffer.write(' · ${course.location}');
    }
    if (withTeacher && course.teacher.isNotEmpty) {
      buffer.write(' · ${course.teacher}');
    }
    return buffer.toString();
  }

  static String _hhmm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// 把课表展开成绝对时刻的排期计划。
///
/// 纯函数：不读时钟、不碰存储、不抛异常。同一份输入恒得同一份输出，
/// 因此可以完整单测——这正是「业务逻辑收归 Dart」的意义所在。
///
/// 展开口径（任一环节偏离都会导致提醒错位或漏发）：
/// - 教学周与自然日的映射一律走 [courseWeekOf] / 周日成行口径，禁止自算 7 天块；
/// - 某门课在第 W 周是否上课一律走 [Course.isActiveInWeek]（离散周次 `customWeeks`
///   的成员判断不受起止周约束，自己写区间判断会漏算）；
/// - 节次到时刻的换算取 `config.timeSlots[section - 1]`。
///
/// 刻意不使用 `selectVisibleCoursesForDay`：它默认把未来周次的占位课程也塞进
/// 结果，用于提醒会在非上课周误报。
class ReminderPlanBuilder {
  const ReminderPlanBuilder._();

  /// 构建排期计划。
  ///
  /// - [now] 必须由调用方注入，构建器自身不读系统时钟。
  /// - [maxReminders] 非空时按触发时刻升序截断（近处优先），被丢弃的条数记入
  ///   [ReminderPlan.droppedCount]。iOS 需传
  ///   [ReminderSettings.iosPendingNotificationLimit]。
  /// - [config] 为 null（无课表）时返回空计划，而不是抛异常。
  static ReminderPlan build({
    required List<Course> courses,
    required ScheduleConfig? config,
    required ReminderSettings settings,
    required DateTime now,
    ReminderNarrator narrator = const DefaultReminderNarrator(),
    String channel = defaultChannel,
    int? maxReminders,
  }) {
    final generatedAt = now;
    final firstDay = DateTime(now.year, now.month, now.day);
    final windowEnd = firstDay.add(Duration(days: settings.windowDays));

    if (config == null || !settings.courseReminderEnabled || courses.isEmpty) {
      return ReminderPlan(
        planId: _planId(const [], windowEnd, channel),
        generatedAt: generatedAt,
        windowStart: firstDay,
        windowEnd: windowEnd,
        channel: channel,
        reminders: const [],
      );
    }

    final leads = settings.normalizedLeadMinutes;
    final semesterStart = config.semesterStartDate;
    final byId = <String, ReminderItem>{};

    for (var offset = 0; offset < settings.windowDays; offset++) {
      final day = firstDay.add(Duration(days: offset));
      if (day.isBefore(
        DateTime(semesterStart.year, semesterStart.month, semesterStart.day),
      )) {
        continue;
      }
      // 放假后 courseWeekOf 会继续返回大于总周数的值，这里显式裁掉。
      final week = courseWeekOf(semesterStart, day);
      if (week > config.totalWeeks) continue;

      final dayOfWeek = day.weekday; // 1=Mon..7=Sun，与 Course.dayOfWeek 同域
      for (final course in courses) {
        if (course.dayOfWeek != dayOfWeek) continue;
        if (!course.isActiveInWeek(week)) continue;

        final slot = _slotOf(config, course.startSection);
        if (slot == null) continue;

        final startAt = DateTime(
          day.year,
          day.month,
          day.day,
          slot.startTime.hour,
          slot.startTime.minute,
        );

        for (final lead in leads) {
          final fireAt = startAt.subtract(Duration(minutes: lead));
          if (!fireAt.isAfter(now)) continue;
          if (fireAt.isAfter(windowEnd)) continue;
          if (settings.isQuiet(
            TimeOfDay(hour: fireAt.hour, minute: fireAt.minute),
          )) {
            continue;
          }

          final item = ReminderItem(
            id: _reminderId(course, day, course.startSection, lead),
            kind: ReminderKind.courseStart,
            fireAt: fireAt,
            title: narrator.titleFor(course),
            body: narrator.bodyFor(
              course: course,
              slot: slot,
              withLocation: settings.includeLocation,
              withTeacher: settings.includeTeacher,
            ),
            collapseKey: 'course:${_yyyymmdd(day)}',
          );
          // 同一门课在库里可能存在多条记录（不同周段展开），同 id 覆盖即可。
          byId[item.id] = item;
        }
      }
    }

    final all = byId.values.toList()
      ..sort((a, b) {
        final byTime = a.fireAt.compareTo(b.fireAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    // 负数上限视为「不限制」而不是直接参与截断：`sublist(0, -1)` 会抛
    // RangeError，而本文件的契约是纯函数不抛异常（与 `semester_week.dart`
    // 同一约定）。调用方传 -1 想表达「不限」是常见笔误，这里兜住。
    final limit = maxReminders != null && maxReminders > 0
        ? maxReminders
        : null;
    final dropped = limit != null && all.length > limit
        ? all.length - limit
        : 0;
    final kept = dropped > 0 ? all.sublist(0, limit) : all;

    return ReminderPlan(
      planId: _planId(kept, windowEnd, channel),
      generatedAt: generatedAt,
      windowStart: firstDay,
      windowEnd: windowEnd,
      channel: channel,
      reminders: kept,
      droppedCount: dropped,
    );
  }

  /// 默认通知渠道标识。
  static const String defaultChannel = 'bugaoshan_reminder';

  static TimeSlot? _slotOf(ScheduleConfig config, int section) {
    if (section < 1 || section > config.timeSlots.length) return null;
    return config.timeSlots[section - 1];
  }

  /// 提醒 id：课程名 + 上课日 + 起始节次 + 提前量。
  ///
  /// 用内容而非 [Course.id] 作为身份——课程 id 由微秒时间戳生成，重新导入课表后
  /// 会全部改变，会让「同一节课」在重排时被判成新提醒并重复投递。
  static String _reminderId(
    Course course,
    DateTime day,
    int startSection,
    int leadMinutes,
  ) => 'course:${course.name}:${_yyyymmdd(day)}:$startSection:$leadMinutes';

  static String _yyyymmdd(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}'
      '${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';

  /// 计划哈希 = 「全部提醒内容 + 排期窗口」。
  ///
  /// 窗口也参与哈希：同一批提醒但窗口推进了一天，应被当作新计划下发，
  /// 否则原生侧会拿旧 `windowEnd` 提前停止投递。
  static String _planId(
    List<ReminderItem> reminders,
    DateTime windowEnd,
    String channel,
  ) => planContentHash([
    ...reminders,
    ReminderItem(
      id: '_window:$channel',
      kind: ReminderKind.courseStart,
      fireAt: windowEnd,
      title: '',
      body: '',
      collapseKey: '',
    ),
  ]);
}
