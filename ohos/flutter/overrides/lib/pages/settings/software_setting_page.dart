import 'dart:io';

import 'package:bugaoshan/providers/scu_auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/pages/settings/add_widget/add_widget_page.dart';
import 'package:bugaoshan/pages/settings/set_dock_page.dart';
import 'package:bugaoshan/pages/settings/set_duration_page.dart';
import 'package:bugaoshan/pages/settings/set_language_page.dart';
import 'package:bugaoshan/pages/settings/set_app_icon_page.dart';
import 'package:bugaoshan/pages/settings/set_course_style_page.dart';
import 'package:bugaoshan/pages/settings/set_font_page.dart';
import 'package:bugaoshan/pages/settings/set_theme_color_page.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/providers/course_provider.dart';
import 'package:bugaoshan/services/dynamic_icon_service.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/widgets/common/info_card.dart';
import 'package:bugaoshan/widgets/common/section_title.dart';
import 'package:bugaoshan/widgets/common/styled_tile.dart';
import 'package:bugaoshan/widgets/dialog/dialog.dart';
import 'package:bugaoshan/widgets/route/router_utils.dart';

class SoftwareSettingPage extends StatelessWidget {
  const SoftwareSettingPage({super.key});

  Future<void> _openAppIconSettings(BuildContext context) async {
    if (Platform.operatingSystem == 'ohos') {
      String? message;
      try {
        final supported = await DynamicIconService.supportsAlternateIcons();
        if (!context.mounted) return;
        if (!supported) {
          message = AppLocalizations.of(context)!.ohosIconRequiresHarmonyOS7;
        }
      } catch (error) {
        AppLog.e('DynamicIcon', 'Failed to check icon support: $error');
        if (!context.mounted) return;
        message = AppLocalizations.of(context)!.loadFailed;
      }
      if (!context.mounted) return;
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        return;
      }
    }
    if (!context.mounted) return;
    popupOrNavigate(context, const SetAppIconPage());
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appConfig = getIt<AppConfigProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(localizations.softwareSetting)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          SectionTitle(title: localizations.settingsGeneral),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.language,
                label: localizations.modifyLanguage,
                onTap: () => popupOrNavigate(context, SetLanguagePage()),
              ),
              if (Platform.isAndroid || Platform.operatingSystem == 'ohos')
                IconTile(
                  icon: Icons.photo_size_select_actual_outlined,
                  label: localizations.appIcon,
                  onTap: () => _openAppIconSettings(context),
                ),
              IconTile(
                icon: Icons.timer,
                label: localizations.animationDuration,
                onTap: () => popupOrNavigate(context, SetDurationPage()),
              ),
              IconTile(
                icon: Icons.dock_outlined,
                label: localizations.customDock,
                onTap: () => popupOrNavigate(context, const SetDockPage()),
              ),
              if (Platform.isAndroid || Platform.operatingSystem == 'ohos')
                IconTile(
                  icon: Icons.widgets_outlined,
                  label: localizations.addWidgetPageTitle,
                  onTap: () => popupOrNavigate(context, const AddWidgetPage()),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SectionTitle(title: localizations.settingsStyle),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.color_lens,
                label: localizations.themeColor,
                onTap: () => popupOrNavigate(context, SetThemeColorPage()),
              ),
              IconTile(
                icon: Icons.style,
                label: localizations.courseStyleSetting,
                onTap: () =>
                    popupOrNavigate(context, const SetCourseStylePage()),
              ),
              IconTile(
                icon: Icons.font_download,
                label: localizations.setFont,
                onTap: () => popupOrNavigate(context, const SetFontPage()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SectionTitle(title: localizations.settingsDanger),
          InfoCard(
            children: [
              IconTile(
                icon: Icons.delete,
                iconColor: Colors.red,
                label: localizations.clearAllData,
                labelColor: Colors.red,
                onTap: () async {
                  final confirm = await showYesNoDialog(
                    title: localizations.clearAllData,
                    content: localizations.confirmMessage,
                  );
                  if (confirm == true) {
                    final scuAuth = getIt<ScuAuthProvider>();
                    await scuAuth.logout();
                    await scuAuth.clearCredentials();
                    await appConfig.clearAll();
                    final courseProvider = getIt<CourseProvider>();
                    await courseProvider.clearAllData();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
