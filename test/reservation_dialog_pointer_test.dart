import 'package:bugaoshan/app.dart';
import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/pages/campus/reservation/models/reservation_models.dart';
import 'package:bugaoshan/pages/campus/reservation/reservation_page.dart';
import 'package:bugaoshan/providers/reservation_provider.dart';
import 'package:bugaoshan/providers/scu_auth_provider.dart';
import 'package:bugaoshan/services/api/reservation_api_service.dart';
import 'package:bugaoshan/widgets/route/router_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduce the real-Windows-device symptom:
/// inside the reservation popup, the body (strip / chips / arrows) receives
/// no pointer events, while the AppBar close button works.
///
/// Bisect with 4 variants:
/// 1. direct-home: page as home (same as existing tests) at real dialog size
/// 2. popup-chain: full popupOrNavigate path (showDialog + Dialog + Fragment nested Navigator)
/// 3. dialog-no-fragment: showDialog + Dialog, no Fragment
/// 4. dialog-fragment: showDialog + Dialog + Fragment
void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> useRealDesktopSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder stripFinder() => find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );

  IconButton arrow(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        ),
      );

  /// Drag + chip tap + right-arrow tap; returns the first failure or null.
  Future<String?> probePointerPaths(WidgetTester tester) async {
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ReservationPage)),
    )!;

    // 1) mouse drag on the strip
    await tester.drag(
      stripFinder(),
      const Offset(-220, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    if (arrow(tester, l10n.reservationScrollLeft).onPressed == null) {
      return 'mouse-drag: left arrow still disabled';
    }
    // drag back to origin for a clean state
    await tester.drag(
      stripFinder(),
      const Offset(220, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    // 2) tap the ChoiceChip 'Room2'
    final chip2 = find.widgetWithText(ChoiceChip, 'Room2');
    if (chip2.evaluate().isEmpty) return 'chip Room2 not found';
    await tester.tap(chip2);
    await tester.pumpAndSettle();
    if (tester.widget<ChoiceChip>(chip2).selected != true) {
      return 'chip tap: Room2 not selected';
    }

    // 3) 点击右箭头，标签条应继续向右滚
    final stripController =
        tester.widget<ListView>(stripFinder()).controller!;
    final before = stripController.offset;
    await tester.tap(find.byTooltip(l10n.reservationScrollRight));
    await tester.pumpAndSettle();
    if (stripController.offset <= before) {
      return 'right arrow tap: strip did not scroll';
    }
    return null;
  }

  Widget host(Widget Function(BuildContext) body) => MaterialApp(
        navigatorKey: navigatorKey,
        scrollBehavior: const AppScrollBehavior(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) => Scaffold(body: body(context))),
      );

  void registerFakes() {
    getIt.registerSingleton<ReservationProvider>(
      ReservationProvider(_FakeReservationApi()),
    );
    getIt.registerSingleton<ScuAuthProvider>(_LoggedInAuth());
  }

  testWidgets('1 direct-home: all pointer paths alive at desktop size',
      (tester) async {
    registerFakes();
    await useRealDesktopSize(tester);

    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ReservationPage(),
    ));
    await tester.pumpAndSettle();

    final failure = await probePointerPaths(tester);
    expect(failure, isNull, reason: failure ?? '');
  });

  testWidgets('2 popup-chain: full popupOrNavigate path', (tester) async {
    registerFakes();
    await useRealDesktopSize(tester);

    await tester.pumpWidget(host((context) {
      return Center(
        child: FilledButton(
          onPressed: () => popupOrNavigate(context, const ReservationPage()),
          child: const Text('OPEN'),
        ),
      );
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(ReservationPage), findsOneWidget);

    final failure = await probePointerPaths(tester);
    expect(failure, isNull, reason: failure ?? '');
  });

  testWidgets('3 dialog-no-fragment: showDialog without Fragment',
      (tester) async {
    registerFakes();
    await useRealDesktopSize(tester);

    await tester.pumpWidget(host((context) {
      return Center(
        child: FilledButton(
          onPressed: () => showDialog(
            context: context,
            useRootNavigator: false,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: DialogTheme.of(context).backgroundColor,
                  child: const SizedBox(
                    width: 853,
                    height: 900,
                    child: ReservationPage(),
                  ),
                ),
              ),
            ),
          ),
          child: const Text('OPEN'),
        ),
      );
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(ReservationPage), findsOneWidget);

    final failure = await probePointerPaths(tester);
    expect(failure, isNull, reason: failure ?? '');
  });

  testWidgets('4 dialog-fragment: showDialog + Fragment nested Navigator',
      (tester) async {
    registerFakes();
    await useRealDesktopSize(tester);

    await tester.pumpWidget(host((context) {
      return Center(
        child: FilledButton(
          onPressed: () => showDialog(
            context: context,
            useRootNavigator: false,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: DialogTheme.of(context).backgroundColor,
                  child: const SizedBox(
                    width: 853,
                    height: 900,
                    child: Fragment(child: ReservationPage()),
                  ),
                ),
              ),
            ),
          ),
          child: const Text('OPEN'),
        ),
      );
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(ReservationPage), findsOneWidget);

    final failure = await probePointerPaths(tester);
    expect(failure, isNull, reason: failure ?? '');
  });
}

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

/// 足够多的活动室，保证宽屏（1707 逻辑宽）与窄弹窗（853）下标签条都横向溢出。
List<ReservationResource> manyResources() => [
      for (var i = 0; i < 20; i++)
        ReservationResource(
          id: '$i',
          name: 'Room$i',
          attributes: const [],
          needsApproval: false,
          maxPeriodsPerDay: 0,
        ),
    ];

class _FakeReservationApi implements ReservationApi {
  @override
  Future<List<ReservationResource>> fetchResources() async => manyResources();

  @override
  Future<ReservationCalendar> fetchCalendar({
    required String resourceId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return const ReservationCalendar(
      slots: [
        ReservationTimeSlot(id: 'a', startTime: '08:00:00', endTime: '12:00:00'),
        ReservationTimeSlot(id: 'b', startTime: '12:00:00', endTime: '18:00:00'),
        ReservationTimeSlot(id: 'c', startTime: '18:00:00', endTime: '22:00:00'),
      ],
      days: ['2026-10-24'],
      states: {
        '2026-10-24': {
          'a': ReservationSlotState(
            status: ReservationSlotStatus.available,
            total: 1,
            remaining: 1,
          ),
          'b': ReservationSlotState(
            status: ReservationSlotStatus.available,
            total: 1,
            remaining: 1,
          ),
          'c': ReservationSlotState(
            status: ReservationSlotStatus.full,
            total: 1,
            remaining: 0,
          ),
        },
      },
    );
  }
}
