import 'dart:convert';

import 'package:bugaoshan/models/course.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/providers/course_provider.dart';

/// Versioned presentation data only. Course validity stays with the upstream model;
/// the form extension chooses today's date and status without opening Flutter's DB.
String buildOhosCourseCardSnapshot(
  CourseProvider provider,
  AppConfigProvider settings,
) {
  if (provider.isLoading.value) {
    throw StateError('The selected schedule is still loading');
  }
  final config = provider.scheduleConfig.value;
  final hasSchedule = provider.hasSchedule && config != null;
  final snapshot = <String, Object?>{
    'schemaVersion': 1,
    'hasSchedule': hasSchedule,
    'language': settings.locale.value?.languageCode ?? '',
    'showTomorrow': settings.widgetShowTomorrow.value,
    'courses': <Map<String, Object?>>[],
  };
  if (config == null || !hasSchedule) return jsonEncode(snapshot);

  DateTime day(DateTime date) => DateTime.utc(date.year, date.month, date.day);
  String dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // Bound invalid imported metadata before iterating. Native also validates the
  // snapshot and clears invalid data to a sync hint instead of showing old courses.
  if (config.totalWeeks < 1 || config.totalWeeks > 60) {
    snapshot['totalWeeks'] = 0;
    return jsonEncode(snapshot);
  }

  final end = day(config.semesterStartDate).add(
    Duration(days: config.totalWeeks * 7 - 1),
  );
  DateTime? nextStart;
  for (final schedule in provider.allSchedules.value) {
    final start = day(schedule.semesterStartDate);
    if (schedule.id != config.id &&
        start.isAfter(end) &&
        (nextStart == null || start.isBefore(nextStart))) {
      nextStart = start;
    }
  }
  snapshot['semesterStart'] = dateText(config.semesterStartDate);
  snapshot['totalWeeks'] = config.totalWeeks;
  snapshot['nextSemesterStart'] = nextStart == null ? '' : dateText(nextStart);

  int timeMinutes(int section, {required bool isEnd}) {
    if (section < 1 || section > config.timeSlots.length) return -1;
    final slot = config.timeSlots[section - 1];
    final time = isEnd ? slot.endTime : slot.startTime;
    return time.hour * 60 + time.minute;
  }

  snapshot['courses'] = provider.courses.value.map((Course course) {
    return <String, Object?>{
      'id': course.id,
      'name': course.name,
      'location': course.location,
      'dayOfWeek': course.dayOfWeek,
      'activeWeeks': [
        for (var week = 1; week <= config.totalWeeks; week++)
          if (course.isActiveInWeek(week)) week,
      ],
      'startSection': course.startSection < 0 ? 0 : course.startSection,
      'endSection': course.endSection < 0 ? 0 : course.endSection,
      'startMinutes': timeMinutes(course.startSection, isEnd: false),
      'endMinutes': timeMinutes(course.endSection, isEnd: true),
      'colorValue': course.colorValue & 0xffffffff,
    };
  }).toList();
  return jsonEncode(snapshot);
}
