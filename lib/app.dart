import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/strings.dart';
import 'core/theme/app_theme.dart';

/// Root widget. Auth is bootstrapped in main() before this is mounted, so the
/// router's first redirect already knows whether the user is signed in.
class YusraApp extends ConsumerWidget {
  const YusraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: S.appName,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
