import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../../core/auth/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _message = null;
      _error = null;
    });
    final error =
        await ref.read(authProvider.notifier).requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (error == null) {
        _message = S.resetLinkSent;
      } else {
        // A failure must never reuse the green success styling.
        _error = error;
      }
    });
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
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: YusraLogo(
                            variant: YusraLogoVariant.full, size: 180),
                      ),
                      const SizedBox(height: 24),
                      Text(S.resetPassword,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your email and we will send a reset link.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_message != null) ...[
                        AppSnackbarLikeMessage(message: _message!),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null) ...[
                        AppSnackbarLikeMessage(message: _error!, isError: true),
                        const SizedBox(height: 12),
                      ],
                      AppTextField(
                        label: S.email,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        validator: (value) =>
                            value == null || !value.contains('@')
                                ? S.emailInvalid
                                : null,
                      ),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: S.sendResetLink,
                        loading: _sending,
                        onPressed: _send,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Back to sign in'),
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

class AppSnackbarLikeMessage extends StatelessWidget {
  const AppSnackbarLikeMessage({
    super.key,
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
