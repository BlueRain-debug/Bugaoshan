import 'package:bugaoshan/pages/campus/reservation/models/reservation_models.dart';
import 'package:bugaoshan/providers/reservation_provider.dart';
import 'package:bugaoshan/services/api/reservation_api_service.dart';
import 'package:bugaoshan/services/auth/scu_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReservationProvider', () {
    test('refresh：拉资源并默认选中第一个，再查日历', () async {
      final api = _FakeReservationApi(
        resources: [_resource('493', '党建活动室'), _resource('490', '学术交流室')],
      );
      final provider = ReservationProvider(api);

      await provider.refresh();

      expect(provider.state, ReservationLoadState.loaded);
      expect(provider.resources, hasLength(2));
      expect(provider.selectedResourceId, '493');
      expect(provider.selectedResource?.name, '党建活动室');
      expect(provider.calendar, isNotNull);
      expect(api.calendarCalls, 1);
      expect(api.lastResourceId, '493');
      // 默认区间为今天起 7 天。
      expect(api.lastStart, isNotNull);
      expect(api.lastEnd!.difference(api.lastStart!).inDays, 6);
    });

    test('selectResource：切换资源并重新查日历', () async {
      final api = _FakeReservationApi(
        resources: [_resource('493', '党建活动室'), _resource('490', '学术交流室')],
      );
      final provider = ReservationProvider(api);
      await provider.refresh();

      await provider.selectResource('490');

      expect(provider.selectedResourceId, '490');
      expect(provider.selectedResource?.name, '学术交流室');
      expect(api.calendarCalls, 2);
      expect(api.lastResourceId, '490');
    });

    test('重复选中同一资源不重复请求', () async {
      final api = _FakeReservationApi(resources: [_resource('493', '党建活动室')]);
      final provider = ReservationProvider(api);
      await provider.refresh();

      await provider.selectResource('493');

      expect(api.calendarCalls, 1);
    });

    test('shiftRange：区间整体前后平移 7 天', () async {
      final api = _FakeReservationApi(resources: [_resource('493', '党建活动室')]);
      final provider = ReservationProvider(api);
      await provider.refresh();
      final originalStart = provider.rangeStart;

      await provider.shiftRange(7);
      expect(provider.rangeStart.difference(originalStart).inDays, 7);
      expect(api.calendarCalls, 2);

      await provider.shiftRange(-7);
      expect(provider.rangeStart, originalStart);
      expect(api.calendarCalls, 3);
    });

    test('资源列表为空：loaded 且不查日历', () async {
      final api = _FakeReservationApi(resources: const []);
      final provider = ReservationProvider(api);

      await provider.refresh();

      expect(provider.state, ReservationLoadState.loaded);
      expect(provider.resources, isEmpty);
      expect(provider.selectedResourceId, isNull);
      expect(provider.calendar, isNull);
      expect(api.calendarCalls, 0);
    });

    test('会话失效：unauthenticated，不抛未捕获异常', () async {
      final api = _FakeReservationApi(
        resources: const [],
        error: const UnauthenticatedException('预约系统会话未建立或已过期'),
      );
      final provider = ReservationProvider(api);

      await provider.refresh();

      expect(provider.state, ReservationLoadState.error);
      expect(provider.errorKind, ReservationErrorKind.unauthenticated);
      expect(provider.errorMessage, isNull);
    });

    test('接口异常：failed 且带服务端原文', () async {
      final api = _FakeReservationApi(
        resources: const [],
        error: const ServiceException('资源不存在'),
      );
      final provider = ReservationProvider(api);

      await provider.refresh();

      expect(provider.state, ReservationLoadState.error);
      expect(provider.errorKind, ReservationErrorKind.failed);
      expect(provider.errorMessage, '资源不存在');
    });

    test('日历失败：failed 且保留已加载的资源列表', () async {
      final api = _FakeReservationApi(
        resources: [_resource('493', '党建活动室')],
        calendarError: const ServiceException('系统错误'),
      );
      final provider = ReservationProvider(api);

      await provider.refresh();

      expect(provider.resources, hasLength(1));
      expect(provider.state, ReservationLoadState.error);
      expect(provider.errorKind, ReservationErrorKind.failed);
      expect(provider.errorMessage, '系统错误');
    });

    test('clear 复位全部状态', () async {
      final api = _FakeReservationApi(resources: [_resource('493', '党建活动室')]);
      final provider = ReservationProvider(api);
      await provider.refresh();

      provider.clear();

      expect(provider.state, ReservationLoadState.idle);
      expect(provider.resources, isEmpty);
      expect(provider.selectedResourceId, isNull);
      expect(provider.calendar, isNull);
    });
  });
}

ReservationResource _resource(String id, String name) => ReservationResource(
  id: id,
  name: name,
  attributes: const [],
  needsApproval: true,
  maxPeriodsPerDay: 2,
  bookable: true,
);

/// 可编排的假 API：记录调用参数，按需抛错。
class _FakeReservationApi implements ReservationApi {
  _FakeReservationApi({
    required this.resources,
    this.error,
    this.calendarError,
  });

  final List<ReservationResource> resources;
  final Object? error;
  final Object? calendarError;

  int calendarCalls = 0;
  String? lastResourceId;
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<List<ReservationResource>> fetchResources() async {
    final error = this.error;
    if (error != null) throw error;
    return resources;
  }

  @override
  Future<ReservationResource?> fetchResourceDetail(String resourceId) async {
    for (final resource in resources) {
      if (resource.id == resourceId) return resource;
    }
    return null;
  }

  @override
  Future<ReservationCalendar> fetchCalendar({
    required String resourceId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    calendarCalls++;
    lastResourceId = resourceId;
    lastStart = startDate;
    lastEnd = endDate;
    final error = calendarError;
    if (error != null) throw error;
    return ReservationCalendar(
      slots: const [
        ReservationTimeSlot(
          id: '5103',
          startTime: '08:00:00',
          endTime: '12:00:00',
        ),
      ],
      days: const ['2026-10-23'],
      states: {
        '2026-10-23': {
          '5103': const ReservationSlotState(
            status: ReservationSlotStatus.available,
            total: 1,
            remaining: 1,
          ),
        },
      },
    );
  }
}
