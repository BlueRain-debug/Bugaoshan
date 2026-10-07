import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/services/reminder/live_activity_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [LiveCourseResolver] 的判定测试。
///
/// 这里只验证「此刻上的是哪节课」——它决定灵动岛显示什么，也决定 Live Activity
/// 的开关时机。周次口径本身由 `reminder_plan_test.dart` 与 ADR-0006 覆盖，
/// 两处刻意走同一个 `courseWeekOf` / `Course.isActiveInWeek`。
void main() {
  /// 2026-08-31 是周一，教学第 1 周；09-01 为周二，仍在第 1 周。
  ScheduleConfig schedule({int totalWeeks = 20}) => ScheduleConfig(
    id: 's1',
    semesterStartDate: DateTime(2026, 8, 31),
    totalWeeks: totalWeeks,
    timeSlots: const [
      TimeSlot(
        startTime: TimeOfDay(hour: 8, minute: 0),
        endTime: TimeOfDay(hour: 8, minute: 45),
      ),
      TimeSlot(
        startTime: TimeOfDay(hour: 9, minute: 0),
        endTime: TimeOfDay(hour: 9, minute: 45),
      ),
      TimeSlot(
        startTime: TimeOfDay(hour: 10, minute: 0),
        endTime: TimeOfDay(hour: 10, minute: 45),
      ),
    ],
  );

  Course course({
    String name = '高等数学',
    int dayOfWeek = 2,
    int startSection = 1,
    int endSection = 1,
    List<int>? customWeeks,
  }) => Course(
    name: name,
    teacher: '张老师',
    location: '综C407',
    dayOfWeek: dayOfWeek,
    startWeek: 1,
    endWeek: 20,
    startSection: startSection,
    endSection: endSection,
    colorValue: 0xFF2196F3,
    customWeeks: customWeeks,
  );

  LiveCourseSnapshot resolve({
    required List<Course> courses,
    required DateTime now,
    ScheduleConfig? config,
  }) => LiveCourseResolver.resolve(
    courses: courses,
    config: config ?? schedule(),
    now: now,
  );
  group('当前课程判定', () {
    test('课中：返回当前课程与下课时刻', () {
      final snapshot = resolve(
        courses: [course()],
        now: DateTime(2026, 9, 1, 8, 20),
      );

      expect(snapshot.current?.name, '高等数学');
      expect(snapshot.endAt, DateTime(2026, 9, 1, 8, 45));
    });

    test('上课瞬间即为「在上课」，下课瞬间即为「已下课」', () {
      final courses = [course()];

      expect(
        resolve(courses: courses, now: DateTime(2026, 9, 1, 8, 0)).hasCurrent,
        isTrue,
      );
      // 半开区间：下课那一秒不该还挂着「后下课 0:00」。
      expect(
        resolve(courses: courses, now: DateTime(2026, 9, 1, 8, 45)).hasCurrent,
        isFalse,
      );
    });

    test('连堂课按结束节次取下课时刻', () {
      final snapshot = resolve(
        courses: [course(startSection: 1, endSection: 3)],
        now: DateTime(2026, 9, 1, 8, 30),
      );

      expect(snapshot.current?.name, '高等数学');
      expect(snapshot.endAt, DateTime(2026, 9, 1, 10, 45));
    });

    test('课间：没有当前课程，但能拿到下一节', () {
      final snapshot = resolve(
        courses: [
          course(startSection: 1),
          course(name: '线性代数', startSection: 2),
        ],
        now: DateTime(2026, 9, 1, 8, 50),
      );

      expect(snapshot.hasCurrent, isFalse);
      expect(snapshot.next?.name, '线性代数');
      expect(snapshot.nextStartAt, DateTime(2026, 9, 1, 9, 0));
    });

    test('别的星期与本周不上课的课程都不算数', () {
      expect(
        resolve(
          courses: [course(dayOfWeek: 3)],
          now: DateTime(2026, 9, 1, 8, 20),
        ).hasCurrent,
        isFalse,
      );
      // 第 1 周不在自定义离散周次里。
      expect(
        resolve(
          courses: [
            course(customWeeks: const [2, 3]),
          ],
          now: DateTime(2026, 9, 1, 8, 20),
        ).hasCurrent,
        isFalse,
      );
    });

    test('学期开始前与放假后都不判定', () {
      expect(
        resolve(
          courses: [course(dayOfWeek: 1)],
          now: DateTime(2026, 8, 24, 8, 20),
        ).hasCurrent,
        isFalse,
      );
      // 第 21 周已超出总周数。
      expect(
        resolve(
          courses: [course(dayOfWeek: 1)],
          now: DateTime(2027, 1, 25, 8, 20),
        ).hasCurrent,
        isFalse,
      );
    });

    test('无课表或无课程时返回空快照而不是抛异常', () {
      // 这里刻意直接调用 resolve 而不用上面的辅助函数：辅助函数把 null 当作
      // 「用默认课表」，无法表达「课表尚未加载」这一真实状态。
      expect(
        LiveCourseResolver.resolve(
          courses: const [],
          config: schedule(),
          now: DateTime(2026, 9, 1, 8, 20),
        ).hasCurrent,
        isFalse,
      );
      expect(
        LiveCourseResolver.resolve(
          courses: [course()],
          config: null,
          now: DateTime(2026, 9, 1, 8, 20),
        ).hasCurrent,
        isFalse,
      );
    });

    test('节次超出时间表长度时跳过该课', () {
      expect(
        resolve(
          courses: [course(startSection: 9, endSection: 9)],
          now: DateTime(2026, 9, 1, 8, 20),
        ).hasCurrent,
        isFalse,
      );
    });
  });
}
