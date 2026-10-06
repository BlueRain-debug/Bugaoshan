import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:bugaoshan/services/reminder/reminder_plan_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 排期计划构建器的口径回归测试。
///
/// 构建器是纯函数，这里覆盖三类容易出错的地方：
/// 1. 教学周 ↔ 自然日的映射（周一起点学期里周日归属下一周，见 ADR-0006）；
/// 2. 课程活跃周判定（离散周次 `customWeeks` 是成员判断，不受起止周约束）；
/// 3. 投递边界的裁剪（过去时刻、窗口末端、免打扰、平台条数上限）。
///
/// 学期固定用 2026-2027 秋季：起点 2026-08-31（周一），块首日 2026-08-30（周日），
/// 因此 2026-09-20（周日）属第 4 周 —— 历史线上问题正是把它算成第 3 周。
void main() {
  DateTime at(int y, int m, int d, [int h = 0, int mi = 0]) =>
      DateTime(y, m, d, h, mi);

  ScheduleConfig config({
    DateTime? start,
    int totalWeeks = 20,
    List<TimeSlot>? slots,
  }) => ScheduleConfig(
    id: 's1',
    semesterName: '2026-2027 秋季',
    semesterStartDate: start ?? at(2026, 8, 31),
    totalWeeks: totalWeeks,
    timeSlots:
        slots ??
        const [
          // 节次 1：09:00-09:45
          TimeSlot(
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 45),
          ),
          // 节次 2：10:00-10:45
          TimeSlot(
            startTime: TimeOfDay(hour: 10, minute: 0),
            endTime: TimeOfDay(hour: 10, minute: 45),
          ),
        ],
  );

  Course course({
    String name = '高等数学',
    String teacher = '张老师',
    String location = '综C407',
    int dayOfWeek = 2, // 周二
    int startWeek = 1,
    int endWeek = 20,
    int startSection = 1,
    int endSection = 1,
    WeekType weekType = WeekType.every,
    List<int>? customWeeks,
  }) => Course(
    name: name,
    teacher: teacher,
    location: location,
    dayOfWeek: dayOfWeek,
    startWeek: startWeek,
    endWeek: endWeek,
    startSection: startSection,
    endSection: endSection,
    colorValue: 0xFF2196F3,
    weekType: weekType,
    customWeeks: customWeeks,
  );

  const enabled = ReminderSettings(
    courseReminderEnabled: true,
    leadMinutes: [15],
  );

  group('基本展开', () {
    test('周二第 1 节的课在 08:45 提醒', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1), // 周二 00:00
      );

      expect(plan.reminders, hasLength(1));
      final item = plan.reminders.single;
      expect(item.kind, ReminderKind.courseStart);
      expect(item.fireAt, at(2026, 9, 1, 8, 45));
      expect(item.title, '高等数学');
      expect(item.body, '09:00 · 综C407 · 张老师');
      expect(item.collapseKey, 'course:20260901');
    });

    test('没有课表配置时返回空计划而不抛异常', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: null,
        settings: enabled,
        now: at(2026, 9, 1),
      );

      expect(plan.reminders, isEmpty);
      expect(plan.planId, isNotEmpty);
    });

    test('总开关关闭时返回空计划', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(courseReminderEnabled: false),
        now: at(2026, 9, 1),
      );

      expect(plan.reminders, isEmpty);
    });

    test('结果按触发时刻升序，且窗口内每天各一条', () {
      final plan = ReminderPlanBuilder.build(
        // 周二与周四各一门
        courses: [
          course(dayOfWeek: 2),
          course(name: '线性代数', dayOfWeek: 4),
        ],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1), // 周二
      );

      // 窗口 7 天覆盖 9/1~9/7：周二 9/1、周四 9/3（下一个周二 9/8 已在窗口外）
      expect(plan.reminders.map((e) => e.fireAt).toList(), [
        at(2026, 9, 1, 8, 45),
        at(2026, 9, 3, 8, 45),
      ]);
      expect(plan.reminders.map((e) => e.title).toList(), ['高等数学', '线性代数']);
    });
  });

  group('教学周口径（ADR-0006 周日成行）', () {
    test('周一起点学期：2026-09-20 属第 4 周，第 4 周的周日课会被提醒', () {
      final plan = ReminderPlanBuilder.build(
        courses: [
          course(
            name: '周日限定课',
            dayOfWeek: DateTime.sunday,
            startWeek: 4,
            endWeek: 4,
          ),
        ],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          windowDays: 7,
        ),
        now: at(2026, 9, 16), // 周三，窗口覆盖 9/16~9/22
      );

      // 若按「自起点起算的整 7 天块」计算，9/20 会被算成第 3 周而漏掉这条。
      expect(plan.reminders, hasLength(1));
      expect(plan.reminders.single.fireAt, at(2026, 9, 20, 8, 45));
    });

    test('学期开始前不排期', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 8, 20), // 开学前
      );

      expect(plan.reminders, isEmpty);
    });

    test('超出总周数后不排期', () {
      // 2026-08-31 起 20 周：末周最后一天 = 2027-01-16(六)
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(totalWeeks: 20),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          windowDays: 7,
        ),
        now: at(2027, 1, 18),
      );

      expect(plan.reminders, isEmpty);
    });
  });

  group('课程活跃周判定', () {
    test('离散周次只在这些周排期，且不受起止周约束', () {
      final plan = ReminderPlanBuilder.build(
        courses: [
          course(
            name: '离散课',
            startWeek: 1,
            endWeek: 2, // 起止周故意收窄
            customWeeks: [1, 10], // 但第 10 周仍应上课
          ),
        ],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          windowDays: 7,
        ),
        now: at(2026, 9, 1), // 第 1 周周二
      );

      // 第 1 周命中；第 2~9 周都不该有
      expect(plan.reminders, hasLength(1));
      expect(plan.reminders.single.fireAt, at(2026, 9, 1, 8, 45));
    });

    test('单周课只在奇数周排期', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course(weekType: WeekType.odd)],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          windowDays: 22,
        ),
        now: at(2026, 9, 1), // 第 1 周周二
      );

      // 窗口 22 天覆盖 9/1~9/22：奇数周 1/3 的周二为 9/1 与 9/15；
      // 9/8 与 9/22 是第 2、4 周（偶数周），被排除
      expect(plan.reminders.map((e) => e.fireAt).toList(), [
        at(2026, 9, 1, 8, 45),
        at(2026, 9, 15, 8, 45),
      ]);
    });

    test('双周课只在偶数周排期', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course(weekType: WeekType.even)],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          windowDays: 14,
        ),
        now: at(2026, 9, 1),
      );

      expect(plan.reminders.map((e) => e.fireAt).toList(), [
        at(2026, 9, 8, 8, 45),
      ]);
    });

    test('同一天同一节次同名课程的多条记录只产生一条提醒', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course(), course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );

      expect(plan.reminders, hasLength(1));
    });

    test('同一天不同节次的课各产生一条，id 不冲突', () {
      final plan = ReminderPlanBuilder.build(
        courses: [
          course(startSection: 1),
          course(name: '大学物理', startSection: 2),
        ],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );

      expect(plan.reminders, hasLength(2));
      expect(plan.reminders.map((e) => e.id).toSet(), hasLength(2));
      expect(plan.reminders.map((e) => e.fireAt).toList(), [
        at(2026, 9, 1, 8, 45),
        at(2026, 9, 1, 9, 45),
      ]);
    });
  });

  group('投递边界', () {
    test('已过去的时刻不排期（当天课前调用不会补发）', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1, 9, 30), // 周二 09:30，08:45 已过
      );

      // 09:30 之后最近的周二在窗口内是 9/8，但窗口 7 天只到 9/7
      expect(plan.reminders, isEmpty);
    });

    test('多个提前量产生多条并按时刻升序', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [30, 5],
        ),
        now: at(2026, 9, 1),
      );

      expect(plan.reminders.map((e) => e.fireAt).toList(), [
        at(2026, 9, 1, 8, 30), // 提前 30 分
        at(2026, 9, 1, 8, 55), // 提前 5 分
      ]);
      expect(plan.reminders.map((e) => e.id).toSet(), hasLength(2));
    });

    test('提前量去重、丢弃非正值并规范化', () {
      const settings = ReminderSettings(
        courseReminderEnabled: true,
        leadMinutes: [15, 15, 0, -3, 5],
      );
      expect(settings.normalizedLeadMinutes, [5, 15]);

      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: settings,
        now: at(2026, 9, 1),
      );
      expect(plan.reminders, hasLength(2));
    });

    test('免打扰时段内的提醒被丢弃而非延后', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          quietStart: TimeOfDay(hour: 7, minute: 30),
          quietEnd: TimeOfDay(hour: 8, minute: 30),
        ),
        now: at(2026, 9, 1),
      );

      // 08:45 不在 07:30~08:30 内，应保留；再补一个落在区间内的提前量验证丢弃
      expect(plan.reminders, hasLength(1));

      final quiet = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [45], // 09:00 - 45min = 08:15，落在静默区间
          quietStart: TimeOfDay(hour: 7, minute: 30),
          quietEnd: TimeOfDay(hour: 8, minute: 30),
        ),
        now: at(2026, 9, 1),
      );
      expect(quiet.reminders, isEmpty);
    });

    test('节次超出时间表长度时跳过该课，不影响其他课', () {
      final plan = ReminderPlanBuilder.build(
        courses: [
          course(name: '越界课', startSection: 9),
          course(name: '正常课', startSection: 1),
        ],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );

      expect(plan.reminders, hasLength(1));
      expect(plan.reminders.single.title, '正常课');
    });

    test('超过平台条数上限时按时刻截断并记录丢弃数', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          windowDays: 28,
        ),
        now: at(2026, 9, 1),
        maxReminders: 3,
      );

      expect(plan.reminders, hasLength(3));
      expect(plan.droppedCount, greaterThan(0));
      // 截断保留的是最近的 3 条
      expect(plan.reminders.first.fireAt, at(2026, 9, 1, 8, 45));
      expect(plan.reminders.last.fireAt, at(2026, 9, 15, 8, 45));
    });

    test('负数上限视为「不限制」而非崩溃', () {
      // 纯函数契约是不抛异常；`sublist(0, -1)` 会抛 RangeError。
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
        maxReminders: -1,
      );

      expect(plan.droppedCount, 0);
      expect(plan.reminders, isNotEmpty);
    });
  });

  group('隐私开关联动', () {
    test('关闭地点与教师后正文只保留时刻', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          includeLocation: false,
          includeTeacher: false,
        ),
        now: at(2026, 9, 1),
      );

      expect(plan.reminders.single.body, '09:00');
    });

    test('仅关闭教师时保留地点', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: const ReminderSettings(
          courseReminderEnabled: true,
          leadMinutes: [15],
          includeTeacher: false,
        ),
        now: at(2026, 9, 1),
      );

      expect(plan.reminders.single.body, '09:00 · 综C407');
    });
  });

  group('ReminderSettings.isQuiet', () {
    test('未设置时段时永不静默', () {
      const settings = ReminderSettings();
      expect(settings.isQuiet(const TimeOfDay(hour: 3, minute: 0)), isFalse);
    });

    test('同日区间按闭区间判定', () {
      const settings = ReminderSettings(
        quietStart: TimeOfDay(hour: 7, minute: 30),
        quietEnd: TimeOfDay(hour: 8, minute: 30),
      );
      expect(settings.isQuiet(const TimeOfDay(hour: 8, minute: 0)), isTrue);
      expect(settings.isQuiet(const TimeOfDay(hour: 7, minute: 30)), isTrue);
      expect(settings.isQuiet(const TimeOfDay(hour: 8, minute: 30)), isTrue);
      expect(settings.isQuiet(const TimeOfDay(hour: 8, minute: 31)), isFalse);
    });

    test('跨午夜区间（22:00~07:00）', () {
      const settings = ReminderSettings(
        quietStart: TimeOfDay(hour: 22, minute: 0),
        quietEnd: TimeOfDay(hour: 7, minute: 0),
      );
      expect(settings.isQuiet(const TimeOfDay(hour: 23, minute: 30)), isTrue);
      expect(settings.isQuiet(const TimeOfDay(hour: 2, minute: 0)), isTrue);
      expect(settings.isQuiet(const TimeOfDay(hour: 12, minute: 0)), isFalse);
    });

    test('首尾相同的空区间视为不静默', () {
      const settings = ReminderSettings(
        quietStart: TimeOfDay(hour: 8, minute: 0),
        quietEnd: TimeOfDay(hour: 8, minute: 0),
      );
      expect(settings.isQuiet(const TimeOfDay(hour: 8, minute: 0)), isFalse);
    });
  });

  group('计划哈希与序列化', () {
    test('相同输入得到相同 planId（跨调用稳定）', () {
      final a = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final b = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );

      expect(a.planId, b.planId);
    });

    test('课表变化会改变 planId', () {
      final a = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final b = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1, 1), // 同一天晚一小时，窗口未变
      );

      expect(a.planId, b.planId);
      expect(a.generatedAt, isNot(b.generatedAt));
    });

    test('窗口推进会改变 planId', () {
      final a = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final b = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 2),
      );

      expect(a.planId, isNot(b.planId));
    });

    test('toChannelPayload 只带 epoch 毫秒，不带 ISO 串', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final payload = plan.toChannelPayload();

      expect(payload['schema'], ReminderPlan.schema);
      expect(payload['windowStartMillis'], isA<int>());
      final first = (payload['reminders'] as List).first as Map;
      expect(
        first['fireAtMillis'],
        at(2026, 9, 1, 8, 45).millisecondsSinceEpoch,
      );
      expect(first.containsKey('fireAt'), isFalse);
    });

    test('toJson → fromJson 往返一致', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final restored = ReminderPlan.fromJson(plan.toJson());

      expect(restored, isNotNull);
      expect(restored!.planId, plan.planId);
      expect(restored.channel, plan.channel);
      expect(restored.windowEnd, plan.windowEnd);
      expect(restored.reminders, hasLength(plan.reminders.length));
      expect(restored.reminders.single.fireAt, plan.reminders.single.fireAt);
      expect(restored.reminders.single.title, plan.reminders.single.title);
    });

    test('schema 不匹配时拒绝解析', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final json = plan.toJson();
      json['schema'] = 999;

      expect(ReminderPlan.fromJson(json), isNull);
    });

    test('脏数据条目被跳过而不是让整批失败', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final json = plan.toJson();
      final list = List<Object?>.from(json['reminders'] as List);
      list.add(<String, Object?>{'id': '', 'kind': 'course_start'});
      list.add(<String, Object?>{'id': 'x', 'kind': 'unknown_kind'});
      list.add('not-a-map');
      json['reminders'] = list;

      final restored = ReminderPlan.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.reminders, hasLength(1));
    });

    test('ISO 时刻串带显式时区偏移', () {
      final plan = ReminderPlanBuilder.build(
        courses: [course()],
        config: config(),
        settings: enabled,
        now: at(2026, 9, 1),
      );
      final json = plan.toJson();
      final fireAt = json['reminders'] as List;
      final text = (fireAt.first as Map)['fireAt'] as String;

      expect(
        text,
        matches(
          RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$'),
        ),
      );
      expect(
        DateTime.parse(text).isAtSameMomentAs(at(2026, 9, 1, 8, 45)),
        isTrue,
      );
    });

    test('planContentHash 对内容敏感且稳定', () {
      ReminderItem item(String id, String title) => ReminderItem(
        id: id,
        kind: ReminderKind.courseStart,
        fireAt: at(2026, 9, 1, 8, 45),
        title: title,
        body: 'b',
        collapseKey: 'c',
      );

      expect(
        planContentHash([item('a', 'x')]),
        planContentHash([item('a', 'x')]),
      );
      expect(
        planContentHash([item('a', 'x')]),
        isNot(planContentHash([item('a', 'y')])),
      );
      expect(
        planContentHash([item('a', 'x')]),
        isNot(planContentHash([item('b', 'x')])),
      );
      expect(planContentHash(const []), isNotEmpty);
    });

    test('字段拼接无歧义：不同字段切分不能混出同一哈希', () {
      ReminderItem item(String id, String title) => ReminderItem(
        id: id,
        kind: ReminderKind.courseStart,
        fireAt: at(2026, 9, 1, 8, 45),
        title: title,
        body: 'b',
        collapseKey: 'c',
      );

      // 若字段之间不补分隔符，「ab」+「c」与「a」+「bc」会混成同一串。
      expect(
        planContentHash([item('ab', 'c')]),
        isNot(planContentHash([item('a', 'bc')])),
      );
      // 条目之间同理：一条空 title 与少一条不能等价。
      expect(
        planContentHash([item('a', '')]),
        isNot(planContentHash(const [])),
      );
    });
  });
}
