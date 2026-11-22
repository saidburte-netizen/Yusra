import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../errors/app_error.dart';
import '../permissions.dart';
import '../strings.dart';
import '../supabase_client.dart';

enum AuthStatus {
  initial,
  loading,
  profileLoading,
  authenticated,
  unauthenticated,
  profileError,
}

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

  factory UserProfile.fromJson(Map<String, dynamic> json,
      {required String email}) {
    final roleText = json['role'] as String?;
    final role = AppRoleX.fromDb(roleText);
    final active = json['is_active'];
    if (role == null || active is! bool || (json['id'] as String?) == null) {
      throw const FormatException('Invalid profile response');
    }
    return UserProfile(
      id: json['id'] as String,
      email: email,
      fullName: (json['full_name'] as String?) ?? email.split('@').first,
      role: role,
      roleLabel: roleText,
      isActive: active,
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
    this.sessionExpired = false,
  });

  final AuthStatus status;
  final UserProfile? profile;
  final String? error;

  /// Set when the server rejected an expired token. The router uses it to
  /// route to /login and the login screen can show a re-sign-in hint.
  final bool sessionExpired;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isInitialising =>
      status == AuthStatus.initial ||
      status == AuthStatus.loading ||
      status == AuthStatus.profileLoading;
  bool get isActive => profile?.isActive ?? false;

  static const initial = AuthState(status: AuthStatus.initial);
  static const loading = AuthState(status: AuthStatus.loading);
  static const unauthenticated = AuthState(status: AuthStatus.unauthenticated);
  static const expired =
      AuthState(status: AuthStatus.unauthenticated, sessionExpired: true);
}

/// Bumped whenever auth state changes so go_router re-runs its redirect.
final ValueNotifier<int> authRevision = ValueNotifier<int>(0);

final authProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
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
  Future<void>? _profileFuture;

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

  /// Serialize profile reads so overlapping auth events cannot drop a refresh.
  Future<void> _loadProfile() {
    final pending = _profileFuture;
    if (pending != null) return pending;
    final future = _loadProfileUnchecked().whenComplete(() {
      _profileFuture = null;
    });
    _profileFuture = future;
    return future;
  }

  Future<void> _loadProfileUnchecked() async {
    final client = SupabaseService.client;
    final user = client.auth.currentUser;
    if (user == null) {
      state = AuthState.unauthenticated;
      _bump();
      return;
    }
    // Keep a previously loaded profile visible while a background refresh is
    // in flight. Clearing it makes the router wait at a blank shell on every
    // token refresh, which looks like a crash to the user.
    if (state.profile == null || state.status != AuthStatus.authenticated) {
      state = const AuthState(status: AuthStatus.profileLoading);
    }
    _bump();
    try {
      // The SECURITY DEFINER RPC is the only profile read. A missing row or a
      // broken migration is a profile error, never a fabricated cashier.
      final rpcResult = await client.rpc('get_my_profile');
      if (rpcResult == null) throw StateError('Empty profile response');
      final row = Map<String, dynamic>.from(rpcResult as Map);
      state = AuthState(
        status: AuthStatus.authenticated,
        profile: UserProfile.fromJson(row, email: user.email ?? ''),
      );
    } catch (e) {
      final mapped = AppErrorMapper.from(e);
      if (mapped.isSessionExpired) {
        // An expired token is not a profile bug: route to sign-in so the user
        // can refresh the session instead of staring at a profile error.
        state = AuthState.expired;
      } else {
        state = AuthState(
          status: AuthStatus.profileError,
          error: mapped.message,
        );
      }
    }
    _bump();
  }

  /// Called by repository boundaries that receive a 401 / PGRST301 /
  /// "JWT expired" response. Idempotent: repeated calls keep one state.
  void markSessionExpired() {
    if (state.sessionExpired && state.status == AuthStatus.unauthenticated) {
      return;
    }
    state = AuthState.expired;
    _bump();
  }

  /// Reload the profile after admin/team mutations without recreating this
  /// provider (which would reset the router to the initial state).
  Future<void> refreshProfile() => _loadProfile();

  Future<String?> signIn(
      {required String email, required String password}) async {
    state = AuthState.loading;
    try {
      await SupabaseService.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile();
      if (state.status == AuthStatus.profileError) return state.error;
      return state.profile?.isActive == false ? S.inactiveAccount : null;
    } on AuthException catch (e) {
      final message = _friendlyAuthError(e.message);
      state = AuthState(status: AuthStatus.unauthenticated, error: message);
      _bump();
      return message;
    } catch (_) {
      const message = S.somethingWrong;
      state =
          const AuthState(status: AuthStatus.unauthenticated, error: message);
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
    if (lower.contains('email not confirmed')) return S.emailNotConfirmed;
    if (lower.contains('too many requests')) return S.tooManyAttempts;
    if (lower.contains('network') || lower.contains('failed to fetch')) {
      return S.noConnection;
    }
    return S.somethingWrong;
  }
}
