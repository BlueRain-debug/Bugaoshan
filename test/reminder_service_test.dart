import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/providers/course_provider.dart';
import 'package:bugaoshan/services/database_service.dart';
import 'package:bugaoshan/services/reminder/reminder_plan_builder.dart';
import 'package:bugaoshan/services/reminder/reminder_service.dart';
import 'package:bugaoshan/services/reminder/reminder_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [ReminderService] 的协调语义测试：监听、去抖、短路、全量清空、失败重试。
///
/// 这里不重复验证排期口径（那属于 `reminder_plan_test.dart`），只验证
/// 「什么时候会重排」与「重排失败后系统处于什么状态」——这两件事出问题
/// 时用户在锁屏上看到的症状完全一样（没有提醒），但修法完全不同。
/// 记录每一次投递，供断言「是否真的重排了」。
class RecordingTransport implements ReminderTransport {
  final List<ReminderPlan> synced = [];
  int cancelAllCount = 0;
  Object? failWith;
  bool unavailable = false;
  bool denied = false;

  @override
  Future<void> syncPlan(ReminderPlan plan) async {
    if (unavailable) throw const ReminderTransportUnavailable();
    if (denied) throw const ReminderPermissionDenied();
    if (failWith != null) throw failWith!;
    synced.add(plan);
  }

  @override
  Future<void> cancelAll() async {
    if (unavailable) throw const ReminderTransportUnavailable();
    if (denied) throw const ReminderPermissionDenied();
    if (failWith != null) throw failWith!;
    cancelAllCount++;
  }

  @override
  Future<bool> requestAuthorization({bool provisional = false}) async {
    if (unavailable) throw const ReminderTransportUnavailable();
    return !denied;
  }

  @override
  Future<String> getPermissionStatus() async => unavailable
      ? MethodChannelReminderTransport.permissionUnknown
      : (denied ? 'denied' : 'authorized');

  @override
  Future<int> getPendingCount() async =>
      unavailable ? 0 : (synced.isEmpty ? 0 : synced.last.reminders.length);

  @override
  Future<bool> openNotificationSettings() async => !unavailable;

  /// 默认不限条数，需要验证裁剪的用例自行设置。
  @override
  int? pendingLimit;
}

/// 内存版课表数据源。
///
/// 复用 `course_provider_test.dart` 的做法：只覆盖 [CourseProvider] 实际会读的
/// 同步 getter 与写方法，避免在单测里初始化真实 SQLite（那需要 path_provider
/// 等平台插件）。
class _FakeDatabase extends DatabaseService {
  _FakeDatabase({ScheduleConfig? config}) : _config = config;

  ScheduleConfig? _config;
  List<Course> _courses = [];

  @override
  List<Course> getCourses({String? scheduleId}) => List.of(_courses);

  @override
  List<ScheduleConfig> getAllSchedules() =>
      _config == null ? const [] : [_config!];

  @override
  ScheduleConfig? getScheduleConfig() => _config;

  @override
  String getCurrentScheduleId() => _config?.id ?? '';

  @override
  Future<void> saveScheduleConfig(ScheduleConfig config) async {
    _config = config;
  }

  @override
  Future<void> addCourse(Course course) async {
    _courses = [..._courses, course];
  }

  @override
  Future<void> updateCourse(Course course) async {
    _courses = [
      for (final c in _courses)
        if (c.id == course.id) course else c,
    ];
  }

