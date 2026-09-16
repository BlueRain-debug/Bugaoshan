import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/providers/course_provider.dart';
import 'package:bugaoshan/services/widget_update_service.dart';
import 'package:bugaoshan/utils/app_log.dart';

/// Owns OH-only lifecycle/settings listeners. Course mutations continue using
/// the upstream onCoursesChanged callback and WidgetUpdateService debounce.
class OhosCourseCardSync with WidgetsBindingObserver {
  final CourseProvider courses;
  final AppConfigProvider settings;
  final WidgetUpdateService service;
  late final Listenable _changes;
  bool _disposed = false;

  OhosCourseCardSync(this.courses, this.settings, this.service) {
    _changes = Listenable.merge([
      courses.allSchedules,
      courses.isLoading,
      settings.widgetShowTomorrow,
      settings.locale,
    ]);
  }

  void start() {
    _changes.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void _sync() {
    if (_disposed || courses.isLoading.value) return;
    unawaited(service.updateWidgetData().catchError((Object error) {
      AppLog.w('OhosCourseCard', 'Snapshot sync failed: $error');
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  @override
  void didChangeLocales(List<Locale>? locales) => _sync();

  void dispose() {
    _disposed = true;
    _changes.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
  }
}
