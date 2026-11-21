import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/errors/app_error.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _newPassword = TextEditingController();
  bool _saving = false;
  Uint8List? _avatarBytes;

  /// The profile object that last populated the controllers. A background
  /// profile refresh must not wipe out unsaved edits in the form.
  UserProfile? _boundProfile;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  void _bindProfile(UserProfile? profile) {
    if (profile == null) return;
    if (_boundProfile?.id == profile.id) return;
    _boundProfile = profile;
    _name.text = profile.fullName;
    _phone.text = profile.phone ?? '';
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _avatarBytes = bytes);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<String?> _uploadAvatar(String userId) async {
    if (_avatarBytes == null) return null;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await SupabaseService.client.storage.from('avatars').uploadBinary(
        path, _avatarBytes!,
        fileOptions:
            const FileOptions(upsert: true, contentType: 'image/jpeg'));
    return SupabaseService.client.storage.from('avatars').getPublicUrl(path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(authProvider).profile;
    if (profile == null) {
      AppSnackbar.error(context, S.accountProblem);
      return;
    }
    setState(() => _saving = true);
    try {
      final avatarUrl = await _uploadAvatar(profile.id);
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      // Safe RPC: name, phone and avatar only. Role, branch and active status
      // can never be changed from this screen.
      await SupabaseService.client.rpc('update_my_profile', params: {
        'p_full_name': _name.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_avatar_url': avatarUrl,
      });
      if (_newPassword.text.isNotEmpty) {
        final error = await ref
            .read(authProvider.notifier)
            .updatePassword(_newPassword.text);
        if (error != null && mounted) {
          AppSnackbar.error(context, error);
          return;
        }
      }
      await ref.read(authProvider.notifier).refreshProfile();
      if (mounted) {
        _boundProfile = ref.read(authProvider).profile;
        AppSnackbar.success(context, S.saved);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _retry() async {
    await ref.read(authProvider.notifier).refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final profile = auth.profile;
    _bindProfile(profile);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: _body(context, auth, profile),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AuthState auth, UserProfile? profile) {
    if (auth.isInitialising && profile == null) {
      return const LoadingSkeleton(lines: 4);
    }
    if (auth.status == AuthStatus.profileError) {
      return ErrorState(
        message: auth.error ?? S.accountProblem,
        onRetry: _retry,
      );
    }
    if (profile == null) {
      return EmptyState(
        message: S.accountProblem,
        icon: Icons.person_off_outlined,
        actionLabel: S.retry,
        onAction: _retry,
      );
    }
    return Form(
      key: _formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: AppColors.pink50,
                    foregroundColor: AppColors.pink600,
                    backgroundImage: profile.avatarUrl != null
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl == null
                        ? const Icon(Icons.person, size: 36)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.fullName,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(profile.email,
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          '${S.role}: ${profile.roleLabel ?? profile.role.label}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        TextButton.icon(
                          onPressed: _pickAvatar,
                          icon: const Icon(Icons.upload, size: 18),
                          label: const Text('Upload photo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppTextField(
                label: S.fullName,
                controller: _name,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? S.required : null,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: S.phone,
                controller: _phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: '${S.newPassword} (${S.optional})',
                controller: _newPassword,
                obscureText: true,
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) return null;
                  return text.length < 6 ? S.passwordShort : null;
                },
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: S.save,
                onPressed: _save,
                loading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
