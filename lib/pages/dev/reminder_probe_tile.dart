import 'dart:convert';

import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/models/reminder_plan.dart';
import 'package:bugaoshan/services/reminder/reminder_service.dart';
import 'package:bugaoshan/services/reminder/reminder_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dev 页的提醒排期探针。
///
/// 存在的理由：本地提醒是典型的「失败起来和没做一样」的功能。用户报「没有提醒」
/// 时，可能是未授权、窗口过期、闹钟丢失、或排期根本没生成，四者症状完全一样。
/// 这个入口把状态摆出来，并提供一个走真实链路的短延时探针，用来把
/// 「Dart 算错了」与「宿主投递不了」两类问题区分开。
class ReminderProbeTile extends StatefulWidget {
  const ReminderProbeTile({super.key});

  @override
  State<ReminderProbeTile> createState() => _ReminderProbeTileState();
}

class _ReminderProbeTileState extends State<ReminderProbeTile> {
  bool _sending = false;

  Future<void> _fireProbe() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await getIt<ReminderService>().fireProbe(
        title: l10n.reminderProbeTitle,
        body: l10n.reminderProbeBody,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.reminderHostProbeSent)),
      );
    } on ReminderPermissionDenied {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.reminderHostProbeDenied)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.reminderHostProbeFailed}: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _copyPlan(ReminderPlan plan) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final text = const JsonEncoder.withIndent('  ').convert(plan.toJson());
    try {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(SnackBar(content: Text(l10n.reminderPlanCopied)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.reminderPlanFailed}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = getIt<ReminderService>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(l10n.reminderHostProbeTitle),
          subtitle: Text(
            l10n.reminderHostProbeSubtitle,
            style: theme.textTheme.bodySmall,
          ),
          trailing: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed: _fireProbe,
                  child: Text(l10n.reminderHostProbeAction),
                ),
        ),
        ValueListenableBuilder<ReminderPlan?>(
          valueListenable: service.lastPlan,
          builder: (context, plan, _) {
            if (plan == null) {
              return Text(
                l10n.reminderPlanEmpty,
                style: theme.textTheme.bodySmall,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reminderPlanSummary(
                    plan.reminders.length,
                    '${plan.windowEnd.month}/${plan.windowEnd.day} '
                    '${plan.windowEnd.hour.toString().padLeft(2, '0')}:'
                    '${plan.windowEnd.minute.toString().padLeft(2, '0')}',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                if (plan.droppedCount > 0)
                  Text(
                    l10n.reminderPlanDropped(plan.droppedCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                FutureBuilder<int>(
                  future: service.pendingCount(),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Text(
                          l10n.reminderPlanPending(snapshot.data!),
                          style: theme.textTheme.bodySmall,
                        )
                      : const SizedBox.shrink(),
                ),
                if (plan.reminders.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      plan.reminders
                          .take(3)
                          .map(
                            (r) =>
                                '${r.fireAt.month}/${r.fireAt.day} '
                                '${r.fireAt.hour.toString().padLeft(2, '0')}:'
                                '${r.fireAt.minute.toString().padLeft(2, '0')} '
                                '${r.title}',
                          )
                          .join('\n'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _copyPlan(plan),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l10n.reminderPlanCopy),
                  ),
                ),
              ],
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: service.lastError,
          builder: (context, error, _) => error == null
              ? const SizedBox.shrink()
              : Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
        ),
      ],
    );
  }
}
