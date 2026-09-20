import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/services/auth/scu_exceptions.dart';
import 'package:bugaoshan/widgets/common/retryable_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 线 A 回归：本科教务在统一认证已建立仍踢回登录页（undergradOnly）时，
/// 错误映射与渲染给出针对性提示、不放永远无效的重试按钮。
void main() {
  group('zhjwAuthErrorType 映射', () {
    test('带 undergradOnly 标记 → undergradOnly', () {
      expect(
        zhjwAuthErrorType(
          const UnauthenticatedException('本科教务会话未建立', true),
        ),
        LoadErrorType.undergradOnly,
      );
    });

    test('普通未登录异常沿用调用方原分类（默认 sessionExpired）', () {
      expect(
        zhjwAuthErrorType(const UnauthenticatedException()),
        LoadErrorType.sessionExpired,
      );
    });

    test('exam_plan 场景：未标记时回落 notLoggedIn', () {
      expect(
        zhjwAuthErrorType(
          const UnauthenticatedException(),
          fallback: LoadErrorType.notLoggedIn,
        ),
        LoadErrorType.notLoggedIn,
      );
      expect(
        zhjwAuthErrorType(
          const UnauthenticatedException('本科教务会话未建立', true),
          fallback: LoadErrorType.notLoggedIn,
        ),
        LoadErrorType.undergradOnly,
      );
    });
  });

  group('RetryableErrorWidget 渲染', () {
    Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: child),
    );

    testWidgets('undergradOnly 显示针对性提示，重试与前往登录按钮齐备', (tester) async {
      await tester.pumpWidget(
        wrap(
          const RetryableErrorWidget(
            errorType: LoadErrorType.undergradOnly,
            onRetry: _noRetry,
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(RetryableErrorWidget)),
      )!;
      expect(find.text(l10n.undergradDataOnly), findsOneWidget);
      expect(find.text(l10n.retry), findsOneWidget);
      expect(find.text(l10n.goToLogin), findsOneWidget);
    });

    testWidgets('其它错误类型仍显示重试按钮', (tester) async {
      await tester.pumpWidget(
        wrap(
          const RetryableErrorWidget(
            errorType: LoadErrorType.sessionExpired,
            onRetry: _noRetry,
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(RetryableErrorWidget)),
      )!;
      expect(find.text(l10n.retry), findsOneWidget);
    });
  });
}

void _noRetry() {}
