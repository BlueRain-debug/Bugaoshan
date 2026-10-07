import 'package:bugaoshan/services/reminder/live_activity_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'bugaoshan/live_activity';
  late List<MethodCall> log;
  late LiveActivityService service;

  setUp(() {
    log = <MethodCall>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          MethodCall call,
        ) async {
          log.add(call);
          switch (call.method) {
            case 'isSupported':
              return true;
            case 'start':
              return 'test-activity-id-123';
            case 'update':
              return null;
            case 'end':
              return null;
            default:
              return null;
          }
        });

    service = LiveActivityService();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
  });

  group('LiveActivityService', () {
    test('isSupported 正常返回 true', () async {
      final supported = await service.isSupported();
      expect(supported, isTrue);
      expect(log.single.method, 'isSupported');
    });

    test('isSupported 通道抛异常时安全返回 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (
            MethodCall call,
          ) async {
            throw PlatformException(code: 'ERROR');
          });

      final supported = await service.isSupported();
      expect(supported, isFalse);
    });

    test('start 正确传递课程参数并返回 activityId', () async {
      final now = DateTime(2026, 10, 7, 10, 0);
      final end = DateTime(2026, 10, 7, 11, 40);

      final id = await service.start(
        courseName: '高等数学',
        location: '综合楼C101',
        startAt: now,
        endAt: end,
        nextCourseName: '大学物理',
        nextLocation: '一教A202',
      );

      expect(id, 'test-activity-id-123');
      expect(log.single.method, 'start');
      final args = log.single.arguments as Map<dynamic, dynamic>;
      expect(args['courseName'], '高等数学');
      expect(args['location'], '综合楼C101');
      expect(args['startAtMillis'], now.millisecondsSinceEpoch);
      expect(args['endAtMillis'], end.millisecondsSinceEpoch);
      expect(args['nextCourseName'], '大学物理');
      expect(args['nextLocation'], '一教A202');
    });

    test(
      'start 抛出 NOT_IN_FOREGROUND 时转换为 LiveActivityForegroundRequiredException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              MethodCall call,
            ) async {
              throw PlatformException(
                code: 'NOT_IN_FOREGROUND',
                message: 'Must be foreground',
              );
            });

        expect(
          () => service.start(
            courseName: '高等数学',
            location: 'C101',
            endAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          throwsA(isA<LiveActivityForegroundRequiredException>()),
        );
      },
    );

    test(
      'start 抛出 NOT_AUTHORIZED 时转换为 LiveActivityNotAuthorizedException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              MethodCall call,
            ) async {
              throw PlatformException(
                code: 'NOT_AUTHORIZED',
                message: 'Disabled in settings',
              );
            });

        expect(
          () => service.start(
            courseName: '高等数学',
            location: 'C101',
            endAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          throwsA(isA<LiveActivityNotAuthorizedException>()),
        );
      },
    );

    test(
      'start 抛出 UNSUPPORTED_PLATFORM 时转换为 LiveActivityUnsupportedException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              MethodCall call,
            ) async {
              throw PlatformException(
                code: 'UNSUPPORTED_PLATFORM',
                message: 'Requires iOS 16.1',
              );
            });

        expect(
          () => service.start(
            courseName: '高等数学',
            location: 'C101',
            endAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          throwsA(isA<LiveActivityUnsupportedException>()),
        );
      },
    );

    test('update 正常传递更新参数', () async {
      final end = DateTime(2026, 10, 7, 12, 0);

      await service.update(courseName: '线性代数', endAt: end);

      expect(log.single.method, 'update');
      final args = log.single.arguments as Map<dynamic, dynamic>;
      expect(args['courseName'], '线性代数');
      expect(args['endAtMillis'], end.millisecondsSinceEpoch);
    });

    test(
      'update 抛出 NO_ACTIVE_ACTIVITY 时转换为 LiveActivityNoActiveSessionException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              MethodCall call,
            ) async {
              throw PlatformException(
                code: 'NO_ACTIVE_ACTIVITY',
                message: 'No active activity',
              );
            });

        expect(
          () => service.update(courseName: '线性代数'),
          throwsA(isA<LiveActivityNoActiveSessionException>()),
        );
      },
    );

    test('end 正常调用原生通道', () async {
      await service.end();
      expect(log.single.method, 'end');
    });

    test('非 iOS 平台调用 isSupported 返回 false，start 抛出不支持异常', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(await service.isSupported(), isFalse);
      expect(
        () => service.start(
          courseName: '英语',
          location: 'D201',
          endAt: DateTime.now(),
        ),
        throwsA(isA<LiveActivityUnsupportedException>()),
      );
      // 验证 end() 在非 iOS 平台执行安全静默回退
      await service.end();
      expect(log, isEmpty);
    });
  });
}
