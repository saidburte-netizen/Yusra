import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme/app_colors.dart';
import 'app_error.dart';

/// Installs a single global error boundary.
///
/// Errors are still surfaced locally through [AppSnackbar] / [AsyncStateView],
/// but any error that escapes a widget build is shown as a branded fallback
/// instead of Flutter's red error screen and is logged once in debug mode.
class AppErrorReporter {
  AppErrorReporter._();

  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Uncaught Flutter error: ${details.exception}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught async error: $error');
      return true; // prevent the process from being torn down
    };

    ErrorWidget.builder =
        (details) => _FatalErrorView(error: details.exception);
  }

  /// Convenience for repository boundaries that should not throw raw errors.
  static AppError guard(Object error) => AppErrorMapper.from(error);
}

class _FatalErrorView extends StatelessWidget {
  const _FatalErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final mapped = AppErrorMapper.from(error);
    return Scaffold(
      backgroundColor: AppColors.pink50,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  Text(S.somethingWrong,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(mapped.message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.refresh),
                    label: const Text(S.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
