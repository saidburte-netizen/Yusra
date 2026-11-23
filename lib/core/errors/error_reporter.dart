import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      final mapped = AppErrorMapper.from(details.exception);
      debugPrint('Uncaught Flutter error: ${mapped.sanitizedLogLine}');
      debugPrint('Error detail: ${details.exception}');
      debugPrint('Stack trace:\n${details.stack}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      final mapped = AppErrorMapper.from(error);
      debugPrint('Uncaught async error: ${mapped.sanitizedLogLine}');
      debugPrint('Error detail: $error');
      debugPrint('Stack trace:\n$stack');
      return true; // prevent the process from being torn down
    };

    ErrorWidget.builder = (details) => _FatalErrorView(details: details);
  }

  /// Convenience for repository boundaries that should not throw raw errors.
  static AppError guard(Object error) => AppErrorMapper.from(error);

  /// Maps then logs a stable, PII-free line (kind + short code only).
  /// Use this in catch blocks that intentionally swallow an error.
  static AppError logAndMap(Object error) {
    final mapped = AppErrorMapper.from(error);
    debugPrint('Handled error: ${mapped.sanitizedLogLine}');
    return mapped;
  }
}

class _FatalErrorView extends StatelessWidget {
  const _FatalErrorView({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final error = details.exception;
    final mapped = AppErrorMapper.from(error);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBase : AppColors.pink50;
    final stackLines = (details.stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(15)
        .join('\n');
    final fullReport =
        'Exception: $error\n\nStack (first 15 lines):\n$stackLines';
    return Material(
      color: bg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppColors.danger),
                        const SizedBox(height: 16),
                        Text(
                          S.somethingWrong,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mapped.message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error details',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkCard
                                : AppColors.pink50.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.gold300.withOpacity(0.5),
                            ),
                          ),
                          child: SelectableText(
                            fullReport,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: fullReport));
                                if (context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)
                                      ?.showSnackBar(const SnackBar(
                                          content: Text('Error copied')));
                                }
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy error'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                final nav = Navigator.maybeOf(context);
                                if (nav != null) nav.maybePop();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text(S.retry),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
