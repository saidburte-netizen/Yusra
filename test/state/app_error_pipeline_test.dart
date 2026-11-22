import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yusra_pharmacy/core/errors/app_error.dart';
import 'package:yusra_pharmacy/core/state/idempotency.dart';
import 'package:yusra_pharmacy/core/strings.dart';

void main() {
  group('AppErrorMapper WS4 additions', () {
    test('maps offline exception to retryable OFFLINE code', () {
      final mapped = AppErrorMapper.from(const OfflineException());
      expect(mapped.kind, AppErrorKind.network);
      expect(mapped.retryable, isTrue);
      expect(mapped.code, 'OFFLINE');
      expect(mapped.message, S.noConnection);
    });

    test('maps duplicate submit to validation DUPLICATE', () {
      final mapped = AppErrorMapper.from(const DuplicateSubmitException());
      expect(mapped.kind, AppErrorKind.validation);
      expect(mapped.code, 'DUPLICATE');
    });

    test('maps expired auth session to AUTH_EXPIRED and login routing flag',
        () {
      final mapped = AppErrorMapper.from(
        const AuthException('JWT expired'),
      );
      expect(mapped.kind, AppErrorKind.authentication);
      expect(mapped.code, 'AUTH_EXPIRED');
      expect(mapped.isSessionExpired, isTrue);
      expect(mapped.message, S.sessionExpired);
    });

    test('maps 401 FunctionException to AUTH_EXPIRED', () {
      final mapped = AppErrorMapper.from(const FunctionException(status: 401));
      expect(mapped.kind, AppErrorKind.authentication);
      expect(mapped.code, 'AUTH_EXPIRED');
      expect(mapped.isSessionExpired, isTrue);
    });

    test('maps PostgREST JWT/401-like expiry to AUTH_EXPIRED', () {
      final mapped = AppErrorMapper.from(
        const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
      );
      expect(mapped.kind, AppErrorKind.authentication);
      expect(mapped.code, 'AUTH_EXPIRED');
      expect(mapped.isSessionExpired, isTrue);
    });

    test('sanitizedLogLine contains only kind/code, no PII', () {
      final mapped = AppErrorMapper.from(
        const PostgrestException(
          message: 'permission denied for table sales user=alice@example.com',
          code: '42501',
        ),
      );
      expect(mapped.sanitizedLogLine, 'permission:42501');
      expect(mapped.sanitizedLogLine, isNot(contains('alice')));
      expect(mapped.sanitizedLogLine, isNot(contains('@')));
    });

    test('network/timeout/42501/23xxx/P000x still mapped with codes', () {
      final net = AppErrorMapper.from(const SocketException('x'));
      expect(net.code, 'NETWORK');
      expect(net.kind, AppErrorKind.network);
      final timeout = AppErrorMapper.from(TimeoutException('x'));
      expect(timeout.code, 'TIMEOUT');
      final perm = AppErrorMapper.from(
          const PostgrestException(message: 'denied', code: '42501'));
      expect(perm.code, '42501');
      expect(perm.kind, AppErrorKind.permission);
      final unique = AppErrorMapper.from(
          const PostgrestException(message: 'dup', code: '23505'));
      expect(unique.code, '23505');
      expect(unique.kind, AppErrorKind.validation);
      final p0001 = AppErrorMapper.from(
          const PostgrestException(message: 'stock', code: 'P0001'));
      expect(p0001.code, 'P0001');
    });
  });
}
