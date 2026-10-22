import 'package:bugaoshan/pages/campus/reservation/models/reservation_models.dart';
import 'package:bugaoshan/services/api/reservation_api_service.dart';
import 'package:bugaoshan/services/auth/scu_exceptions.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:flutter/foundation.dart';

/// 预约页加载状态。
enum ReservationLoadState { idle, loading, loaded, error }

/// 预约页失败原因，决定错误态文案与动作。
enum ReservationErrorKind {
  /// 统一认证未登录，或预约系统会话未建立（自愈重试后仍失败）。
  unauthenticated,

  /// 网络 / 接口 / 解析等其它错误。
  failed,
}

/// 预约系统页面状态（资源列表 + 选中资源的日历）。
///
/// 数据链：`ReservationApiService.fetchResources`（专题资源）→
/// 选中资源后 `fetchCalendar`（未来 7 天 × 时段）。只读，不提交预约。
class ReservationProvider extends ChangeNotifier {
  static const String _tag = 'ReservationProvider';

  /// 一次展示的天数（服务端接受任意区间，7 天刚好一屏）。
  static const int visibleDays = 7;

  ReservationProvider(this._api);

  final ReservationApi _api;

  ReservationLoadState _state = ReservationLoadState.idle;
  ReservationErrorKind? _errorKind;
  String? _errorMessage;
  int _generation = 0;

  List<ReservationResource> _resources = const [];
  String? _selectedResourceId;
  ReservationCalendar? _calendar;

  /// 日历查询区间的第一天（默认今天）。
  DateTime _rangeStart = _dateOnly(DateTime.now());

  ReservationLoadState get state => _state;
  ReservationErrorKind? get errorKind => _errorKind;
  String? get errorMessage => _errorMessage;

  List<ReservationResource> get resources => List.unmodifiable(_resources);
  String? get selectedResourceId => _selectedResourceId;
  ReservationCalendar? get calendar => _calendar;
  DateTime get rangeStart => _rangeStart;

  ReservationResource? get selectedResource {
    final id = _selectedResourceId;
    if (id == null) return null;
    for (final resource in _resources) {
      if (resource.id == id) return resource;
    }
    return null;
  }

  /// 首次进入：拉资源列表，并默认选中第一个资源查日历。
  Future<void> ensureLoaded() async {
    if (_state == ReservationLoadState.loaded) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_state == ReservationLoadState.loading) return;
    final generation = ++_generation;
    _state = ReservationLoadState.loading;
    _errorKind = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final resources = await _api.fetchResources();
      if (generation != _generation) return;
      _resources = resources;
      final selected = _selectedResourceId ?? resources.firstOrNull?.id;
      _selectedResourceId = selected;
      _state = ReservationLoadState.loaded;
      notifyListeners();

      if (selected != null) {
        await _loadCalendar(selected, generation: generation);
      }
    } on UnauthenticatedException {
      if (generation != _generation) return;
      _state = ReservationLoadState.error;
      _errorKind = ReservationErrorKind.unauthenticated;
      notifyListeners();
    } catch (e, logStackTrace) {
      if (generation != _generation) return;
      AppLog.e(_tag, 'refresh 失败', error: e, stackTrace: logStackTrace);
      _state = ReservationLoadState.error;
      _errorKind = ReservationErrorKind.failed;
      _errorMessage = e is ServiceException ? e.message : null;
      notifyListeners();
    }
  }

  /// 切换选中资源并重新查日历。
  Future<void> selectResource(String resourceId) async {
    if (_selectedResourceId == resourceId && _calendar != null) return;
    _selectedResourceId = resourceId;
    _calendar = null;
    notifyListeners();
    await _loadCalendar(resourceId, generation: ++_generation);
  }

  /// 日历区间前移 / 后移 [visibleDays] 天。
  Future<void> shiftRange(int days) async {
    final resourceId = _selectedResourceId;
    if (resourceId == null) return;
    _rangeStart = _rangeStart.add(Duration(days: days));
    _calendar = null;
    notifyListeners();
    await _loadCalendar(resourceId, generation: ++_generation);
  }

  /// 回到以今天为起点的区间。
  Future<void> resetRange() async {
    final resourceId = _selectedResourceId;
    if (resourceId == null) return;
    _rangeStart = _dateOnly(DateTime.now());
    _calendar = null;
    notifyListeners();
    await _loadCalendar(resourceId, generation: ++_generation);
  }

  Future<void> _loadCalendar(
    String resourceId, {
    required int generation,
  }) async {
    final start = _rangeStart;
    final end = start.add(const Duration(days: visibleDays - 1));
    try {
      final calendar = await _api.fetchCalendar(
        resourceId: resourceId,
        startDate: start,
        endDate: end,
      );
      if (generation != _generation) return;
      _calendar = calendar;
      _state = ReservationLoadState.loaded;
      _errorKind = null;
      _errorMessage = null;
    } on UnauthenticatedException {
      if (generation != _generation) return;
      _state = ReservationLoadState.error;
      _errorKind = ReservationErrorKind.unauthenticated;
    } catch (e, logStackTrace) {
      if (generation != _generation) return;
      AppLog.e(_tag, 'loadCalendar 失败', error: e, stackTrace: logStackTrace);
      _state = ReservationLoadState.error;
      _errorKind = ReservationErrorKind.failed;
      _errorMessage = e is ServiceException ? e.message : null;
    }
    notifyListeners();
  }

  /// 登出时复位。
  void clear() {
    _generation++;
    _resources = const [];
    _selectedResourceId = null;
    _calendar = null;
    _state = ReservationLoadState.idle;
    _errorKind = null;
    _errorMessage = null;
    notifyListeners();
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
