import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/models/campus_item_config.dart';
import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/providers/scu_auth_provider.dart';
import 'package:bugaoshan/utils/app_log.dart';
import 'package:bugaoshan/services/auth/auth_coordinator.dart';
import 'package:bugaoshan/utils/constants.dart';
import 'package:bugaoshan/widgets/common/auth_scoped_indexed_stack.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _attemptAutoLogin();
  }

  Future<void> _attemptAutoLogin() async {
    try {
      await getIt.isReady<ScuAuthProvider>();
      final authProvider = getIt<ScuAuthProvider>();
      if (authProvider.isLoggedIn) {
        unawaited(getIt<AuthCoordinator>().warmUpAll());
        return;
      }
      await authProvider.autoLogin();
    } catch (e) {
      AppLog.w('HomePage', 'Auto login attempt error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildMainScreen();
  }

  Widget _buildUpdateBadge({required Widget child, required bool showBadge}) {
    if (!showBadge) return child;
    return Badge(child: child);
  }

  Widget _buildMainScreen() {
    final appConfig = getIt<AppConfigProvider>();
    final authProvider = getIt<ScuAuthProvider>();
    final l10n = AppLocalizations.of(context)!;

    return ValueListenableBuilder<List<String>>(
      valueListenable: appConfig.visibleDockIds,
      builder: (context, visibleIds, _) {
        _clampCurrentIndex(visibleIds);

        return ValueListenableBuilder<bool>(
          valueListenable: appConfig.hasUpdateNotification,
          builder: (context, hasUpdate, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                final showRail = isWide && visibleIds.length >= 2;
                final showBar = !isWide && visibleIds.length >= 2;
                final pageContent = ListenableBuilder(
                  listenable: Listenable.merge([
                    appConfig.cardSizeAnimationDuration,
                    appConfig.enablePageTransitionAnimation,
                  ]),
                  builder: (context, _) {
                    return AuthScopedIndexedStack(
                      authListenable: authProvider,
                      isAuthenticated: () => authProvider.isLoggedIn,
                      visibleIds: visibleIds,
                      selectedIndex: _currentIndex,
                      duration: appConfig.cardSizeAnimationDuration.value,
                      enableAnimation:
                          appConfig.enablePageTransitionAnimation.value,
                      axis: showRail ? Axis.vertical : Axis.horizontal,
                      pageBuilder: (id) => campusItemConfigById(id).page(),
                    );
                  },
                );
                return Scaffold(
                  body: Row(
                    children: [
                      // Rail placeholder: always present, hidden via Offstage
                      Offstage(
                        offstage: !showRail,
                        child: NavigationRail(
                          selectedIndex: _currentIndex,
                          onDestinationSelected: (index) {
                            setState(() => _currentIndex = index);
                          },
                          labelType: NavigationRailLabelType.all,
                          destinations: visibleIds
                              .map(
                                (id) =>
                                    _buildRailDestination(id, hasUpdate, l10n),
                              )
                              .toList(),
                        ),
                      ),
                      Offstage(
                        offstage: !showRail,
                        child: const VerticalDivider(thickness: 1, width: 1),
                      ),
                      // Page content: always at index 2
                      Expanded(child: SafeArea(child: pageContent)),
                    ],
                  ),
                  bottomNavigationBar: showBar
                      ? NavigationBar(
                          selectedIndex: _currentIndex,
                          onDestinationSelected: (index) {
                            setState(() => _currentIndex = index);
                          },
                          destinations: visibleIds
                              .map(
                                (id) =>
                                    _buildBarDestination(id, hasUpdate, l10n),
                              )
                              .toList(),
                        )
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }

  void _clampCurrentIndex(List<String> ids) {
    if (ids.isEmpty) {
      _currentIndex = 0;
    } else if (_currentIndex >= ids.length) {
      _currentIndex = ids.length - 1;
    }
  }

  NavigationRailDestination _buildRailDestination(
    String id,
    bool hasUpdate,
    AppLocalizations l10n,
  ) {
    final config = campusItemConfigById(id);
    final isProfile = id == dockIdProfile;
    return NavigationRailDestination(
      icon: isProfile
          ? _buildUpdateBadge(showBadge: hasUpdate, child: Icon(config.icon))
          : Icon(config.icon),
      selectedIcon: isProfile
          ? _buildUpdateBadge(
              showBadge: hasUpdate,
              child: Icon(config.selectedIcon),
            )
          : Icon(config.selectedIcon),
      label: Text(config.dockLabel(l10n)),
    );
  }

  NavigationDestination _buildBarDestination(
    String id,
    bool hasUpdate,
    AppLocalizations l10n,
  ) {
    final config = campusItemConfigById(id);
    final isProfile = id == dockIdProfile;
    return NavigationDestination(
      icon: isProfile
          ? _buildUpdateBadge(showBadge: hasUpdate, child: Icon(config.icon))
          : Icon(config.icon),
      selectedIcon: isProfile
          ? _buildUpdateBadge(
              showBadge: hasUpdate,
              child: Icon(config.selectedIcon),
            )
          : Icon(config.selectedIcon),
      label: config.dockLabel(l10n),
      tooltip: '',
    );
  }
}
