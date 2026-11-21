import 'dart:async';
import 'dart:convert';

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
    this.code,
  });

  final String message;
  final AppErrorKind kind;
  final bool retryable;
  final Object? cause;

  /// A short, copyable machine code (for example `42501` or `PGRST200`).
  /// Never contains SQL text: the mapper whitelists code-shaped values only.
  final String? code;

  /// The line shown underneath the friendly message in error banners.
  String? get codeLine => code == null ? null : 'Error code: $code';

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
      final code = _cleanCode(error.code);
      return AppError(
        _withCode(_postgrestMessage(error), code),
        kind: _postgrestKind(error),
        retryable: _postgrestRetryable(error),
        cause: error,
        code: code,
      );
    }

    if (error is FunctionException) {
      return AppError(
        _functionMessage(error),
        kind: _functionKind(error.status),
        retryable: _functionRetryable(error.status),
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
      final code = error is SocketException ? 'NETWORK' : 'TIMEOUT';
      return AppError(
        _withCode(
          'No connection to the server. Check your internet and try again.',
          code,
        ),
        kind: AppErrorKind.network,
        retryable: true,
        cause: error,
        code: code,
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

  /// Only a short machine code is ever shown. A malformed/verbose `code`
  /// coming from a server must not become a back-door for raw SQL text.
  static String? _cleanCode(String? raw) {
    if (raw == null) return null;
    final code = raw.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{3,24}$').hasMatch(code)) return null;
    return code;
  }

  static String _withCode(String message, String? code) {
    final clean = _cleanCode(code);
    if (clean == null) return message;
    return '$message\nError code: $clean';
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
    if (code == 'PGRST116' || code == 'PGRST204' || code == 'P0002') {
      return AppErrorKind.notFound;
    }
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
      case 'PGRST200':
        return 'The server could not find the requested link between records.';
      case 'PGRST201':
        return 'The server found several matches and could not choose one.';
      case 'PGRST204':
        return 'No data was returned for this request.';
      case '42P01':
        return 'A required table is missing on the server.';
      case '42703':
        return 'A required column is missing on the server.';
      case 'PGRST116':
      case 'P0002':
        return 'The requested record was not found.';
      case '23505':
        return 'That value is already used by another record.';
      case '23503':
        return 'A linked record is missing or is no longer available.';
      case '23514':
        return 'One of the values is not allowed.';
      case 'P0001':
        final raw = error.message.toLowerCase();
        if (raw.contains('stock') || raw.contains('quantity')) {
          return 'There is not enough stock to complete this operation.';
        }
        return 'The server could not complete the operation. Check the entered values and try again.';
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

  /// Edge Functions return `{error: {code, message}}`. Surface that message so
  /// the owner can see the real reason (missing service-role key, duplicate
  /// email, wrong branch, ...) instead of a generic SDK error.
  static String _functionMessage(FunctionException error) {
    Object? details = error.details;
    if (details is String) {
      try {
        details = jsonDecode(details);
      } catch (_) {
        // Keep the raw text below; it may still be a useful plain message.
      }
    }

    String? code;
    String? message;
    if (details is Map) {
      final body = details['error'];
      if (body is Map) {
        code = body['code']?.toString();
        message = body['message']?.toString();
      }
      message ??= details['message']?.toString();
    } else if (details != null) {
      message = details.toString();
    }

    switch (code) {
      case 'unauthenticated':
        return 'Please sign in again.';
      case 'forbidden':
        return 'You do not have permission to do that.';
      case 'not_found':
        return 'The requested record was not found.';
      case 'validation_error':
        return message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'One of the values entered is not valid.';
      case 'conflict':
        return message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'That value is already used by another record.';
      case 'bad_request':
        return message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'The request could not be read.';
      case 'method_not_allowed':
        return 'This action is not available.';
      case 'internal_error':
        return message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'The server could not complete the request. Please try again.';
    }

    if (message != null && message.trim().isNotEmpty) {
      final clean = message.trim();
      // Never leak a stack trace or raw function name to the UI.
      if (!clean.contains('FunctionException') &&
          !clean.contains('Stack Trace') &&
          !clean.contains('supabase/')) {
        return clean;
      }
    }

    switch (error.status) {
      case 401:
        return 'Please sign in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'The requested record was not found.';
      case 409:
        return 'That value is already used by another record.';
      case 422:
        return 'One of the values entered is not valid.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'The server could not complete the request. Please try again.';
      default:
        return S.somethingWrong;
    }
  }

  static AppErrorKind _functionKind(int status) {
    if (status == 401) return AppErrorKind.authentication;
    if (status == 403) return AppErrorKind.permission;
    if (status == 404) return AppErrorKind.notFound;
    if (status == 409 || status == 422) return AppErrorKind.validation;
    if (status >= 500) return AppErrorKind.server;
    return AppErrorKind.unknown;
  }

  static bool _functionRetryable(int status) => status == 408 || status >= 500;
}
