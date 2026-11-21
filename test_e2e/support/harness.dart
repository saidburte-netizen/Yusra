// Shared plumbing for the PostgREST-backed e2e-api suite.
//
// SupabaseClient always talks to <url>/rest/v1, while bare PostgREST serves the
// same API at the root. The tiny reverse proxy below bridges that gap without
// adding an HTTP test dependency. Every JWT is signed locally with the same
// HS256 secret the CI PostgREST container uses.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:yusra_pharmacy/core/supabase_client.dart';

final class E2eEnv {
  E2eEnv._();

  static late String postgrestUrl;
  static late String jwtSecret;
  static late String runId;
  static late Uri proxyUrl;

  static void init() {
    postgrestUrl =
        (Platform.environment['E2E_POSTGREST_URL'] ?? 'http://127.0.0.1:3000')
            .replaceAll(RegExp(r'/+$'), '');
    jwtSecret = Platform.environment['PGRST_JWT_SECRET'] ??
        'e2e-only-hs256-secret-at-least-32-chars-long';
    runId = 'e2e${DateTime.now().microsecondsSinceEpoch}'
        '${Random().nextInt(1 << 20).toRadixString(16)}';
    proxyUrl = Uri.parse('http://127.0.0.1:0');
  }
}

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// HS256 JWT accepted by PostgREST. `sub` drives auth.uid(); the database reads
/// the app role from `profiles`, so only the database role belongs in `role`.
String signJwt(String subject) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final header = _b64url(utf8.encode(jsonEncode({
    'alg': 'HS256',
    'typ': 'JWT',
  })));
  final payload = _b64url(utf8.encode(jsonEncode({
    'aud': 'authenticated',
    'role': 'authenticated',
    'sub': subject,
    'iat': now,
    'exp': now + 3600,
  })));
  final signingInput = '$header.$payload';
  final signature = _b64url(Hmac(sha256, utf8.encode(E2eEnv.jwtSecret))
      .convert(utf8.encode(signingInput))
      .bytes);
  return '$signingInput.$signature';
}

final class PostgrestProxy {
  PostgrestProxy._();

  static final HttpClient _forwarder = HttpClient();
  static HttpServer? _server;

  static Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    E2eEnv.proxyUrl =
        Uri.parse('http://127.0.0.1:${(_server as HttpServer).port}');
    _server!.listen((request) {
      _handle(request).catchError((Object error, StackTrace stack) {
        stdout.writeln('[proxy] $error');
        try {
          request.response.statusCode = HttpStatus.badGateway;
          request.response.write('proxy error: $error');
          request.response.close();
        } catch (_) {
          // The client already went away.
        }
      });
    });
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _forwarder.close();
  }

  static const _prefix = '/rest/v1';
  static const _skipRequestHeaders = {
    'host',
    'content-length',
    'transfer-encoding',
    'accept-encoding',
    'connection',
  };
  static const _skipResponseHeaders = {
    'transfer-encoding',
    'content-length',
    'connection',
  };

  static Future<void> _handle(HttpRequest request) async {
    final requestPath = request.uri.toString();
    if (!requestPath.startsWith(_prefix)) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('expected $_prefix path, got $requestPath');
      await request.response.close();
      return;
    }
    final target = Uri.parse('${E2eEnv.postgrestUrl}'
        '${requestPath.substring(_prefix.length)}');
    final forwarded = await _forwarder.openUrl(request.method, target);
    request.headers.forEach((name, values) {
      if (_skipRequestHeaders.contains(name.toLowerCase())) return;
      for (final value in values) {
        forwarded.headers.add(name, value);
      }
    });
    await forwarded.addStream(request);
    final upstream = await forwarded.close();
    request.response.statusCode = upstream.statusCode;
    upstream.headers.forEach((name, values) {
      if (_skipResponseHeaders.contains(name.toLowerCase())) return;
      for (final value in values) {
        request.response.headers.add(name, value);
      }
    });
    await request.response.addStream(upstream);
    await request.response.close();
  }
}

/// Repositories read this override on every call, so swapping users between
/// awaited operations is enough to change the signed-in identity.
SupabaseClient? _currentClient;

void useUser(String userId) {
  _currentClient?.dispose();
  _currentClient = SupabaseClient(
    E2eEnv.proxyUrl.toString(),
    'e2e-anon-key',
    headers: {
      'apikey': 'e2e-anon-key',
      'Authorization': 'Bearer ${signJwt(userId)}',
    },
  );
  SupabaseService.setE2eClient(_currentClient!);
}

/// Fails with the actual PostgREST code/message instead of an opaque stack.
Future<T> api<T>(String label, Future<T> Function() operation) async {
  try {
    return await operation();
  } on PostgrestException catch (error) {
    fail('[$label] PostgREST error: code=${error.code} '
        'message=${error.message} details=${error.details} '
        'hint=${error.hint}');
  }
}

/// An operation that must be rejected by RLS or by a database RPC.
Future<void> expectApiError(
    String label, Future<void> Function() operation) async {
  try {
    await operation();
    fail('[$label] expected a PostgREST error, but the call succeeded');
  } on PostgrestException catch (error) {
    stdout.writeln('  [$label] expected error code=${error.code} '
        'message=${error.message}');
    expect(error.code, isNotNull,
        reason: '[$label] error code must be printed');
  }
}

String newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Mirrors the admin-create-user Edge Function at the database level.
/// auth.users is not in the public schema, so this one fixture goes through
/// psql; the profile and its role are created by the database trigger.
Future<String> createUserViaSql({
  required String role,
  required String branchId,
  required String label,
}) async {
  final id = newUuid();
  final result = await Process.run(
    'bash',
    [
      'tool/e2e_postgrest.sh',
      'create-user',
      id,
      'e2e-$label-${E2eEnv.runId}@example.test',
      role,
      branchId,
      'E2E $label ${E2eEnv.runId}',
    ],
    workingDirectory: Directory.current.path,
  );
  if (result.exitCode != 0) {
    fail('[create-user $label] exit=${result.exitCode}\n'
        'stdout=${result.stdout}\nstderr=${result.stderr}');
  }
  return id;
}
