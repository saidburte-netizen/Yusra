import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/errors/app_error.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(authProvider).profile;
    final email =
        profile?.email ?? SupabaseService.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      AppSnackbar.error(context, 'No signed-in email found.');
      return;
    }
    setState(() => _loading = true);
    try {
      // Verify current password by re-authenticating.
      await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: _current.text,
      );
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: _next.text),
      );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      AppSnackbar.success(context, 'Password updated successfully.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _current,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Current password'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _next,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 6)
                        return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirm new password'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v != _next.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Update password'),
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
