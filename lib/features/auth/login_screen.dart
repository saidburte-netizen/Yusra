import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/env.dart';
import '../../core/nav/menu_items.dart';
import '../../core/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../../core/auth/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await ref.read(authProvider.notifier).signIn(
          email: _email.text,
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (error == null) {
      final profile = ref.read(authProvider).profile;
      context.go(homeFor(profile?.role));
    } else if (error == S.inactiveAccount) {
      context.go('/forbidden');
    } else if (ref.read(authProvider).status == AuthStatus.profileError) {
      context.go('/profile_error');
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2D0A1E), Color(0xFF4A1230), Color(0xFF7A1E4D)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 36,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: AppColors.gold500.withOpacity(0.45),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width < 400 ? 20 : 36,
                      vertical: 32,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.darkSurface
                                  : AppColors.blush,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? AppColors.darkGold
                                        : AppColors.gold300)
                                    .withOpacity(0.55),
                              ),
                            ),
                            child: const YusraLogo(
                              variant: YusraLogoVariant.full,
                              size: 210,
                              showTagline: true,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (!Env.isConfigured) ...[
                            const _Notice(
                              text: S.configurationMissing,
                              color: AppColors.warning,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_error != null) ...[
                            _Notice(text: _error!, color: AppColors.danger),
                            const SizedBox(height: 16),
                          ],
                          AppTextField(
                            label: S.email,
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon:
                                const Icon(Icons.email_outlined, size: 20),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return S.emailRequired;
                              }
                              if (!value.contains('@')) return S.emailInvalid;
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: S.password,
                            controller: _password,
                            obscureText: _obscure,
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? S.passwordRequired
                                : null,
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.go('/forgot-password'),
                              child: const Text(S.forgotPassword),
                            ),
                          ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: S.signIn,
                            loading: _submitting,
                            onPressed: _signIn,
                            icon: Icons.login,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Yusra Pharmacy · ${S.tagline}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 12))),
        ],
      ),
    );
  }
}
