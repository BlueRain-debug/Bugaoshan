import 'package:bugaoshan/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/utils/app_log.dart';

Future<void> openLink(String link, {BuildContext? context}) async {
  try {
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('No application accepted the link');
  } catch (error) {
    AppLog.e('OpenLink', 'External link failed: $error');
    if (context != null && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.open}: ${l10n.operationFailed}')),
      );
    }
  }
}

Future<void> openProjectRepository({BuildContext? context}) async {
  await openLink(appLink, context: context);
}

Future<void> openOfficialWebsite({BuildContext? context}) async {
  await openLink(officialWebsiteLink, context: context);
}

Future<void> openUserManual({BuildContext? context}) async {
  await openLink(userManualLink, context: context);
}

Future<void> openDeveloperTeam({BuildContext? context}) async {
  await openLink(orgLink, context: context);
}

Future<void> openLicense({BuildContext? context}) async {
  await openLink("$appLink/blob/main/LICENSE", context: context);
}
