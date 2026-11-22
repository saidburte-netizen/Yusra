import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/auth/auth_controller.dart';
import 'core/errors/error_reporter.dart';
import 'core/permissions.dart';
import 'core/state/app_cache.dart';
import 'core/state/cache_policy.dart';
import 'core/state/connectivity.dart';
import 'core/state/invalidation.dart';
import 'core/nav/app_shell.dart';
import 'core/supabase_client.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/inventory/data/inventory_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorReporter.install();

  // With no --dart-define config the app still renders, but every data screen
  // shows a readable configuration message instead of crashing.
  await SupabaseService.initialize();

  // Seed the persisted catalogue snapshot before the first frame so cold
  // starts render the last known catalogue while revalidating in background.
  SharedPrefsCacheSnapshotStore? snapshotStore;
  try {
    final prefs = await SharedPreferences.getInstance();
    snapshotStore = SharedPrefsCacheSnapshotStore(prefs);
  } catch (_) {
    // A storage failure must not block startup; the in-memory cache still works.
  }

  final container = ProviderContainer(overrides: [
    if (snapshotStore != null)
      cacheSnapshotStoreProvider.overrideWithValue(snapshotStore),
  ]);
  await restoreCatalogueSnapshot(
      container.read(appCacheProvider), snapshotStore);
  await container.read(themeModeProvider.notifier).load();
  await container.read(authProvider.notifier).bootstrap();

  // Never carry reference data from one signed-in user into the next.
  String? cacheKey = _identityKey(container.read(authProvider));
  container.listen(authProvider, (_, next) {
    final key = _identityKey(next);
    if (key != cacheKey) {
      cacheKey = key;
      SessionReset.onIdentityChanged(container);
    }
  });

  // Branch switch resets branch-scoped providers and drops branch ledgers.
  String? branchId = container.read(selectedBranchProvider);
  container.listen(selectedBranchProvider, (_, next) {
    if (next != branchId) {
      branchId = next;
      SessionReset.onBranchChanged(container);
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OfflineScope(child: AuthRefreshOnResume(child: YusraApp())),
    ),
  );
}

/// Role changes made in Supabase while the app is in the background must be
/// picked up as soon as the user returns, without waiting for a token refresh.
class AuthRefreshOnResume extends ConsumerStatefulWidget {
  const AuthRefreshOnResume({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AuthRefreshOnResume> createState() =>
      _AuthRefreshOnResumeState();
}

class _AuthRefreshOnResumeState extends ConsumerState<AuthRefreshOnResume>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _identityKey(AuthState state) {
  final profile = state.profile;
  if (profile == null) return state.status.name;
  return [
    profile.id,
    profile.role.dbName,
    profile.branchId ?? '',
    profile.isActive.toString(),
  ].join('|');
}
