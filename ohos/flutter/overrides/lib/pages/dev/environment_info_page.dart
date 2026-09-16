import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/models/version_info.dart';
import 'package:bugaoshan/providers/app_info_provider.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/utils/mobile_device_info.dart';
import 'package:bugaoshan/widgets/common/styled_card.dart';

class EnvironmentInfoPage extends StatefulWidget {
  const EnvironmentInfoPage({super.key});

  @override
  State<EnvironmentInfoPage> createState() => _EnvironmentInfoPageState();
}

class _EnvironmentInfoPageState extends State<EnvironmentInfoPage> {
  final _provider = getIt<AppInfoProvider>();
  late Future<_EnvironmentDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<VersionInfo?> _readVersionInfo() async {
    try {
      return await _provider.getVersionInfo().timeout(
        const Duration(seconds: 5),
      );
    } catch (error) {
      AppLog.e('EnvironmentInfo', 'Failed to read app environment: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readDeviceInfo() async {
    try {
      return await getMobileDeviceInfo();
    } catch (error) {
      AppLog.e('EnvironmentInfo', 'Failed to read device information: $error');
      return null;
    }
  }

  Future<_EnvironmentDetails> _load() async {
    // Start both reads together; either section can still display if one fails.
    final version = _readVersionInfo();
    final device = _readDeviceInfo();
    return _EnvironmentDetails(version: await version, device: await device);
  }

  Map<String, String> _sections(
    _EnvironmentDetails details,
    AppLocalizations l,
  ) {
    final version = details.version;
    final device = details.device;
    return {
      if (version != null) ...{
        'APP': version.app,
        'Environment': version.environment,
        'Flag': version.flag,
        'Build': version.build,
      } else
        'Environment': l.loadFailed,
      'Device': device == null
          ? l.loadFailed
          : device.isEmpty
          ? l.noData
          : device.entries.map((entry) {
              final value = entry.value?.toString().trim() ?? '';
              return '${entry.key}: ${value.isEmpty ? l.noData : value}';
            }).join('\n'),
    };
  }

  Future<void> _copyAll(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.ohosEnvironmentInfoCopied),
        ),
      );
    } catch (error) {
      AppLog.e('EnvironmentInfo', 'Failed to copy environment information: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.ohosEnvironmentInfoCopyFailed,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FutureBuilder<_EnvironmentDetails>(
      future: _future,
      builder: (context, snapshot) {
        final done = snapshot.connectionState == ConnectionState.done;
        final details = done ? snapshot.data : null;
        final sections = details == null
            ? <String, String>{}
            : _sections(details, l);
        return Scaffold(
          appBar: AppBar(
            title: Text(l.environmentInfo),
            actions: [
              if (done && (snapshot.hasError || details?.hasErrors == true))
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l.retry,
                  onPressed: () => setState(() => _future = _load()),
                ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: l.ohosEnvironmentInfoCopyAll,
                onPressed: details == null
                    ? null
                    : () => _copyAll(
                        sections.entries
                            .map((entry) => '${entry.key}\n${entry.value}')
                            .join('\n\n'),
                      ),
              ),
            ],
          ),
          body: details == null
              ? Center(
                  child: snapshot.hasError
                      ? Text(l.loadFailed)
                      : const CircularProgressIndicator(),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entry in sections.entries)
                      _SectionCard(title: entry.key, content: entry.value),
                    if (details.hasErrors)
                      TextButton.icon(
                        onPressed: () => setState(() => _future = _load()),
                        icon: const Icon(Icons.refresh),
                        label: Text(l.retry),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _EnvironmentDetails {
  final VersionInfo? version;
  final Map<String, dynamic>? device;

  const _EnvironmentDetails({required this.version, required this.device});

  bool get hasErrors => version == null || device == null;
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String content;

  const _SectionCard({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return StyledCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            SelectableText(
              content,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
