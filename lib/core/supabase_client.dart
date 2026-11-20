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

  static Future<void> initialize() async {
    if (_initialized || !Env.isConfigured) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    _initialized = true;
  }

  static bool get isReady => _initialized;

  static SupabaseClient get client {
    if (!_initialized) throw const SupabaseNotConfigured();
    return Supabase.instance.client;
  }
}
