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
class AppCache {
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
    Future<T> Function() loader,
  ) async {
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
      return value;
    } finally {
      _pending.remove(key);
    }
  }

  final Map<String, Future<dynamic>> _pending = <String, Future<dynamic>>{};

  T? peek<T>(String key) {
    final entry = _entries[key];
    if (entry == null || entry.isExpired) return null;
    return entry.value is T ? entry.value as T : null;
  }

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

  /// Clears all cached data, e.g. on sign-out.
  void clear() {
    _entries.clear();
    _pending.clear();
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
