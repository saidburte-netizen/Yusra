import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/state/app_cache.dart';

void main() {
  group('AppCache', () {
    test('loads once and reuses the value while fresh', () async {
      final cache = AppCache();
      var calls = 0;
      Future<int> loader() async {
        calls++;
        return 42;
      }

      final key = AppCache.scopedKey(CacheTag.settings, 'user-1', 'receipt');
      expect(await cache.read(key, const Duration(minutes: 5), loader), 42);
      expect(await cache.read(key, const Duration(minutes: 5), loader), 42);
      expect(calls, 1);
      expect(cache.peek<int>(key), 42);
    });

    test('expires entries after the TTL', () async {
      final cache = AppCache();
      var calls = 0;
      final key = AppCache.scopedKey(CacheTag.settings, 'user-1', 'expiry');
      Future<int> loader() async => ++calls;

      await cache.read(key, Duration.zero, loader);
      await Future<void>.delayed(Duration.zero);
      await cache.read(key, Duration.zero, loader);
      expect(calls, 2);
    });

    test('invalidation is scoped to a tag, never to other data', () async {
      final cache = AppCache();
      final settingsKey =
          AppCache.scopedKey(CacheTag.settings, 'user-1', 'receipt');
      final stockKey = AppCache.scopedKey(CacheTag.stock, 'branch-1', 'summary');

      await cache.read(settingsKey, const Duration(minutes: 5), () async => 1);
      await cache.read(stockKey, const Duration(minutes: 5), () async => 2);

      cache.invalidate(CacheTag.settings);
      expect(cache.contains(settingsKey), isFalse);
      expect(cache.contains(stockKey), isTrue);
    });

    test('concurrent readers share a single in-flight request', () async {
      final cache = AppCache();
      var calls = 0;
      final key = AppCache.scopedKey(CacheTag.catalogue, 'user-1', 'medicines');

      final results = await Future.wait([
        cache.read(key, const Duration(minutes: 5), () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 'medicines';
        }),
        cache.read(key, const Duration(minutes: 5), () async {
          calls++;
          return 'medicines';
        }),
      ]);

      expect(results, ['medicines', 'medicines']);
      expect(calls, 1);
    });

    test('clear removes everything', () async {
      final cache = AppCache();
      await cache.read('settings:u:1', const Duration(minutes: 5), () async => 1);
      cache.clear();
      expect(cache.length, 0);
    });
  });
}
