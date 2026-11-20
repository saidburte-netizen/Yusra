import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../strings.dart';
import '../theme/app_colors.dart';
import '../widgets.dart';
import '../errors/app_error.dart';

/// One rendering policy for every AsyncValue in the app.
///
/// Using this instead of hand-written `.when()` blocks keeps loading and error
/// states identical across features and guarantees that errors are mapped
/// through [AppErrorMapper] and are retryable.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.state,
    required this.builder,
    this.onRetry,
    this.loadingLines = 4,
    this.emptyWhen,
    this.emptyMessage = S.noData,
    this.emptyIcon = Icons.inbox_outlined,
  });

  final AsyncValue<T> state;
  final Widget Function(BuildContext context, T value) builder;
  final VoidCallback? onRetry;
  final int loadingLines;
  final bool Function(T value)? emptyWhen;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (value) {
        if (emptyWhen != null && emptyWhen!(value)) {
          return EmptyState(message: emptyMessage, icon: emptyIcon);
        }
        return builder(context, value);
      },
      loading: () => LoadingSkeleton(lines: loadingLines),
      error: (error, _) {
        final mapped = AppErrorMapper.from(error);
        return ErrorState(message: mapped.message, onRetry: onRetry);
      },
    );
  }
}

/// Shows a non-blocking banner for a recoverable failure, with retry.
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({
    super.key,
    required this.error,
    this.onRetry,
  });

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final mapped = AppErrorMapper.from(error);
    return Card(
      color: AppColors.danger.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(mapped.message)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text(S.retry)),
          ],
        ),
      ),
    );
  }
}
