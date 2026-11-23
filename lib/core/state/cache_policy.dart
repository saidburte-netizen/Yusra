import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_client.dart';
import 'app_cache.dart';

/// Central cache policy. Keeping the numbers in one place makes the
/// "catalogue is stale-while-revalidate, ledgers are always fresh" rule
/// auditable and testable.
abstract final class CachePolicy {
  /// Catalogue (medicines/categories) changes rarely. A six-hour fresh window
  /// is enough for a pharmacy; a seven-day stale window lets the app open
  /// instantly from the persisted snapshot before a refresh completes.
  static const catalogueTtl = Duration(hours: 6);
  static const catalogueStale = Duration(days: 7);

  /// Branding/receipt/settings are cached, but checked against a server
  /// version so an admin edit is visible without a manual provider reload.
  static const settingsTtl = Duration(minutes: 10);
  static const settingsVersionTtl = Duration(minutes: 1);

  /// Stock, sales, shifts and reports are ledgers: never serve them from a
  /// persisted snapshot. They are always fetched and refreshed with
  /// pull-to-refresh / an explicit Try again button.
  static const Set<String> alwaysFreshTags = <String>{
    CacheTag.stock,
    CacheTag.sales,
    CacheTag.shifts,
    CacheTag.reports,
  };

  static const snapshotKey = 'yusra.cache.catalogue_snapshot';
  static const brandingVersionKey = 'yusra.cache.branding_version';
}

/// Persists the catalogue snapshot (encoded strings only — the codec lives in
/// the inventory layer, so core never imports feature models). A sign-out
/// calls [AppCache.clear], which delegates here via the provider override in
/// `main.dart`, so the previous user's catalogue never reaches the next one.
class SharedPrefsCacheSnapshotStore implements CacheSnapshotStore {
  SharedPrefsCacheSnapshotStore(this._prefs);

  final SharedPreferences _prefs;

  Map<String, String> read() {
    final raw = _prefs.getString(CachePolicy.snapshotKey);
    if (raw == null) return <String, String>{};
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded
          .map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  @override
  Future<void> save(Map<String, String> entries) =>
      _prefs.setString(CachePolicy.snapshotKey, jsonEncode(entries));

  @override
  Future<void> clear() => _prefs.remove(CachePolicy.snapshotKey);
}

/// Null by default so pure unit tests need no platform channel. `main()` and
/// the integration test override it with a [SharedPrefsCacheSnapshotStore].
final cacheSnapshotStoreProvider =
    Provider<SharedPrefsCacheSnapshotStore?>((ref) => null);

/// Cheap version token for branding/settings. A single `max(updated_at)` read
/// is cached for one minute; a change invalidates the settings cache group on
/// the next read instead of requiring the user to reload the screen.
final settingsVersionProvider = FutureProvider<String>((ref) async {
  try {
    if (!SupabaseService.isReady) return '';
    final key = AppCache.scopedKey(CacheTag.settings, 'global', 'version');
    return await ref.read(appCacheProvider).read<String>(
      key,
      CachePolicy.settingsVersionTtl,
      () async {
        try {
          final rows = await SupabaseService.client
              .from('app_settings')
              .select('updated_at')
              .order('updated_at', ascending: false)
              .limit(1) as List;
          if (rows.isEmpty) return '';
          return (rows.first as Map)['updated_at']?.toString() ?? '';
        } catch (_) {
          // Offline or missing table: keep serving the last good version.
          return '';
        }
      },
    );
  } catch (_) {
    return '';
  }
});