  @override
  Future<void> deleteCourse(String courseId) async {
    _courses = _courses.where((c) => c.id != courseId).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDatabase db;
  late CourseProvider courseProvider;
  late AppConfigProvider appConfig;
  late RecordingTransport transport;
  late ReminderService service;

  DateTime at(int y, int m, int d, [int h = 0, int mi = 0]) =>
      DateTime(y, m, d, h, mi);

  Course course({
    String name = '高等数学',
    int dayOfWeek = 2,
    int startWeek = 1,
    int endWeek = 20,
    List<int>? customWeeks,
  }) => Course(
    name: name,
    teacher: '张老师',
    location: '综C407',
    dayOfWeek: dayOfWeek,
    startWeek: startWeek,
    endWeek: endWeek,
    startSection: 1,
    endSection: 1,
    colorValue: 0xFF2196F3,
    customWeeks: customWeeks,
  );

  ScheduleConfig schedule() => ScheduleConfig(
    id: 's1',
    semesterStartDate: at(2026, 8, 31),
    totalWeeks: 20,
    timeSlots: const [
      TimeSlot(
        startTime: TimeOfDay(hour: 9, minute: 0),
        endTime: TimeOfDay(hour: 9, minute: 45),
      ),
    ],
  );

  /// 建立一套「已有一门周二课」的上下文。
  Future<void> setUpService({bool enabled = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    appConfig = AppConfigProvider(prefs);
    await appConfig.init();
    appConfig.reminderEnabled.value = enabled;

    db = _FakeDatabase(config: schedule());
    courseProvider = CourseProvider(db);
    await courseProvider.addCourse(course());

    transport = RecordingTransport();
    service = ReminderService(
      courseProvider: courseProvider,
      appConfig: appConfig,
      transport: transport,
      // 测试里把去抖压到 0，避免依赖真实计时。
      debounceDuration: Duration.zero,
    );
  }

  tearDown(() {
    service.dispose();
  });

  group('排期触发', () {
    test('启用后首次排期会把计划投递出去', () async {
      await setUpService();
      await service.reschedule(force: true);

      expect(transport.synced, isNotEmpty);
      final plan = transport.synced.last;
      expect(plan.channel, ReminderPlanBuilder.defaultChannel);
      expect(plan.reminders, isNotEmpty);
    });

    test('未启用时不投递计划，只清空', () async {
      await setUpService(enabled: false);
      await service.reschedule(force: true);

      expect(transport.synced, isEmpty);
      expect(transport.cancelAllCount, 1);
    });

    test('计划内容未变化时短路，不重复投递', () async {
      await setUpService();
      await service.reschedule(force: true);
      final firstCount = transport.synced.length;
      await service.reschedule(force: true);
      await service.reschedule(force: true);

      // planId 相同 → 只在第一次投递
      expect(transport.synced.length, firstCount);
    });

    test('课表变化会触发重排并改变计划', () async {
      await setUpService();
      await service.reschedule(force: true);
      final before = transport.synced.last.planId;

      courseProvider.courses.value = [
        ...courseProvider.courses.value,
        course(name: '线性代数', dayOfWeek: 4),
      ];
      await service.reschedule(force: true);

      expect(transport.synced.last.planId, isNot(before));
      expect(transport.synced.last.reminders, hasLength(2));
    });

    test('隐私开关变化会触发重排（锁屏正文随之变化）', () async {
      await setUpService();
      await service.reschedule(force: true);
      expect(transport.synced.last.reminders.first.body, contains('张老师'));

      appConfig.showTeacherName.value = false;
      await service.reschedule(force: true);

      expect(
        transport.synced.last.reminders.first.body,
        isNot(contains('张老师')),
      );
      expect(transport.synced.last.reminders.first.body, contains('综C407'));
    });

    test('关掉总开关会清空已排期提醒，而不只是停止新增', () async {
      await setUpService();
      await service.reschedule(force: true);
      expect(transport.synced, isNotEmpty);

      appConfig.reminderEnabled.value = false;
      await service.reschedule(force: true);

      expect(transport.cancelAllCount, 1);
    });

    test('新增课程后经监听自动重排（不依赖显式调用）', () async {
      await setUpService();
      await service.start();
      final before = transport.synced.length;

      // 刻意避开「今天就是周三」的干扰：周三 08:45 的提醒在当天下课后
      // 就会被 isAfter(now) 排除，而下周三又超出 7 天窗口——这条用例曾在
      // 周三下午起持续失败，原因正是断言依赖了当天时钟。
      await courseProvider.addCourse(course(name: '大学物理', dayOfWeek: 5));
      // 去抖为 0 时监听器排下 Timer(Duration.zero)，但 _runOnce 内部还有
      // 若干 await；多泵几轮，不依赖「一次让出恰好跑完」的时序假设。
      await pumpEventQueue();
      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();

      expect(transport.synced.length, greaterThan(before));
    });
  });

  group('失败与不可用', () {
    test('投递失败时记录 lastError 且下一次仍会重试同一份计划', () async {
      await setUpService();
      transport.failWith = Exception('boom');
      await service.reschedule(force: true);

      expect(service.lastError.value, isNotNull);
      expect(transport.synced, isEmpty);

      // 失败不推进 _lastPushedPlanId：恢复后同一份计划应被重新投递
      transport.failWith = null;
      await service.reschedule(force: true);
      expect(transport.synced, hasLength(1));
      expect(service.lastError.value, isNull);
    });

    test('原生未接线时不视为错误，仅保留可观测的计划', () async {
      await setUpService();
      transport.unavailable = true;
      await service.reschedule(force: true);

      // 用户无法处理这种状态，设置页不应据此报警
      expect(service.lastError.value, isNull);
      expect(service.lastPlan.value, isNotNull);
      expect(service.needsPermission.value, isFalse);
    });

    test('未授权时标记 needsPermission 而非 lastError', () async {
      await setUpService();
      transport.denied = true;
      await service.reschedule(force: true);

      expect(service.needsPermission.value, isTrue);
      expect(service.lastError.value, isNull);

      // 授权后重排应清掉标记
      transport.denied = false;
      await service.onPermissionGranted();
      expect(service.needsPermission.value, isFalse);
      expect(transport.synced, hasLength(1));
    });

    test('dispose 之后不再排期', () async {
      await setUpService();
      service.dispose();
      await service.reschedule(force: true);

      expect(transport.synced, isEmpty);
      expect(transport.cancelAllCount, 0);
    });

    test('fireProbe 不撤销既有课表提醒', () async {
      await setUpService();
      await service.reschedule(force: true);
      final before = transport.synced.last;

      await service.fireProbe(title: '探针', body: '15 秒后');

      // 下发是全量替换：探针计划若只含探针一条，课表提醒会被原生按前缀全部撤销，
      // 用户点一次探针就丢掉接下来一周的课前提醒。
      final probePlan = transport.synced.last;
      expect(
        probePlan.reminders.where((r) => r.id.startsWith('probe:')),
        hasLength(1),
      );
      // 与 before 比对时排除已过期的条目：`fireProbe` 用真实时钟重建计划，
      // 而 before 是同一秒内算出的，两者对「已过期」的判定应当一致。
      final stillUpcoming = before.reminders.where(
        (r) => r.fireAt.isAfter(DateTime.now()),
      );
      expect(
        probePlan.reminders
            .where((r) => !r.id.startsWith('probe:'))
            .map((r) => r.id),
        containsAll(stillUpcoming.map((r) => r.id)),
      );
    });

    test('fireProbe 之后重排不会被短路键挡住', () async {
      await setUpService();
      await service.reschedule(force: true);
      await service.fireProbe(title: '探针', body: '15 秒后');
      final afterProbe = transport.synced.length;

      // 探针计划与真实计划的 planId 不同，若沿用旧的短路键，这一次重排会被判成
      // 「计划没变」而跳过，探针一旦被下一轮重排挤掉就再也补不回来。
      await service.reschedule(force: true);

      expect(transport.synced, hasLength(afterProbe + 1));
      expect(
        transport.synced.last.reminders.where((r) => r.id.startsWith('probe:')),
        isEmpty,
      );
    });

    test('平台上限在 Dart 侧裁剪，而不是交给系统丢', () async {
      await setUpService();
      // 周二到周日各排一门：无论今天星期几，7 天窗口内都必然有多条提醒，
      // 用例因此不依赖执行日期。
      for (var weekday = 2; weekday <= 7; weekday++) {
        await courseProvider.addCourse(
          course(name: '课$weekday', dayOfWeek: weekday),
        );
      }
      transport.pendingLimit = 3;

      await service.reschedule(force: true);

      final plan = transport.synced.last;
      expect(plan.reminders, hasLength(3));
      // 被裁条数必须记进计划：否则设置页会一边显示「已排期 N 条」一边在系统里
      // 查到更少，用户读到的两句自相矛盾。
      expect(plan.droppedCount, greaterThan(0));
    });
  });

  group('构建计划', () {
    test('buildPlan 使用注入的 now，且反映当前设置', () async {
      await setUpService();
      appConfig.reminderLeadMinutes.value = const [30];

      final plan = service.buildPlan(now: at(2026, 9, 1));

      expect(plan.reminders, hasLength(1));
      expect(plan.reminders.single.fireAt, at(2026, 9, 1, 8, 30));
    });
  });
}
