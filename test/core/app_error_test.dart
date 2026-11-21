import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yusra_pharmacy/core/errors/app_error.dart';
import 'package:yusra_pharmacy/core/strings.dart';
import 'package:yusra_pharmacy/core/supabase_client.dart';

void main() {
  group('AppErrorMapper', () {
    test('maps missing configuration without exposing SDK details', () {
      final mapped = AppErrorMapper.from(const SupabaseNotConfigured());
      expect(mapped.kind, AppErrorKind.configuration);
      expect(mapped.message, S.configurationMissing);
      expect(mapped.retryable, isFalse);
    });

    test('maps permission denials and does not suggest retrying', () {
      final mapped = AppErrorMapper.from(
        const PostgrestException(
          message: 'permission denied for table sales',
          code: '42501',
        ),
      );
      expect(mapped.kind, AppErrorKind.permission);
      expect(mapped.message, contains('permission'));
      expect(mapped.retryable, isFalse);
    });

    test('maps stock shortfalls to an actionable message', () {
      final mapped = AppErrorMapper.from(
        const PostgrestException(
          message: 'insufficient stock quantity',
          code: 'P0001',
        ),
      );
      expect(mapped.message, contains('stock'));
    });

    test('network failures are retryable', () {
      final mapped = AppErrorMapper.from(
        const SocketException('connection refused'),
      );
      expect(mapped.kind, AppErrorKind.network);
      expect(mapped.retryable, isTrue);
    });

    test('auth messages are translated', () {
      final mapped = AppErrorMapper.from(
        const AuthException('Invalid login credentials'),
      );
      expect(mapped.kind, AppErrorKind.authentication);
      expect(mapped.message, S.invalidCredentials);
    });

    test('maps validation and unknown errors to friendly text', () {
      expect(
        AppErrorMapper.from(const FormatException('bad')).kind,
        AppErrorKind.validation,
      );
      expect(
        AppErrorMapper.from('something obscure').message,
        S.somethingWrong,
      );
    });

    test('an existing AppError passes through unchanged', () {
      const error = AppError('custom', kind: AppErrorKind.notFound);
      expect(AppErrorMapper.from(error), same(error));
    });

    test('unknown auth errors never expose the raw Supabase message', () {
      final mapped = AppErrorMapper.from(
        const AuthException('Database error saving new user (PGRST/42501)'),
      );
      expect(mapped.message, S.somethingWrong);
      expect(mapped.message, isNot(contains('PGRST')));
      expect(mapped.message, isNot(contains('Database error')));
    });

    test('edge function errors surface the server message', () {
      const exception = FunctionException(
        status: 500,
        details: {
          'error': {
            'code': 'internal_error',
            'message': 'User creation is not configured on the server.',
          }
        },
      );
      final mapped = AppErrorMapper.from(exception);
      expect(mapped.kind, AppErrorKind.server);
      expect(mapped.message, 'User creation is not configured on the server.');
      expect(mapped.retryable, isTrue);
    });

    test('edge function validation errors are friendly, not raw SDK text', () {
      const exception = FunctionException(
        status: 422,
        details: {
          'error': {
            'code': 'validation_error',
            'message': 'Enter a valid email address.'
          }
        },
      );
      final mapped = AppErrorMapper.from(exception);
      expect(mapped.kind, AppErrorKind.validation);
      expect(mapped.message, 'Enter a valid email address.');
      expect(mapped.message, isNot(contains('FunctionException')));
    });

    test('edge function errors without a body fall back to status text', () {
      const exception = FunctionException(status: 403);
      final mapped = AppErrorMapper.from(exception);
      expect(mapped.kind, AppErrorKind.permission);
      expect(mapped.message, 'You do not have permission to do that.');
      expect(mapped.retryable, isFalse);
    });
  });
}
