import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_controller.dart';
import 'core/errors/error_reporter.dart';
import 'core/state/app_cache.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorReporter.install();

  // With no --dart-define config the app still renders, but every data screen
  // shows a readable configuration message instead of crashing.
  await SupabaseService.initialize();

  final container = ProviderContainer();
  await container.read(authProvider.notifier).bootstrap();
  // Never carry reference data from one signed-in user into the next.
  String? cachedUserId = container.read(authProvider).profile?.id;
  container.listen(authProvider, (_, next) {
    final userId = next.profile?.id;
    if (userId != cachedUserId) {
      cachedUserId = userId;
      container.read(appCacheProvider).clear();
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const YusraApp(),
    ),
  );
}
