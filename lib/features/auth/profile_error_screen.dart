import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/nav/menu_items.dart';
import '../../core/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import 'package:go_router/go_router.dart';

/// Shown when the user is signed in but their profile could not be read.
/// Never fabricates a role or turns this into "Access denied".
class ProfileErrorScreen extends ConsumerStatefulWidget {
  const ProfileErrorScreen({super.key});

  @override
  ConsumerState<ProfileErrorScreen> createState() => _ProfileErrorScreenState();
}

class _ProfileErrorScreenState extends ConsumerState<ProfileErrorScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await ref.read(authProvider.notifier).refreshProfile();
    if (!mounted) return;
    setState(() => _retrying = false);
    final status = ref.read(authProvider).status;
    if (status == AuthStatus.authenticated) {
      final profile = ref.read(authProvider).profile;
      context.go(homeFor(profile?.role));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authProvider).error ?? S.profileErrorBody;
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
                  const Icon(Icons.cloud_off_outlined,
                      size: 56, color: AppColors.warning),
                  const SizedBox(height: 16),
                  Text(S.profileErrorTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(S.profileErrorBody, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(error,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: S.retry,
                    loading: _retrying,
                    onPressed: _retrying ? null : _retry,
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: S.signOut,
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
