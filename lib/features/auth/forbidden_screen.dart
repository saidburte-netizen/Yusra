import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/nav/menu_items.dart';
import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';

class ForbiddenScreen extends ConsumerWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline,
                      size: 56, color: AppColors.warning),
                  const SizedBox(height: 16),
                  Text(S.forbidden,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Text(
                    S.forbiddenBody,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${S.signedInAs}: ${auth.profile?.email ?? '—'}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${S.role}: ${auth.profile?.roleLabel ?? auth.profile?.role.label ?? '—'}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: S.backToHome,
                    icon: Icons.home_outlined,
                    onPressed: () => context.go(homeFor(auth.profile?.role)),
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: S.signOut,
                    icon: Icons.logout,
                    onPressed: () => ref.read(authProvider.notifier).signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
