import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_error.dart';
import '../strings.dart';
import '../theme/app_colors.dart';
import 'invalidation.dart';

/// Connectivity is abstracted so tests can emit offline/online events without
/// a platform channel. The real implementation uses connectivity_plus.
abstract class ConnectivitySource {
  Stream<bool> get onLine;

  /// Re-read the current state (used by the banner's Try again button).
  Future<void> recheck() async {}
}

class PluginConnectivitySource implements ConnectivitySource {
  PluginConnectivitySource({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _connectivity.onConnectivityChanged.listen((results) {
      _last = _anyOnline(results);
      _controller.add(_last);
    });
  }

  final Connectivity _connectivity;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _last = true;

  static bool _anyOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> get onLine async* {
    yield _last;
    yield* _controller.stream;
  }

  @override
  Future<void> recheck() async {
    final results = await _connectivity.checkConnectivity();
    _last = _anyOnline(results);
    _controller.add(_last);
  }
}

final connectivitySourceProvider = Provider<ConnectivitySource>((ref) {
  return PluginConnectivitySource();
});

final isOnlineProvider = StreamProvider<bool>((ref) {
  final source = ref.watch(connectivitySourceProvider);
  return source.onLine.distinct();
});

/// Unknown (no event yet) is treated as online: a cold start must never show
/// a false "offline" banner or disable the UI.
bool offlineFrom(AsyncValue<bool> state) =>
    state.maybeWhen(data: (online) => !online, orElse: () => false);

final isOfflineProvider = Provider<bool>((ref) {
  return offlineFrom(ref.watch(isOnlineProvider));
});

/// A tiny global write guard. `OfflineScope` keeps it in sync with the
/// connectivity stream; repositories call [ensureOnline] immediately before a
/// network write. It stays pure Dart so it can be tested without Flutter.
abstract final class OfflineWriteGuard {
  static bool _online = true;

  static bool get isOnline => _online;

  static void setOnline(bool value) => _online = value;

  static void ensureOnline() {
    if (!_online) throw const OfflineException();
  }

  /// Test-only reset; also used before bootstrap sets the real value.
  static void resetForTest() => _online = true;
}

/// Keeps the global guard in sync and refreshes ledger providers when the
/// device comes back online, so no manual reload is needed after a dropout.
class OfflineScope extends ConsumerStatefulWidget {
  const OfflineScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfflineScope> createState() => _OfflineScopeState();
}

class _OfflineScopeState extends ConsumerState<OfflineScope> {
  bool _wasOffline = false;

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    OfflineWriteGuard.setOnline(!offline);

    ref.listen<bool>(isOfflineProvider, (prev, next) {
      OfflineWriteGuard.setOnline(!next);
      final wasOffline = prev ?? _wasOffline;
      if (wasOffline && !next) {
        refreshAfterReconnect(ref.invalidate);
      }
      _wasOffline = next;
    });
    _wasOffline = offline;

    return widget.child;
  }
}

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isOfflineProvider)) return const SizedBox.shrink();
    return Material(
      color: AppColors.danger,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: AppColors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text(S.offlineBanner,
                      style: TextStyle(color: AppColors.white, fontSize: 13))),
              TextButton(
                onPressed: () async {
                  await ref.read(connectivitySourceProvider).recheck();
                  ref.invalidate(isOnlineProvider);
                },
                child: const Text(S.retry,
                    style: TextStyle(color: AppColors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a write callback so callers get a disabled button offline instead of
/// a snackbar after a failed request. Use it for every mutating action.
bool writeEnabled(WidgetRef ref) => !ref.watch(isOfflineProvider);
