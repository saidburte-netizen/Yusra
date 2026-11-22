import 'dart:async';
import 'dart:math';

import '../strings.dart';

/// Raised when the same write is submitted twice before the first one settles.
/// The UI can ignore it silently (a second tap on Pay must never create a
/// second sale).
class DuplicateSubmitException implements Exception {
  const DuplicateSubmitException();

  @override
  String toString() => S.duplicateSubmit;
}

/// Session-scoped double-submit protection and idempotency key registry.
///
/// A key is generated once per logical operation (when the form is opened) and
/// passed to [run]. Concurrent calls with the same key share the first
/// result; a replay after completion returns the same result instead of
/// hitting the server again.
///
/// NOTE: the current SQL RPCs do not accept an idempotency token, so this
/// guarantees at-most-once *per app session / per key*. Server-side dedupe
/// across restarts requires a migration (see docs/STATE_MANAGEMENT.md).
abstract final class WriteIdempotency {
  static final Set<String> _inFlight = <String>{};
  static final Map<String, Object?> _completed = <String, Object?>{};
  static final Random _random = Random();
  static const int _maxCompleted = 128;

  static String newKey(String operation) =>
      '$operation:${DateTime.now().microsecondsSinceEpoch}:'
      '${_random.nextInt(1 << 32).toRadixString(16)}';

  static bool isPending(String key) => _inFlight.contains(key);

  static bool wasCompleted(String key) => _completed.containsKey(key);

  static Future<T> run<T>({
    required String key,
    required Future<T> Function() action,
  }) async {
    if (_inFlight.contains(key)) throw const DuplicateSubmitException();
    if (_completed.containsKey(key)) {
      final done = _completed[key];
      if (done is T) return done;
    }

    _inFlight.add(key);
    try {
      final result = await action();
      if (_completed.length >= _maxCompleted) {
        _completed.remove(_completed.keys.first);
      }
      _completed[key] = result;
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Forget every key. Called on sign-out so a new user cannot replay the
  /// previous user's completed writes.
  static void reset() {
    _inFlight.clear();
    _completed.clear();
  }
}
