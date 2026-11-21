import 'dart:async';

import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../strings.dart';
import '../supabase_client.dart';

/// Error categories used by the UI to decide wording and whether a retry
/// makes sense. Kept independent of any widget so it is unit-testable.
enum AppErrorKind {
  configuration,
  authentication,
  permission,
  network,
  validation,
  storage,
  server,
  notFound,
  unknown,
}

/// A single user-facing error type for the whole app.
///
/// Screens should never show `error.toString()` directly: raw Supabase and
/// socket errors leak implementation details and are not translated when
/// Amharic is added. Use [AppErrorMapper.from] at every boundary instead.
class AppError implements Exception {
  const AppError(
    this.message, {
    this.kind = AppErrorKind.unknown,
    this.retryable = false,
    this.cause,
  });

  final String message;
  final AppErrorKind kind;
  final bool retryable;
  final Object? cause;

  @override
  String toString() => message;
}

/// Maps low-level exceptions to stable, centralised messages.
class AppErrorMapper {
  const AppErrorMapper._();

  static AppError from(Object error) {
    if (error is AppError) return error;

    if (error is SupabaseNotConfigured) {
      return AppError(
        S.configurationMissing,
        kind: AppErrorKind.configuration,
        cause: error,
      );
    }

    if (error is AuthException) {
      return AppError(
        _authMessage(error.message),
        kind: AppErrorKind.authentication,
        cause: error,
      );
    }

    if (error is PostgrestException) {
      return AppError(
        _postgrestMessage(error),
        kind: _postgrestKind(error),
        retryable: _postgrestRetryable(error),
        cause: error,
      );
    }

    if (error is StorageException) {
      return AppError(
        'The file could not be saved. Please try again.',
        kind: AppErrorKind.storage,
        retryable: true,
        cause: error,
      );
    }

    if (error is SocketException || error is TimeoutException) {
      return AppError(
        'No connection to the server. Check your internet and try again.',
        kind: AppErrorKind.network,
        retryable: true,
        cause: error,
      );
    }

    if (error is FormatException) {
      return AppError(
        'One of the values entered is not valid.',
        kind: AppErrorKind.validation,
        cause: error,
      );
    }

    return AppError(S.somethingWrong, cause: error);
  }

  static String _authMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (lower.contains('user already registered')) {
      return 'A user with this email already exists.';
    }
    if (lower.contains('password should be')) {
      return 'The password is too short.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.isEmpty) return S.somethingWrong;
    if (lower.contains('network') || lower.contains('failed to fetch')) {
      return 'No connection. Check your internet and try again.';
    }
    return S.somethingWrong;
  }

  static AppErrorKind _postgrestKind(PostgrestException error) {
    final code = error.code ?? '';
    if (code == '42501' || code == 'PGRST301') return AppErrorKind.permission;
    if (code == 'PGRST116') return AppErrorKind.notFound;
    if (code.startsWith('22') || code.startsWith('23')) {
      return AppErrorKind.validation;
    }
    if (code.startsWith('5')) return AppErrorKind.server;
    return AppErrorKind.server;
  }

  static bool _postgrestRetryable(PostgrestException error) {
    final code = error.code ?? '';
    return code.startsWith('5') || code == 'PGRST203' || code == '408';
  }

  static String _postgrestMessage(PostgrestException error) {
    final code = error.code ?? '';
    switch (code) {
      case '42501':
      case 'PGRST301':
        return 'You do not have permission to do that.';
      case 'PGRST116':
        return 'The requested record was not found.';
      case '23505':
        return 'That value is already used by another record.';
      case '23503':
        return 'A linked record is missing or is no longer available.';
      case '23514':
        return 'One of the values is not allowed.';
      case '22003':
      case '22007':
        return 'One of the numbers or dates is not valid.';
      case 'PGRST202':
        return 'This feature is not available on the server yet.';
    }
    final message = error.message.toLowerCase();
    if (message.contains('shift')) {
      return 'Check the open cash shift and try again.';
    }
    if (message.contains('stock') || message.contains('quantity')) {
      return 'There is not enough stock to complete this operation.';
    }
    if (message.contains('expired')) {
      return 'Expired stock cannot be sold.';
    }
    if (message.contains('prescription')) {
      return 'A valid prescription is required for this sale.';
    }
    return 'The server could not complete the request. Please try again.';
  }
}
