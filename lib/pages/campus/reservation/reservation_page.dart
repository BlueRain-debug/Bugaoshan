import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/pages/campus/reservation/models/reservation_models.dart';
import 'package:bugaoshan/pages/auth/scu_login_page.dart';
import 'package:bugaoshan/providers/reservation_provider.dart';
import 'package:bugaoshan/providers/scu_auth_provider.dart';
import 'package:bugaoshan/services/auth/scu_auth.dart';
import 'package:bugaoshan/theme_shape.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/utils/constants.dart';
import 'package:bugaoshan/utils/open_link.dart';
import 'package:bugaoshan/utils/system_insets.dart';
import 'package:bugaoshan/widgets/common/loading_widgets.dart';
import 'package:bugaoshan/widgets/common/login_required_widget.dart';
import 'package:bugaoshan/widgets/common/retryable_error_widget.dart';
import 'package:bugaoshan/widgets/common/styled_card.dart';
import 'package:bugaoshan/widgets/dialog/dialog.dart';
import 'package:bugaoshan/widgets/route/router_utils.dart';
import 'package:flutter/material.dart';

/// 望江校区研究生活动室预约（只读查询）。
///
/// 展示专题 [kReservationTopicId] 下的活动室，以及选中活动室未来若干天的
/// 时段占用情况。**不代提交预约**：该校资源必须审批（提交后 30 分钟内上传
/// 申请表），代提交涉及短信验证码、附件与审批流，第一版只做到「查空闲 +
/// 跳官方页面」。
class ReservationPage extends StatefulWidget {
  const ReservationPage({super.key});

  @override
  State<ReservationPage> createState() => _ReservationPageState();
}

