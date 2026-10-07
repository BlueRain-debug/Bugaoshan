import 'dart:async';

import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/services/reminder/reminder_service.dart';
import 'package:bugaoshan/widgets/common/info_card.dart';
import 'package:bugaoshan/widgets/common/section_title.dart';
import 'package:bugaoshan/widgets/common/styled_card.dart';
import 'package:bugaoshan/widgets/common/styled_tile.dart';
import 'package:flutter/material.dart';

/// 「通知与提醒」设置页。
///
/// 本地提醒的失败症状高度同质：Dart 算错、未授权、系统超限、原生未接线，
/// 四种情况在用户看来都是「没有提醒」。因此本页除了开关，还必须把
/// **授权状态**与**排期状态**摆出来——否则用户只能反馈「不工作」。
class ReminderSettingPage extends StatefulWidget {
  const ReminderSettingPage({super.key});

  @override
  State<ReminderSettingPage> createState() => _ReminderSettingPageState();
}

class _ReminderSettingPageState extends State<ReminderSettingPage>
    with WidgetsBindingObserver {
  final _appConfig = getIt<AppConfigProvider>();
  final _service = getIt<ReminderService>();

  /// `null` = 尚未查询。取值与原生状态字符串一致。
  String? _permissionStatus;
  bool _requestingPermission = false;
  int? _pendingCount;
  bool _refreshing = false;

  /// 关掉免打扰时记住的时刻，重新打开时还原。
  ///
  /// 不记的话「关掉又打开」会把用户设过的 22:30–06:30 悄悄换成 23:00–07:00——
  /// 一个看起来无害、但确实改动了用户数据的开关。
  TimeOfDay? _lastQuietStart;
  TimeOfDay? _lastQuietEnd;

  /// 多选提前量的候选项。取值依据：5 分钟适合教学楼就在隔壁的场景，
  /// 60 分钟适合需要跨校区通勤的场景；中间三档覆盖大多数情况。
  static const List<int> _leadChoices = [5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastQuietStart = _appConfig.reminderQuietStart.value;
    _lastQuietEnd = _appConfig.reminderQuietEnd.value;
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 失败路径需要用户去系统设置里改，而系统设置是另一个应用：本页重新可见时
    // 必须重查，否则用户授权完回来看到的还是那张「未授权」卡片。
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    // 排期是 debounce 后异步完成的，立刻查 pendingCount 只会拿到上一批的条数，
    // 界面上就会出现「已排期 15 条 / 系统已登记 0 条」。给一次机会让下发先落地。
    await _service.reschedule(force: true);
    final status = await _service.permissionStatus();
    final pending = await _service.pendingCount();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _pendingCount = pending;
    });
  }

  bool get _isGranted =>
      _permissionStatus == 'authorized' || _permissionStatus == 'provisional';

  Future<void> _toggleMaster(bool enabled) async {
    _appConfig.reminderEnabled.value = enabled;
    // 打开总开关时若尚未授权，顺手请求一次——否则用户开了开关却收不到提醒，
    // 而界面上没有任何提示。
    if (enabled && !_isGranted && _permissionStatus == 'notDetermined') {
      await _requestPermission();
      return;
    }
    await _refreshStatus();
  }

  Future<void> _requestPermission() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // 被拒之后系统不再弹框（iOS 上 requestAuthorization 直接返回 false），
    // 再点按钮是死路，改为把用户送到系统设置。
    if (_permissionStatus == 'denied') {
      final opened = await _service.openNotificationSettings();
      if (!opened && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.reminderPermissionOpenFailed)),
        );
      }
      return;
    }
    setState(() => _requestingPermission = true);
    try {
      final granted = await _service.requestPermission();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? l10n.reminderPermissionGrantedToast
                : l10n.reminderPermissionDeniedToast,
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.reminderPermissionFailed}: $e')),
      );
    } finally {
      await _refreshStatus();
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _pickQuietTime({required bool isStart}) async {
    final current = isStart
        ? _appConfig.reminderQuietStart.value
        : _appConfig.reminderQuietEnd.value;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          current ?? TimeOfDay(hour: isStart ? 23 : 7, minute: isStart ? 0 : 0),
    );
    if (picked == null) return;
    if (isStart) {
      _appConfig.reminderQuietStart.value = picked;
    } else {
      _appConfig.reminderQuietEnd.value = picked;
    }
  }

  Future<void> _refreshPlan() async {
    setState(() => _refreshing = true);
    try {
      // _refreshStatus 内部已包含一次强制重排，不必在这里重复调用。
      await _refreshStatus();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reminderSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // 权限先于开关：没有授权时下面所有开关都没有实际效果，
          // 把这一段放最前面可以避免用户在设置里徒劳地反复开关。
          if (!_isGranted) ...[
            _buildPermissionCard(l10n),
            const SizedBox(height: 14),
          ],
          SectionTitle(title: l10n.settingsGeneral),
          InfoCard(children: [_buildMasterSwitch(l10n)]),
          const SizedBox(height: 14),
          _buildCourseSection(l10n),
          const SizedBox(height: 14),
          _buildQuietSection(l10n),
          const SizedBox(height: 14),
          _buildStatusSection(l10n),
          const SizedBox(height: 14),
          _buildPrivacyHint(l10n),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 权限 ────────────────────────────────────────────────────────

  Widget _buildPermissionCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final denied = _permissionStatus == 'denied';
    // 用中性容器 + 错误色图标/按钮，而不是 errorContainer 实底：
    // 后者在深色主题下是一大块高饱和红，视觉重量远超它承载的信息量
    // （这只是「还没授权」，不是出错）。
    final accent = theme.colorScheme.error;
    return StyledCard(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.notifications_off_outlined, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.reminderPermissionTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    denied
                        ? l10n.reminderPermissionDeniedHint
                        : l10n.reminderPermissionNotDeterminedHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: _requestingPermission
                        ? null
                        : _requestPermission,
                    child: _requestingPermission
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            denied
                                ? l10n.reminderPermissionOpenSettings
                                : l10n.reminderPermissionRequest,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 总开关 ──────────────────────────────────────────────────────

  Widget _buildMasterSwitch(AppLocalizations l10n) {
    return ValueListenableBuilder<bool>(
      valueListenable: _appConfig.reminderEnabled,
      builder: (context, enabled, _) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(l10n.reminderMasterSwitch),
        subtitle: Text(
          l10n.reminderMasterSwitchHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: enabled,
        onChanged: _toggleMaster,
      ),
    );
  }

  // ── 课前提醒 ────────────────────────────────────────────────────

  Widget _buildCourseSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _appConfig.reminderEnabled,
      builder: (context, masterEnabled, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title: l10n.reminderCourseSection),
          Opacity(
            // 总开关关闭时整组置灰但保持可见：直接隐藏会让用户以为功能不存在。
            opacity: masterEnabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !masterEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StyledCard(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.reminderLeadTime,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.reminderLeadTimeHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<List<int>>(
                            valueListenable: _appConfig.reminderLeadMinutes,
                            builder: (context, selected, _) => Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final minutes in _leadChoices)
                                  FilterChip(
                                    label: Text(
                                      l10n.reminderLeadMinutes(minutes),
                                    ),
                                    selected: selected.contains(minutes),
                                    onSelected: (on) {
                                      final next = {...selected};
                                      if (on) {
                                        next.add(minutes);
                                      } else {
                                        next.remove(minutes);
                                      }
                                      // 一个都不选等于关掉课前提醒，但总开关
                                      // 仍显示为开——语义容易误解，因此至少保留一个。
                                      if (next.isEmpty) return;
                                      _appConfig.reminderLeadMinutes.value =
                                          next.toList()..sort();
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.reminderLeadTimeMultiHint,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 免打扰 ──────────────────────────────────────────────────────

  Widget _buildQuietSection(AppLocalizations l10n) {
    return ValueListenableBuilder<bool>(
      valueListenable: _appConfig.reminderEnabled,
      builder: (context, masterEnabled, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title: l10n.reminderQuietSection),
          Opacity(
            opacity: masterEnabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !masterEnabled,
              child: InfoCard(
                children: [
                  ValueListenableBuilder<TimeOfDay?>(
                    valueListenable: _appConfig.reminderQuietStart,
                    builder: (context, start, _) =>
                        ValueListenableBuilder<TimeOfDay?>(
                          valueListenable: _appConfig.reminderQuietEnd,
                          builder: (context, end, _) {
                            final enabled = start != null && end != null;
                            return Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  title: Text(l10n.reminderQuietEnabled),
                                  subtitle: Text(
                                    l10n.reminderQuietHint,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  value: enabled,
                                  onChanged: (on) {
                                    if (on) {
                                      // 还原上次的值；首次打开时才落到默认时段。
                                      final start =
                                          _lastQuietStart ??
                                          const TimeOfDay(hour: 23, minute: 0);
                                      final end =
                                          _lastQuietEnd ??
                                          const TimeOfDay(hour: 7, minute: 0);
                                      _lastQuietStart = start;
                                      _lastQuietEnd = end;
                                      _appConfig.reminderQuietStart.value =
                                          start;
                                      _appConfig.reminderQuietEnd.value = end;
                                    } else {
                                      _lastQuietStart = start;
                                      _lastQuietEnd = end;
                                      _appConfig.reminderQuietStart.value =
                                          null;
                                      _appConfig.reminderQuietEnd.value = null;
                                    }
                                  },
                                ),
                                if (enabled) ...[
                                  IconTile(
                                    icon: Icons.bedtime_outlined,
                                    label: l10n.reminderQuietStart,
                                    value: _hhmm(start),
                                    onTap: () => _pickQuietTime(isStart: true),
                                  ),
                                  IconTile(
                                    icon: Icons.wb_sunny_outlined,
                                    label: l10n.reminderQuietEnd,
                                    value: _hhmm(end),
                                    onTap: () => _pickQuietTime(isStart: false),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 排期状态 ────────────────────────────────────────────────────

  Widget _buildStatusSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title: l10n.reminderStatusSection),
        StyledCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<ReminderPlan?>(
                  valueListenable: _service.lastPlan,
                  builder: (context, plan, _) {
                    if (plan == null) {
                      return Text(
                        l10n.reminderStatusEmpty,
                        style: theme.textTheme.bodySmall,
                      );
                    }
                    if (plan.reminders.isEmpty) {
                      return Text(
                        l10n.reminderStatusNoUpcoming,
                        style: theme.textTheme.bodySmall,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.reminderStatusScheduled(
                            plan.reminders.length,
                            '${plan.windowEnd.month}/${plan.windowEnd.day} '
                            '${plan.windowEnd.hour.toString().padLeft(2, '0')}:'
                            '${plan.windowEnd.minute.toString().padLeft(2, '0')}',
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_pendingCount != null && _isGranted) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.reminderStatusPending(_pendingCount!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (plan.droppedCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.reminderStatusDropped(plan.droppedCount),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _previewOf(plan, l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: _service.lastError,
                  builder: (context, error, _) => error == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.reminderStatusError(error),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _refreshing ? null : _refreshPlan,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.reminderStatusRefresh),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 列出最近的几条提醒，让「已排期 N 条」这句话变得可核对。
  String _previewOf(ReminderPlan plan, AppLocalizations l10n) {
    return plan.reminders
        .take(3)
        .map(
          (r) =>
              '${r.fireAt.month}/${r.fireAt.day} '
              '${r.fireAt.hour.toString().padLeft(2, '0')}:'
              '${r.fireAt.minute.toString().padLeft(2, '0')} '
              '${r.title}',
        )
        .join('\n');
  }

  // ── 隐私提示 ────────────────────────────────────────────────────

  Widget _buildPrivacyHint(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.reminderPrivacyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
