import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../errors/app_error.dart';
import '../permissions.dart';
import '../strings.dart';
import '../supabase_client.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated }

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.phone,
    this.avatarUrl,
    this.branchId,
    this.roleLabel,
  });

  final String id;
  final String email;
  final String fullName;
  final AppRole role;
  final String? roleLabel;
  final bool isActive;
  final String? phone;
  final String? avatarUrl;
  final String? branchId;

  factory UserProfile.fromJson(Map<String, dynamic> json, {required String email}) {
    return UserProfile(
      id: (json['id'] as String?) ?? '',
      email: email,
      fullName: (json['full_name'] as String?) ?? email.split('@').first,
      role: AppRoleX.fromDb(json['role'] as String?) ?? AppRole.cashier,
      roleLabel: json['role'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      branchId: json['branch_id'] as String?,
    );
  }
}

class AuthState {
  const AuthState({
    required this.status,
    this.profile,
    this.error,
  });

  final AuthStatus status;
  final UserProfile? profile;
  final String? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isInitialising => status == AuthStatus.initial;
  bool get isActive => profile?.isActive ?? false;

  static const initial = AuthState(status: AuthStatus.initial);
  static const loading = AuthState(status: AuthStatus.loading);
  static const unauthenticated = AuthState(status: AuthStatus.unauthenticated);
}

/// Bumped whenever auth state changes so go_router re-runs its redirect.
final ValueNotifier<int> authRevision = ValueNotifier<int>(0);

final authProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final controller = AuthController();
  ref.onDispose(controller.dispose);
  return controller;
});

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(AuthState.initial) {
    if (!SupabaseService.isReady) return;
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    final goTrue = SupabaseService.client.auth;
    _subscription = goTrue.onAuthStateChange.listen((change) {
      if (change.event == AuthChangeEvent.passwordRecovery) {
        _bump();
      }
      if (change.session?.user == null) {
        state = AuthState.unauthenticated;
        _bump();
      } else {
        // Roles can change in the database while a session is live (for example
        // when an admin promotes a teammate). Re-read the profile on every auth
        // event so the router guard never keeps a stale role.
        unawaited(_loadProfile());
      }
    });
  }

  StreamSubscription<Object>? _subscription;
  bool _loadingProfile = false;

  void _bump() => authRevision.value++;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Called once from main before the router is built.
  Future<void> bootstrap() async {
    if (!SupabaseService.isReady) {
      state = AuthState.unauthenticated;
      _bump();
      return;
    }
    if (SupabaseService.client.auth.currentSession == null) {
      state = AuthState.unauthenticated;
      _bump();
      return;
    }
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_loadingProfile) return;
    _loadingProfile = true;
    try {
      await _loadProfileUnchecked();
    } finally {
      _loadingProfile = false;
    }
  }

  Future<void> _loadProfileUnchecked() async {
    final client = SupabaseService.client;
    final user = client.auth.currentUser;
    if (user == null) {
      state = AuthState.unauthenticated;
      _bump();
      return;
    }
    try {
      // Prefer a SECURITY DEFINER RPC so a missing RLS policy or table grant
      // cannot turn into a fake "cashier" profile and a false access denial.
      // The direct read stays as a fallback for databases where the RPC has
      // not been applied yet.
      late final Map<String, dynamic> row;
      try {
        final rpcResult = await client.rpc('get_my_profile');
        if (rpcResult == null) throw StateError('Empty profile response');
        row = Map<String, dynamic>.from(rpcResult as Map);
      } catch (_) {
        row = await client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .single();
      }
      state = AuthState(
        status: AuthStatus.authenticated,
        profile: UserProfile.fromJson(row, email: user.email ?? ''),
      );
    } catch (e) {
      // Keep the user signed in, but surface the real reason the profile could
      // not be read. Silently turning this into "inactive" made genuine RLS,
      // project-configuration and missing-row problems look like access denied.
      state = AuthState(
        status: AuthStatus.authenticated,
        profile: UserProfile(
          id: user.id,
          email: user.email ?? '',
          fullName: user.email ?? '',
          role: AppRole.cashier,
          roleLabel: S.roleUnknown,
          isActive: false,
        ),
        error: AppErrorMapper.from(e).message,
      );
    }
    _bump();
  }

  Future<void> refreshProfile() => _loadProfile();

  Future<String?> signIn({required String email, required String password}) async {
    state = AuthState.loading;
    try {
      await SupabaseService.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile();
      return state.profile?.isActive == false ? S.inactiveAccount : null;
    } on AuthException catch (e) {
      final message = _friendlyAuthError(e.message);
      state = AuthState(status: AuthStatus.unauthenticated, error: message);
      _bump();
      return message;
    } catch (_) {
      const message = S.somethingWrong;
      state = const AuthState(status: AuthStatus.unauthenticated, error: message);
      _bump();
      return message;
    }
  }

  Future<String?> requestPasswordReset(String email) async {
    try {
      await SupabaseService.client.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return _friendlyAuthError(e.message);
    } catch (_) {
      return S.somethingWrong;
    }
  }

  Future<String?> updatePassword(String newPassword) async {
    try {
      await SupabaseService.client.auth
          .updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return _friendlyAuthError(e.message);
    } catch (_) {
      return S.somethingWrong;
    }
  }

  Future<void> signOut() async {
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {
      // Signing out locally still clears the UI.
    }
    state = AuthState.unauthenticated;
    _bump();
  }

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password')) {
      return S.invalidCredentials;
    }
    if (lower.contains('email not confirmed')) return 'Email not confirmed yet.';
    if (lower.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('network') || lower.contains('failed to fetch')) {
      return 'No connection. Check your internet and try again.';
    }
    return S.somethingWrong;
  }
}
