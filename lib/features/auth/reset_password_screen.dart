import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/nav/menu_items.dart';
import '../../core/strings.dart';
import '../../core/widgets.dart';
import '../../core/auth/auth_controller.dart';

/// Reached from the password-reset email. Supabase establishes a recovery
/// session before the app opens, so only the new password is required here.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error =
        await ref.read(authProvider.notifier).updatePassword(_password.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      AppSnackbar.success(context, S.saved);
      // Recovery must land on the role home, never a hard-coded dashboard that
      // a cashier/store keeper is not allowed to view.
      final profile = ref.read(authProvider).profile;
      context.go(homeFor(profile?.role));
    } else {
      AppSnackbar.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const YusraLogo(variant: YusraLogoVariant.mark, size: 90),
                      const SizedBox(height: 16),
                      Text(S.changePassword,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 20),
                      AppTextField(
                        label: S.newPassword,
                        controller: _password,
                        obscureText: true,
                        validator: (value) => value == null || value.length < 6
                            ? S.passwordShort
                            : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: S.confirmPassword,
                        controller: _confirm,
                        obscureText: true,
                        validator: (value) => value != _password.text
                            ? S.passwordsDontMatch
                            : null,
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: S.save,
                        onPressed: _save,
                        loading: _saving,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
