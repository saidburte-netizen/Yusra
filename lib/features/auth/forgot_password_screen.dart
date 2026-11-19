import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/strings.dart';
import '../../core/widgets.dart';
import '../../core/auth/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  String? _message;

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
    });
    final error = await ref.read(authProvider.notifier).requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _message = error ?? S.resetLinkSent;
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
                      const YusraLogo(variant: YusraLogoVariant.full, size: 180),
                      const SizedBox(height: 24),
                      Text(S.resetPassword, style: Theme.of(context).textTheme.titleLarge),
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
                      AppTextField(
                        label: S.email,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        validator: (value) => value == null || !value.contains('@')
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
  const AppSnackbarLikeMessage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2E9E6B).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}
