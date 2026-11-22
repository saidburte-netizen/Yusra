import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/theme_mode_controller.dart';

class ThemeModeToggle extends ConsumerWidget {
  const ThemeModeToggle({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.darkCard : AppColors.white;
    final border =
        dark ? AppColors.darkBorder : AppColors.gold300.withOpacity(0.6);

    Widget button(ThemeMode value, IconData icon, String label) {
      final selected = mode == value;
      final fg = selected
          ? (dark ? AppColors.darkBase : Colors.white)
          : (dark ? AppColors.darkMuted : AppColors.plum800);
      final selectedBg = dark ? AppColors.darkGold : AppColors.plum800;
      return Expanded(
        child: InkWell(
          key: ValueKey('theme-mode-$label'),
          onTap: () => ref.read(themeModeProvider.notifier).setMode(value),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: fg),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          button(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
          const SizedBox(width: 4),
          button(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
          const SizedBox(width: 4),
          button(ThemeMode.system, Icons.brightness_auto_outlined, 'System'),
        ],
      ),
    );
  }
}
