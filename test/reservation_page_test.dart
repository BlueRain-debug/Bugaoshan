import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/pages/campus/reservation/models/reservation_models.dart';
import 'package:bugaoshan/pages/campus/reservation/reservation_page.dart';
import 'package:bugaoshan/providers/reservation_provider.dart';
import 'package:bugaoshan/providers/scu_auth_provider.dart';
import 'package:bugaoshan/services/api/reservation_api_service.dart';
import 'package:bugaoshan/services/auth/scu_exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('已登录：渲染活动室、时段与可预约状态', (tester) async {
    getIt.registerSingleton<ReservationProvider>(
      ReservationProvider(_FakeReservationApi()),
    );
    getIt.registerSingleton<ScuAuthProvider>(_LoggedInAuth());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ReservationPage)),
    )!;

    expect(find.text(l10n.reservationTitle), findsOneWidget);
    expect(find.text('党建活动室'), findsWidgets);
    expect(find.text('08:00-12:00'), findsOneWidget);
    expect(find.text(l10n.reservationRemaining(1)), findsOneWidget);
    expect(find.text(l10n.reservationStatusFull), findsWidgets);
    expect(find.text(l10n.reservationGoOfficial), findsOneWidget);
  });

  testWidgets('未登录：显示登录引导，不请求数据', (tester) async {
    final api = _FakeReservationApi();
    getIt.registerSingleton<ReservationProvider>(ReservationProvider(api));
    getIt.registerSingleton<ScuAuthProvider>(_LoggedOutAuth());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ReservationPage)),
    )!;
    expect(find.text(l10n.loginRequired), findsOneWidget);
    expect(api.calendarCalls, 0);
  });

  testWidgets('会话失效：显示预约系统会话提示与重试', (tester) async {
    getIt.registerSingleton<ReservationProvider>(
      ReservationProvider(
        _FakeReservationApi(
          error: const UnauthenticatedException('预约系统会话未建立或已过期'),
        ),
      ),
    );
    getIt.registerSingleton<ScuAuthProvider>(_LoggedInAuth());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ReservationPage)),
    )!;

    expect(find.text(l10n.reservationSessionExpired), findsOneWidget);
    expect(find.text(l10n.goToLogin), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
  });

  testWidgets('无活动室：显示空态文案', (tester) async {
    getIt.registerSingleton<ReservationProvider>(
      ReservationProvider(_FakeReservationApi(resources: const [])),
    );
    getIt.registerSingleton<ScuAuthProvider>(_LoggedInAuth());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ReservationPage)),
    )!;

    expect(find.text(l10n.reservationNoResources), findsOneWidget);
  });

  testWidgets('切换活动室会重新查询日历', (tester) async {
    final api = _FakeReservationApi();
    getIt.registerSingleton<ReservationProvider>(ReservationProvider(api));
    getIt.registerSingleton<ScuAuthProvider>(_LoggedInAuth());

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(api.calendarCalls, 1);

    await tester.tap(find.text('学术交流室'));
    await tester.pumpAndSettle();

    expect(api.calendarCalls, 2);
    expect(api.lastResourceId, '490');
  });
}

Widget _wrap() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const ReservationPage(),
);

class _LoggedInAuth extends ChangeNotifier implements ScuAuthProvider {
  @override
  bool get isLoggedIn => true;

  @override
  bool get isAutoLoggingIn => false;

  @override
  String? get accessToken => 'test-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoggedOutAuth extends ChangeNotifier implements ScuAuthProvider {
  @override
  bool get isLoggedIn => false;

  @override
  bool get isAutoLoggingIn => false;

  @override
  String? get accessToken => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 两间活动室、一天三个时段（含约满与可约）。
class _FakeReservationApi implements ReservationApi {
  _FakeReservationApi({this.resources, this.error});

  final List<ReservationResource>? resources;
  final Object? error;

  int calendarCalls = 0;
  String? lastResourceId;

  @override
  Future<List<ReservationResource>> fetchResources() async {
    final error = this.error;
    if (error != null) throw error;
    return resources ??
        [
          ReservationResource(
            id: '493',
            name: '党建活动室',
            attributes: const [
              ReservationAttribute(name: '容量/人数', value: '28'),
              ReservationAttribute(name: '校区', value: '望江校区'),
            ],
            needsApproval: true,
            maxPeriodsPerDay: 2,
            bookable: true,
          ),
          const ReservationResource(
            id: '490',
            name: '学术交流室',
            attributes: [],
            needsApproval: true,
            maxPeriodsPerDay: 2,
            bookable: true,
          ),
        ];
  }

  @override
  Future<ReservationResource?> fetchResourceDetail(String resourceId) async {
    final list = await fetchResources();
    for (final resource in list) {
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
    return ReservationCalendar(
      slots: const [
        ReservationTimeSlot(
          id: '5103',
          startTime: '08:00:00',
          endTime: '12:00:00',
        ),
        ReservationTimeSlot(
          id: '5104',
          startTime: '12:00:00',
          endTime: '18:00:00',
        ),
        ReservationTimeSlot(
          id: '5105',
          startTime: '18:00:00',
          endTime: '22:00:00',
        ),
      ],
      days: const ['2026-10-23'],
      states: {
        '2026-10-23': {
          '5103': const ReservationSlotState(
            status: ReservationSlotStatus.full,
            total: 1,
            remaining: 0,
          ),
          '5104': const ReservationSlotState(
            status: ReservationSlotStatus.available,
            total: 1,
            remaining: 1,
          ),
          '5105': const ReservationSlotState(
            status: ReservationSlotStatus.notOpen,
            total: 0,
            remaining: 0,
          ),
        },
      },
    );
  }
}