class _ReservationPageState extends State<ReservationPage>
    with WidgetsBindingObserver {
  static const String _tag = 'ReservationPage';

  late final ReservationProvider _provider;
  late final ScuAuthProvider _auth;
  bool _recoveringSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _provider = getIt<ReservationProvider>();
    _auth = getIt<ScuAuthProvider>();
    _auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onAuthChanged();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 页面跨夜挂着再回到前台时，把区间夹回今天，避免继续展示昨天的日历。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _provider.ensureRangeNotPast();
    }
  }

  void _onAuthChanged() {
    final auth = getIt<ScuAuthProvider>();
    if (auth.isLoggedIn) {
      _provider.ensureLoaded();
    } else if (!auth.isAutoLoggingIn &&
        !_recoveringSession &&
        auth.accessToken != null) {
      _recoverSession();
    }
  }

  Future<void> _recoverSession() async {
    setState(() => _recoveringSession = true);
    try {
      await getIt<ScuAuth>().refresh();
    } catch (e, logStackTrace) {
      AppLog.e(_tag, '_recoverSession 失败', error: e, stackTrace: logStackTrace);
    } finally {
      if (mounted) setState(() => _recoveringSession = false);
    }
  }

  void _openLoginPage() {
    popupOrNavigate(context, const ScuLoginPage());
  }

  Future<void> _openOfficialPage() async {
    await openLink(kReservationSpecialPageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: Listenable.merge([_provider, getIt<ScuAuthProvider>()]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(l10n.reservationTitle),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            onPressed: () => popDialog(),
          ),
          actions: [
            if (getIt<ScuAuthProvider>().isLoggedIn &&
                _provider.state != ReservationLoadState.loading)
              IconButton(
                tooltip: l10n.refresh,
                onPressed: _provider.refresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: _buildBody(l10n),
        bottomNavigationBar: _buildBottomBar(l10n),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final auth = getIt<ScuAuthProvider>();

    if (!auth.isLoggedIn) {
      return auth.isAutoLoggingIn || _recoveringSession
          ? const AutoLoginLoadingWidget()
          : const LoginRequiredWidget();
    }

    if (_provider.state == ReservationLoadState.loading &&
        _provider.calendar == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_provider.errorKind == ReservationErrorKind.unauthenticated) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.reservationSessionExpired,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openLoginPage,
                icon: const Icon(Icons.login),
                label: Text(l10n.goToLogin),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _provider.refresh,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_provider.errorKind != null) {
      return RetryableErrorWidget.message(
        message: _provider.errorMessage ?? l10n.loadFailed,
        onRetry: _provider.refresh,
      );
    }

    if (_provider.resources.isEmpty) {
      return Center(
        child: Text(
          l10n.reservationNoResources,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _provider.refresh,
      child: ListView(
        padding: withSystemBottomInset(
          context,
          const EdgeInsets.all(AppShapes.large),
        ),
        children: [
          _buildResourcePicker(l10n),
          const SizedBox(height: AppShapes.large),
          _buildCalendar(l10n),
        ],
      ),
    );
  }

  /// 资源选择：横向滚动的胶囊。
  Widget _buildResourcePicker(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reservationChooseRoom,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppShapes.small),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _provider.resources.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppShapes.small),
            itemBuilder: (context, index) {
              final resource = _provider.resources[index];
              final selected = resource.id == _provider.selectedResourceId;
              return ChoiceChip(
                label: Text(resource.name),
                selected: selected,
                onSelected: (_) => _provider.selectResource(resource.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar(AppLocalizations l10n) {
    final calendar = _provider.calendar;
    final resource = _provider.selectedResource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (resource != null) ...[
          _buildResourceInfo(resource, l10n),
          const SizedBox(height: AppShapes.large),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.reservationAvailability,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            // 翻走之后给一条回到今天的捷径；已经在今天这一屏时禁用。
            TextButton(
              onPressed: _provider.isAtTodayRange
                  ? null
                  : () => _provider.resetRange(),
              child: Text(l10n.reservationBackToToday),
            ),
            IconButton(
              tooltip: l10n.reservationPreviousWeek,
              onPressed: _provider.isAtTodayRange
                  ? null
                  : () => _provider.shiftRange(
                      -ReservationProvider.visibleDays,
                    ),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: l10n.reservationNextWeek,
              onPressed: () => _provider.shiftRange(
                ReservationProvider.visibleDays,
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: AppShapes.small),
        if (calendar == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (calendar.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l10n.reservationNoSlots,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          _buildCalendarGrid(calendar, l10n),
        const SizedBox(height: AppShapes.large),
        _buildLegend(l10n),
      ],
    );
  }

  Widget _buildResourceInfo(ReservationResource resource, AppLocalizations l10n) {
    return StyledCard(
      padding: const EdgeInsets.all(AppShapes.large),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resource.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (resource.attributes.isNotEmpty) ...[
            const SizedBox(height: AppShapes.small),
            Wrap(
              spacing: AppShapes.small,
              runSpacing: AppShapes.xs,
              children: [
                for (final attribute in resource.attributes)
                  Text(
                    '${attribute.name}：${attribute.value}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppShapes.small),
          Wrap(
            spacing: AppShapes.small,
            runSpacing: AppShapes.xs,
            children: [
              if (resource.needsApproval)
                _InfoChip(label: l10n.reservationNeedsApproval),
              if (resource.maxPeriodsPerDay > 0)
                _InfoChip(
                  label: l10n.reservationDailyLimit(resource.maxPeriodsPerDay),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 日期 × 时段的网格：行为时段，列为日期。
  ///
  /// 时段列固定在左侧，只有日期列横向滚动——否则横滑后连「几点到几点」
  /// 都被滚走，用户不知道看的是哪一行。
  ///
  /// 不用 `DataTable`：它在横屏 / 小高度弹窗里会被父级压扁（实测行高
  /// 只剩 11px），`dataRowMinHeight` 也兜不住。这里用手工 Row/Column
  /// 布局，行高由 `SizedBox` 写死，超出部分交给外层 ListView 滚动。
  Widget _buildCalendarGrid(ReservationCalendar calendar, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    const headingHeight = 44.0;
    const rowHeight = 48.0;
    const dayWidth = 72.0;
    final gridHeight = headingHeight + calendar.slots.length * rowHeight;

    return SizedBox(
      height: gridHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 固定列：时段
          SizedBox(
            width: 108,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: headingHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.reservationTimeColumn,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                for (final slot in calendar.slots)
                  SizedBox(
                    height: rowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(slot.label, style: textStyle),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: gridHeight,
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          // 可滚动列：日期
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: headingHeight,
                    child: Row(
                      children: [
                        for (final day in calendar.days)
                          SizedBox(
                            width: dayWidth,
                            child: Center(
                              child: Text(
                                _dayLabel(day),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final slot in calendar.slots)
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: [
                          for (final day in calendar.days)
                            SizedBox(
                              width: dayWidth,
                              child: Center(
                                child: _SlotCell(
                                  state: calendar.stateOf(day, slot.id),
                                  onTap: () =>
                                      _onSlotTap(day, slot, calendar),
                                ),
                              ),
                            ),
                        ],
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

  Future<void> _onSlotTap(
    String day,
    ReservationTimeSlot slot,
    ReservationCalendar calendar,
  ) async {
    final state = calendar.stateOf(day, slot.id);
    if (!state.bookable) return;

    final l10n = AppLocalizations.of(context)!;
    // 只读页面：可预约时引导去官方页面完成提交（含验证码与申请表上传）。
    //
    // 用 `showYesNoDialog` 而不是 `showInfoDialog`：后者只有一个按钮，且
    // `barrierDismissible: true` 时点遮罩同样会完成 future —— 用户只是想把
    // 弹窗关掉，却会被直接拉起浏览器。这里必须拿到明确的「确认」意图。
    final confirmed = await showYesNoDialog(
      title: l10n.reservationGoOfficialTitle,
      content: l10n.reservationGoOfficialBody('${_dayLabel(day)} ${slot.label}'),
    );
    if (confirmed != true || !mounted) return;
    await _openOfficialPage();
  }

  Widget _buildLegend(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppShapes.large,
      runSpacing: AppShapes.small,
      children: [
        _LegendDot(
          color: _slotStatusColor(scheme, ReservationSlotStatus.available),
          label: l10n.reservationStatusAvailable,
        ),
        _LegendDot(
          color: _slotStatusColor(scheme, ReservationSlotStatus.full),
          label: l10n.reservationStatusFull,
        ),
        _LegendDot(
          color: _slotStatusColor(scheme, ReservationSlotStatus.notOpen),
          label: l10n.reservationStatusUnavailable,
        ),
      ],
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    if (!getIt<ScuAuthProvider>().isLoggedIn) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppShapes.large,
          AppShapes.small,
          AppShapes.large,
          AppShapes.small,
        ),
        child: OutlinedButton.icon(
          onPressed: _openOfficialPage,
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.reservationGoOfficial),
        ),
      ),
    );
  }

  static String _dayLabel(String day) {
    // `YYYY-MM-DD` → `M/D`，保持表头紧凑。
    final parts = day.split('-');
    if (parts.length != 3) return day;
    final month = int.tryParse(parts[1]);
    final date = int.tryParse(parts[2]);
    if (month == null || date == null) return day;
    return '$month/$date';
  }
}

/// 时段状态 → 展示色。图例与格子共用同一套取色，避免「图例一个色、
/// 格子另一个色」对不上号。
Color _slotStatusColor(ColorScheme scheme, ReservationSlotStatus status) =>
    switch (status) {
      ReservationSlotStatus.available => scheme.primary,
      ReservationSlotStatus.full => scheme.error,
      ReservationSlotStatus.notOpen ||
      ReservationSlotStatus.expired ||
      ReservationSlotStatus.disabled => scheme.onSurfaceVariant,
    };

/// 单元格：可约显示剩余数，约满显示「满」，其余显示「—」。
class _SlotCell extends StatelessWidget {
  const _SlotCell({required this.state, required this.onTap});

  final ReservationSlotState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (state.bookable) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppShapes.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppShapes.small,
            vertical: 4,
          ),
          child: Text(
            l10n.reservationRemaining(state.remaining),
            style: TextStyle(
              color: _slotStatusColor(scheme, ReservationSlotStatus.available),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final text = switch (state.status) {
      ReservationSlotStatus.full => l10n.reservationStatusFull,
      ReservationSlotStatus.notOpen => l10n.reservationStatusUnavailable,
      ReservationSlotStatus.expired => l10n.reservationStatusUnavailable,
      ReservationSlotStatus.disabled => l10n.reservationStatusUnavailable,
      ReservationSlotStatus.available => l10n.reservationStatusUnavailable,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppShapes.small,
        vertical: 4,
      ),
      child: Text(
        text,
        style: TextStyle(color: _slotStatusColor(scheme, state.status)),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppShapes.small,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppShapes.small),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
