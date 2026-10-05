import 'package:bugaoshan/utils/app_logger.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/injection/injector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await getIt.reset();
  });
  tearDown(() async {
    await getIt.reset();
  });

  test('认证与业务日志分类，并保留脱敏后的异常和堆栈', () {
    final logger = AppLogger();
    getIt.registerSingleton<AppLogger>(logger);
    logger.i('ScuAuth', '登录开始');
    AppLog.e(
      'GradesProvider',
      '读取成绩失败',
      error: StateError('tokenKey=secret'),
      stackTrace: StackTrace.fromString('https://example.test/?token=secret'),
    );
    expect(logger.entries.first.category, LogCategory.authentication);
    final entry = logger.entries.last;
    expect(entry.category, LogCategory.business);
    expect(entry.level, LogLevel.error);
    expect(entry.error, contains('<redacted>'));
    expect(logger.exportToText(), isNot(contains('secret')));
    expect(logger.exportToText(), contains('[business] [GradesProvider]'));
  });

  test('切换注册实例后业务日志进入新的实例', () async {
    final first = AppLogger();
    getIt.registerSingleton<AppLogger>(first);
    AppLog.i('Test', 'first');
    await getIt.reset();
    final second = AppLogger();
    getIt.registerSingleton<AppLogger>(second);
    AppLog.i('Test', 'second');
    expect(first.entries.single.message, 'first');
    expect(second.entries.single.message, 'second');
  });

  test('异步操作失败留下日志，并保留原异常及堆栈传播', () async {
    final logger = AppLogger();
    getIt.registerSingleton<AppLogger>(logger);
    final failure = StateError('failed');
    await expectLater(
      AppLog.guard<void>('Test', '加载', () async => throw failure),
      throwsA(same(failure)),
    );
    expect(logger.entries.single.stackTrace, isNotEmpty);
    expect(logger.entries.single.message, '加载 失败');
  });

  test('早期日志可被 DI 沿用，缓冲区按容量淘汰旧记录', () {
    AppLog.bootstrapLogger.clear();
    AppLog.e('Startup', 'early failure');
    getIt.registerSingleton<AppLogger>(AppLog.bootstrapLogger);
    expect(getIt<AppLogger>().entries.single.message, 'early failure');
    AppLog.bootstrapLogger.clear();
    final logger = AppLogger(capacity: 2);
    logger.i('Test', '1');
    logger.i('Test', '2');
    logger.i('Test', '3');
    expect(logger.entries.map((entry) => entry.message), ['2', '3']);
  });
}
