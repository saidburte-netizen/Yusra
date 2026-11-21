import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'strings.dart';

/// Thrown when a screen needs Supabase but no --dart-define config was supplied.
class SupabaseNotConfigured implements Exception {
  const SupabaseNotConfigured();

  @override
  String toString() => S.configurationMissing;
}

/// Thin wrapper so every screen shares one initialised client and so a missing
/// build config produces a readable message instead of a cryptic SDK error.
abstract final class SupabaseService {
  static bool _initialized = false;
  static SupabaseClient? _e2eClient;

  static Future<void> initialize() async {
    if (_initialized || !Env.isConfigured) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    _initialized = true;
  }

  /// Install a pre-configured client for the PostgREST-backed e2e suite.
  ///
  /// Test-only: application code never calls this. It lets the suite swap the
  /// signed-in identity by replacing the client between repository calls.
  static void setE2eClient(SupabaseClient client) => _e2eClient = client;

  static void clearE2eClient() => _e2eClient = null;

  static bool get isReady => _initialized || _e2eClient != null;

  static SupabaseClient get client {
    final e2eClient = _e2eClient;
    if (e2eClient != null) return e2eClient;
    if (!_initialized) throw const SupabaseNotConfigured();
    return Supabase.instance.client;
  }
}
