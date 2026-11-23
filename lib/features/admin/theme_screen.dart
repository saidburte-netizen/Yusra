import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_controller.dart';

class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: mode,
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
            title: const Text('Light'),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: mode,
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
            title: const Text('Dark'),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: mode,
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
            title: const Text('Auto (system)'),
          ),
        ],
      ),
    );
  }
}
