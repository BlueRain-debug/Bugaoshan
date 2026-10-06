import 'dart:convert';

import 'package:bugaoshan/utils/json_utils.dart';
import 'package:flutter/material.dart';

/// 提醒类型。新增类型时在 [ReminderKind.fromWire] 同步登记，原生侧只做透传。
enum ReminderKind {
  /// 课前提醒：由课表的「星期 + 节次 + 周次」展开得到。
  courseStart('course_start');

  const ReminderKind(this.wire);

  /// 跨 MethodChannel 的稳定标识，不要改（原生侧可能按其分流渠道）。
  final String wire;

  static ReminderKind? fromWire(String? value) {
    for (final kind in ReminderKind.values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// 单条提醒。字段即原生侧投递所需的全部信息——原生不做任何业务推断。
@immutable
class ReminderItem {
  /// 稳定且可推导的标识：同一门课、同一天、同一节次、同一提前量恒等。
  ///
  /// 全量覆盖式重排时，新计划里不存在的 id 会被原生撤销，因此 id 的稳定性
  /// 直接决定「改了课表后旧提醒是否残留」。
  final String id;

  final ReminderKind kind;

  /// 投递时刻（设备本地墙钟语义）。由 Dart 算好，原生不参与换算。
  final DateTime fireAt;

  final String title;
  final String body;

  /// 同组提醒的折叠键：同一天同一门课的多条提前量提醒可折叠展示。
  final String collapseKey;

  const ReminderItem({
    required this.id,
    required this.kind,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.collapseKey,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.wire,
    'fireAt': _iso8601Local(fireAt),
    // epoch 毫秒是原生侧排期实际使用的值；ISO 串仅用于日志与 Dev 页排查。
    'fireAtMillis': fireAt.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'collapseKey': collapseKey,
  };

  /// 解析单条提醒。脏数据（缺 id / 时刻不可解析 / 类型未知）返回 null，
  /// 由调用方跳过该条而不是整批失败。
  static ReminderItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    final id = safeString(json['id']);
    final kind = ReminderKind.fromWire(safeString(json['kind']));
    final fireAt = _parseFireAt(json);
    if (id.isEmpty || kind == null || fireAt == null) return null;
    return ReminderItem(
      id: id,
      kind: kind,
      fireAt: fireAt,
      title: safeString(json['title']),
      body: safeString(json['body']),
      collapseKey: safeString(json['collapseKey']),
    );
  }
}

/// 一批排期计划。原生侧对它的处理必须是**全量替换**（见 I2）。
@immutable
class ReminderPlan {
  /// 契约版本。原生侧据此判断能否解析；不认识的版本应拒绝而非猜测。
  static const int schema = 1;

  /// 计划内容哈希（不含 [generatedAt]）。相同哈希可短路，避免无谓的重排。
  final String planId;

  final DateTime generatedAt;

  /// 计划覆盖的时间窗。窗口结束后原生侧应停止投递并等待下次下发。
  final DateTime windowStart;
  final DateTime windowEnd;

  /// 原生侧应使用的通知渠道标识。
  final String channel;

  final List<ReminderItem> reminders;

  /// 因平台待投递上限被裁掉的条数。非 0 时设置页与日志都应把它显式暴露出来，
  /// 否则「少了几条提醒」在用户看来与「功能坏了」没有区别。
  final int droppedCount;

  const ReminderPlan({
    required this.planId,
    required this.generatedAt,
    required this.windowStart,
    required this.windowEnd,
    required this.channel,
    required this.reminders,
    this.droppedCount = 0,
  });

  bool get isEmpty => reminders.isEmpty;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'planId': planId,
    'generatedAt': _iso8601Local(generatedAt),
    'window': {
      'start': _iso8601Local(windowStart),
      'end': _iso8601Local(windowEnd),
    },
    'channel': channel,
    'reminders': reminders.map((e) => e.toJson()).toList(),
    'droppedCount': droppedCount,
  };

  /// 传给 MethodChannel 的载荷。
  ///
  /// 与 [toJson] 的差别：移除 ISO 时刻串，只保留 epoch 毫秒——跨 channel 传
  /// epoch 整数可完全绕开时区解析分歧。Dev 页需要可读时刻时用 [toJson]。
  Map<String, Object?> toChannelPayload() => {
    'schema': schema,
    'planId': planId,
    'generatedAtMillis': generatedAt.millisecondsSinceEpoch,
    'windowStartMillis': windowStart.millisecondsSinceEpoch,
    'windowEndMillis': windowEnd.millisecondsSinceEpoch,
    'channel': channel,
    'droppedCount': droppedCount,
    'reminders': reminders
        .map(
          (e) => {
            'id': e.id,
            'kind': e.kind.wire,
            'fireAtMillis': e.fireAt.millisecondsSinceEpoch,
            'title': e.title,
            'body': e.body,
            'collapseKey': e.collapseKey,
          },
        )
        .toList(),
  };

  static ReminderPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    if (safeInt(json['schema'], fallback: -1) != schema) return null;
    final window = json['window'];
    final windowMap = window is Map ? window.cast<String, Object?>() : const {};
    final reminders = <ReminderItem>[];
    final rawList = json['reminders'];
    if (rawList is List) {
      for (final entry in rawList) {
        final item = ReminderItem.fromJson(entry);
        if (item != null) reminders.add(item);
      }
    }
    return ReminderPlan(
      planId: safeString(json['planId']),
      generatedAt:
          _parseDate(json['generatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      windowStart:
          _parseDate(windowMap['start']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      windowEnd:
          _parseDate(windowMap['end']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      channel: safeString(json['channel']),
      reminders: reminders,
      droppedCount: safeInt(json['droppedCount']),
    );
  }
}

/// 提醒设置。由调用方从 AppConfigProvider 取出后传入构建器，使构建器保持纯函数。
@immutable
class ReminderSettings {
  /// 课前提醒总开关。
  final bool courseReminderEnabled;

  /// 提前量（分钟），可多选。去重升序后生效。
  final List<int> leadMinutes;

  /// 免打扰时段（含首尾）。为空表示不启用。
  ///
  /// 落入该时段的提醒会被**丢弃**而非延后——一门 08:00 的课在 23:00 提醒没有意义。
  final TimeOfDay? quietStart;
  final TimeOfDay? quietEnd;

  /// 排期窗口长度（天）。窗口越长提醒越不易漏，但会更快触及 iOS 的待投递上限。
  final int windowDays;

  /// 提醒正文是否包含上课地点 / 教师。应与隐私开关同源，锁屏通知同样受其约束。
  final bool includeLocation;
  final bool includeTeacher;

  const ReminderSettings({
    this.courseReminderEnabled = false,
    this.leadMinutes = const [15],
    this.quietStart,
    this.quietEnd,
    this.windowDays = defaultWindowDays,
    this.includeLocation = true,
    this.includeTeacher = true,
  });

  /// 默认排期窗口。
  ///
  /// iOS 只保留每个应用最近的 64 条待投递本地通知。按每天 4~6 节课、每个提前量
  /// 一条估算，7 天约 28~42 条；再多一个提前量就会翻倍并逼近上限。
  static const int defaultWindowDays = 7;

  /// iOS 待投递上限，`ReminderPlanBuilder` 据此裁剪。
  static const int iosPendingNotificationLimit = 64;

  /// 规范化后的提前量：去重、只保留正数、升序。
  List<int> get normalizedLeadMinutes {
    final set = <int>{};
    for (final lead in leadMinutes) {
      if (lead > 0) set.add(lead);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// [time] 是否落在免打扰时段内。支持跨午夜（如 22:00–07:00）。
  bool isQuiet(TimeOfDay time) {
    final start = quietStart;
    final end = quietEnd;
    if (start == null || end == null) return false;
    final t = time.hour * 60 + time.minute;
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    if (s == e) return false;
    if (s < e) return t >= s && t <= e;
    return t >= s || t <= e;
  }
}

/// `yyyy-MM-ddTHH:mm:ss±HH:MM`。
///
/// 刻意不用 `DateTime.toIso8601String()`：它对本地时间不写偏移量，原生侧解析时
/// 会按设备当前时区重新解释，跨时区场景下产生偏移。这里显式带上偏移。
String _iso8601Local(DateTime time) {
  final local = time.isUtc ? time.toLocal() : time;
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final oh = abs.inHours.toString().padLeft(2, '0');
  final om = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}T'
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}'
      '$sign$oh:$om';
}

DateTime? _parseDate(Object? value) {
  final text = safeString(value);
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

/// 从 channel 载荷解析触发时刻：优先 epoch 毫秒，回退 ISO 串。
DateTime? _parseFireAt(Map<String, Object?> json) {
  final millis = json['fireAtMillis'];
  if (millis is num) {
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  }
  return _parseDate(json['fireAt']);
}

/// 计划内容的稳定哈希（FNV-1a 32 位）。
///
/// 不用 `Object.hashCode`：它在不同进程/运行间不保证一致，而原生侧要用这个值
/// 判断「计划是否变化」，跨进程不稳定会让短路判断失效。
String planContentHash(List<ReminderItem> reminders) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;
  var hash = offsetBasis;
  void mix(String text) {
    for (final unit in utf8.encode(text)) {
      hash ^= unit;
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    // 字段之间必须补分隔符：否则 id='ab'+title='c' 与 id='a'+title='bc'
    // 会混出同一串字节，两个内容不同的计划被判成同一个，原生侧直接短路。
    hash ^= 0x1f;
    hash = (hash * prime) & 0xFFFFFFFF;
  }

  for (final item in reminders) {
    mix(item.id);
    mix(item.kind.wire);
    mix(item.fireAt.millisecondsSinceEpoch.toString());
    mix(item.title);
    mix(item.body);
    mix(item.collapseKey);
    // 条目之间用另一个分隔符，避免 ['a',''] 与 ['a'] 混淆。
    mix('\u0000');
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
