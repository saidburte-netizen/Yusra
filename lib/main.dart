import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_controller.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // With no --dart-define config the app still renders, but every data screen
  // shows a readable configuration message instead of crashing.
  await SupabaseService.initialize();

  final container = ProviderContainer();
  await container.read(authProvider.notifier).bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const YusraApp(),
    ),
  );
}
