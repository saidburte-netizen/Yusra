import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Logical cache groups. Keys are always namespaced with one of these, plus
/// the current user/branch, so invalidating a group never leaves stale data
/// behind and never leaks one user's data to another.
abstract final class CacheTag {
  static const String settings = 'settings';
  static const String catalogue = 'catalogue';
  static const String stock = 'stock';
  static const String sales = 'sales';
  static const String shifts = 'shifts';
  static const String users = 'users';
  static const String customers = 'customers';
  static const String purchases = 'purchases';
  static const String prescriptions = 'prescriptions';
  static const String expenses = 'expenses';
  static const String reports = 'reports';
}

/// Where the catalogue snapshot is stored. Implemented by the persistence
/// layer in `cache_policy.dart`; kept here so [AppCache] stays dependency-free
/// and unit-testable without a platform channel.
abstract class CacheSnapshotStore {
  Future<void> save(Map<String, String> entries);
  Future<void> clear();
}

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final Object? value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Small in-memory, TTL-based query cache.
///
/// It is deliberately dependency-free and synchronous to read: Riverpod
/// already caches provider results for the lifetime of the app, but reference
/// data (settings, categories) must be refreshable and must not survive a
/// sign-out with the previous user's values. Use [scopedKey] for every key.
///
/// [readSWR] adds stale-while-revalidate for the catalogue: a stale value is
/// returned immediately and refreshed in the background, so a cold start with
/// a persisted snapshot never shows a loading skeleton. [readVersioned] adds a
/// cheap version check for branding/settings: when the server version changes,
/// the cached entry is dropped before the value is read.
class AppCache {
  AppCache({this.snapshotStore});

  /// Optional persisted store. [clear] always clears memory first and then
  /// asks the store to clear, so logout never leaves a snapshot on disk.
  final CacheSnapshotStore? snapshotStore;

  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  /// Builds a key that cannot collide across users or branches.
  static String scopedKey(String tag, String scope, String suffix) =>
      '$tag:$scope:$suffix';

  /// Returns the cached value, or loads and caches it.
  ///
  /// Concurrent callers share the same in-flight future so a screen rebuild
  /// cannot trigger duplicate requests.
  Future<T> read<T>(
    String key,
    Duration ttl,
    Future<T> Function() loader, {
    Future<void> Function(T value)? onLoaded,
  }) async {
    final entry = _entries[key];
    if (entry != null && !entry.isExpired && entry.value is T) {
      return entry.value as T;
    }
    final pending = _pending[key];
    if (pending != null) return (await pending) as T;

    final future = loader();
    _pending[key] = future;
    try {
      final value = await future;
      _entries[key] = _CacheEntry(value, DateTime.now().add(ttl));
      if (onLoaded != null) await onLoaded(value);
      return value;
    } finally {
      _pending.remove(key);
    }
  }

  /// Stale-while-revalidate read used by catalogue providers.
  ///
  /// * fresh entry  -> returned synchronously (no network);
  /// * stale entry within [staleFor] -> returned immediately while a refresh
  ///   runs in the background; the next read sees the fresh value;
  /// * stale entry older than [staleFor] (or no entry) -> awaited load, with
  ///   concurrent callers sharing one in-flight request.
  Future<T> readSWR<T>(
    String key,
    Duration ttl,
    Future<T> Function() loader, {
    Duration staleFor = Duration.zero,
    Future<void> Function(T value)? onLoaded,
  }) async {
    final entry = _entries[key];
    if (entry != null && !entry.isExpired && entry.value is T) {
      return entry.value as T;
    }
    if (entry != null &&
        entry.value is T &&
        staleFor > Duration.zero &&
        DateTime.now().isBefore(entry.expiresAt.add(staleFor))) {
      // Return stale data now; refresh without making the caller wait.
      unawaited(read<T>(key, ttl, loader, onLoaded: onLoaded));
      return entry.value as T;
    }
    return read<T>(key, ttl, loader, onLoaded: onLoaded);
  }

  /// Reads a value only while the server-side version is unchanged.
  ///
  /// Used for branding/settings: a cheap version read (e.g. `max(updated_at)`)
  /// invalidates the whole `settings` tag when it changes, so a price/list
  /// edit is picked up without a manual provider reload.
  Future<T> readVersioned<T>(
    String key,
    Duration ttl,
    Future<String> Function() versionLoader,
    Future<T> Function() loader,
  ) async {
    String? version;
    try {
      version = await versionLoader();
    } catch (_) {
      // A failed version check must not hide the last known good value.
    }
    final versionKey = '$key#version';
    final cachedVersion = _entries[versionKey]?.value;
    if (version != null &&
        cachedVersion is String &&
        cachedVersion != version) {
      invalidate(key.split(':').first);
    }
    if (version != null) {
      _entries[versionKey] = _CacheEntry(version, DateTime.now().add(ttl));
    }
    return read<T>(key, ttl, loader);
  }

  final Map<String, Future<dynamic>> _pending = <String, Future<dynamic>>{};

  /// Seeds one entry, e.g. from a persisted catalogue snapshot. Seeded entries
  /// are treated as stale immediately so [readSWR] revalidates in background.
  void restore<T>(String key, T value,
      {Duration age = const Duration(days: 1)}) {
    _entries[key] = _CacheEntry(value, DateTime.now().subtract(age));
  }

  T? peek<T>(String key) {
    final entry = _entries[key];
    if (entry == null || entry.isExpired) return null;
    return entry.value is T ? entry.value as T : null;
  }

  Iterable<String> get keys => List<String>.unmodifiable(_entries.keys);

  /// Removes everything in a cache group.
  void invalidate(String tag) {
    _entries.removeWhere((key, _) => key.startsWith('$tag:'));
    _pending.removeWhere((key, _) => key.startsWith('$tag:'));
  }

  void invalidateAll(Iterable<String> tags) {
    for (final tag in tags) {
      invalidate(tag);
    }
  }

  /// Clears all cached data, e.g. on sign-out. The persisted snapshot is
  /// cleared too; no user-scoped bytes survive the session boundary.
  void clear() {
    _entries.clear();
    _pending.clear();
    final store = snapshotStore;
    if (store != null) unawaited(store.clear());
  }

  int get length => _entries.length;

  bool contains(String key) => _entries.containsKey(key);
}

final appCacheProvider = Provider<AppCache>((ref) => AppCache());

/// Lets any screen or provider invalidate cache groups without depending on
/// the concrete cache implementation.
extension CacheInvalidation on Ref {
  void invalidateCache(String tag) => read(appCacheProvider).invalidate(tag);

  void invalidateCaches(Iterable<String> tags) =>
      read(appCacheProvider).invalidateAll(tags);
}

extension WidgetCacheInvalidation on WidgetRef {
  void invalidateCache(String tag) => read(appCacheProvider).invalidate(tag);

  void invalidateCaches(Iterable<String> tags) =>
      read(appCacheProvider).invalidateAll(tags);
}
