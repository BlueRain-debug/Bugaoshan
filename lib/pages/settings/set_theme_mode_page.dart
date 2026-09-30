import 'package:flutter/material.dart';
import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';

/// 深色模式设置页：跟随系统 / 浅色 / 深色，选择后立即生效并持久化。
class SetThemeModePage extends StatelessWidget {
  const SetThemeModePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appConfig = getIt<AppConfigProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.darkMode)),
      body: Center(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: appConfig.themeMode,
          builder: (context, mode, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  label: Text(l10n.followSystem),
                  icon: const Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text(l10n.themeModeLight),
                  icon: const Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text(l10n.themeModeDark),
                  icon: const Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selected) {
                appConfig.themeMode.value = selected.first;
              },
            ),
          ),
        ),
      ),
    );
  }
}
