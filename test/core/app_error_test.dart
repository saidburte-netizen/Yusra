import 'dart:async';
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

    // PR #17 mapping must stay byte-for-byte: no extra code line is added to
    // FunctionException messages.
    test('FunctionException mapping from PR #17 is preserved', () {
      const conflict = FunctionException(
        status: 409,
        details: {
          'error': {'code': 'conflict', 'message': 'Duplicate email'}
        },
      );
      final mapped = AppErrorMapper.from(conflict);
      expect(mapped.message, 'Duplicate email');
      expect(mapped.code, isNull);
      expect(mapped.codeLine, isNull);
      expect(mapped.message, isNot(contains('Error code:')));
    });

    const cases = <Map<String, String>>[
      {
        'code': 'PGRST200',
        'raw': 'Could not find a relationship between sale_items and medicines',
        'friendly': 'link between records',
      },
      {
        'code': 'PGRST201',
        'raw': 'Could not embed because more than one relationship was found',
        'friendly': 'several matches',
      },
      {
        'code': 'PGRST204',
        'raw': 'No content found for the requested range',
        'friendly': 'No data',
      },
      {
        'code': '42501',
        'raw': 'permission denied for table sales',
        'friendly': 'permission',
      },
      {
        'code': '42P01',
        'raw': 'relation "public.v_top_medicines" does not exist',
        'friendly': 'table',
      },
      {
        'code': '42703',
        'raw': 'column s.profit does not exist',
        'friendly': 'column',
      },
      {
        'code': '23503',
        'raw': 'insert or update violates foreign key constraint',
        'friendly': 'linked record',
      },
      {
        'code': '23505',
        'raw': 'duplicate key value violates unique constraint',
        'friendly': 'already used',
      },
      {
        'code': '23514',
        'raw': 'new row violates check constraint "quantity_positive"',
        'friendly': 'not allowed',
      },
      {
        'code': 'P0001',
        'raw': 'insufficient stock quantity',
        'friendly': 'stock',
      },
      {
        'code': 'P0002',
        'raw': 'no_data_found: select into returned no rows',
        'friendly': 'not found',
      },
    ];

    for (final testCase in cases) {
      final code = testCase['code']!;
      test('maps $code to friendly text plus a copyable code line', () {
        final mapped = AppErrorMapper.from(
          PostgrestException(message: testCase['raw']!, code: code),
        );
        expect(mapped.code, code);
        expect(mapped.codeLine, 'Error code: $code');
        expect(mapped.message, contains(testCase['friendly']!));
        expect(mapped.message, contains('Error code: $code'));
        // Code only: none of the raw SQL text may reach the UI.
        expect(mapped.message, isNot(contains('SELECT')));
        expect(mapped.message, isNot(contains('relation')));
        expect(mapped.message, isNot(contains('constraint')));
        expect(mapped.message, isNot(contains('violates')));
      });
    }

    test('network errors expose a short, copyable code', () {
      final socket = AppErrorMapper.from(const SocketException('refused'));
      expect(socket.code, 'NETWORK');
      expect(socket.message, contains('Error code: NETWORK'));
      expect(socket.kind, AppErrorKind.network);
      expect(socket.retryable, isTrue);

      final timeout = AppErrorMapper.from(TimeoutException('late'));
      expect(timeout.code, 'TIMEOUT');
      expect(timeout.message, contains('Error code: TIMEOUT'));
      expect(timeout.kind, AppErrorKind.network);
      expect(timeout.retryable, isTrue);
    });

    test('a verbose or SQL-shaped code is never echoed back', () {
      final mapped = AppErrorMapper.from(
        const PostgrestException(
          message: 'permission denied for table sales',
          code: '42501 permission denied for table sales',
        ),
      );
      expect(mapped.code, isNull);
      expect(mapped.codeLine, isNull);
      expect(mapped.message, isNot(contains('permission denied for table')));
      expect(mapped.message, isNot(contains('Error code:')));
    });
  });
}
