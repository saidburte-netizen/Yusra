import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/state/connectivity.dart';
import 'core/strings.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';

/// Root widget. Auth is bootstrapped in main() before this is mounted, so the
/// router's first redirect already knows whether the user is signed in.
class YusraApp extends ConsumerWidget {
  const YusraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: S.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      themeAnimationDuration: const Duration(milliseconds: 250),
      themeAnimationCurve: Curves.easeInOut,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AppTheme.pageBackground(
        context: context,
        child: Column(
          children: [
            // Auth screens sit outside AppShell; the shell shows its own banner
            // for the main app layout. Keep a single top banner globally.
            const OfflineBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
