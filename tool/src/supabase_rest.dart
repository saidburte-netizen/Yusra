// Minimal Supabase REST client for the maintenance tools. Plain Dart + dart:io
// only, so `dart run tool/smoke_test.dart` needs no extra packages and the
// tools can never accidentally use the app's signed-in session.

import 'dart:convert';
import 'dart:io';

class RestException implements Exception {
  const RestException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode: $body';
}

class RestResponse {
  const RestResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class SupabaseRest {
  SupabaseRest({
    required this.url,
    required this.anonKey,
    String? token,
  })  : _base = Uri.parse(url.replaceAll(RegExp(r'/$'), '')),
        _token = token;

  final String url;
  final String anonKey;
  final Uri _base;
  String? _token;

  factory SupabaseRest.fromEnv() => SupabaseRest(
        url: _env('SUPABASE_URL'),
        anonKey: _env('SUPABASE_ANON_KEY'),
      );

  static String _env(String key) {
    final value = Platform.environment[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable $key');
    }
    return value;
  }

  /// Service-role client for seeding. The key is supplied through the
  /// environment at runtime and is never stored in the repository.
  factory SupabaseRest.service({required String url, required String serviceRoleKey}) =>
      SupabaseRest(url: url, anonKey: serviceRoleKey, token: serviceRoleKey);

  /// Creates an Auth user through the admin endpoint. The `handle_new_user`
  /// trigger creates the matching profile from the app metadata.
  Future<Map<String, dynamic>?> adminCreateUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
    required String branchId,
  }) async {
    try {
      final response = await _send(
        'POST',
        _base.replace(path: '/auth/v1/admin/users'),
        body: {
          'email': email,
          'password': password,
          'email_confirm': true,
          'user_metadata': {'full_name': fullName},
          'app_metadata': {'role': role, 'branch_id': branchId},
        },
      );
      final decoded = jsonDecode(response.body);
      return Map<String, dynamic>.from(decoded as Map);
    } on RestException catch (error) {
      if (error.statusCode == 422 || error.statusCode == 409) return null;
      rethrow;
    }
  }

  Future<void> deleteWhere(String table, Map<String, String> filters) async {
    await _send(
      'DELETE',
      _base.replace(path: '/rest/v1/$table', queryParameters: filters),
      headers: {'Prefer': 'return=minimal'},
    );
  }

  /// Safety gate shared by both tools. A production-looking URL is refused
  /// unless the operator explicitly confirms. [confirmVar] defaults to
  /// SMOKE_CONFIRM so existing callers stay backward compatible; the seeder
  /// passes SEED_CONFIRM instead.
  static void assertSafeTarget({String confirmVar = 'SMOKE_CONFIRM'}) {
    final url = Platform.environment['SUPABASE_URL'] ?? '';
    if (url.toLowerCase().contains('prod') &&
        Platform.environment[confirmVar] != '1') {
      throw StateError(
        'Refusing to run: SUPABASE_URL contains "prod" and $confirmVar '
        'is not set to 1. Set $confirmVar=1 after double-checking the target.',
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    final response = await _send(
      'POST',
      _base.replace(
        path: '/auth/v1/token',
        queryParameters: {'grant_type': 'password'},
      ),
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['access_token'] as String?;
    if (token == null) {
      throw StateError('No access token returned for $email: ${response.body}');
    }
    _token = token;
  }

  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    Map<String, String> filters = const {},
  }) async {
    final query = <String, String>{'select': columns, ...filters};
    final response = await _send(
      'GET',
      _base.replace(path: '/rest/v1/$table', queryParameters: query),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Inserts and returns the created rows (PostgREST `return=representation`).
  Future<List<Map<String, dynamic>>> insert(
    String table,
    Map<String, dynamic> values,
  ) async {
    final response = await _send(
      'POST',
      _base.replace(path: '/rest/v1/$table'),
      body: values,
      headers: {'Prefer': 'return=representation'},
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Returns the HTTP status so tests can assert that RLS refused a write.
  Future<int> tryInsert(String table, Map<String, dynamic> values) async {
    try {
      await _send(
        'POST',
        _base.replace(path: '/rest/v1/$table'),
        body: values,
        headers: {'Prefer': 'return=minimal'},
      );
      return 201;
    } on RestException catch (error) {
      return error.statusCode;
    }
  }

  Future<RestResponse> tryRpc(
    String name, [
    Map<String, dynamic>? params,
  ]) async {
    try {
      return await _send(
        'POST',
        _base.replace(path: '/rest/v1/rpc/$name'),
        body: params ?? const {},
      );
    } on RestException catch (error) {
      return RestResponse(error.statusCode, error.body);
    }
  }

  Future<dynamic> rpc(String name, [Map<String, dynamic>? params]) async {
    final response = await _send(
      'POST',
      _base.replace(path: '/rest/v1/rpc/$name'),
      body: params ?? const {},
    );
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, String> filters,
  }) async {
    await _send(
      'PATCH',
      _base.replace(path: '/rest/v1/$table', queryParameters: filters),
      body: values,
      headers: {'Prefer': 'return=minimal'},
    );
  }

  Future<RestResponse> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers
        ..add('apikey', anonKey)
        ..add('Content-Type', 'application/json')
        ..add('Accept', 'application/json');
      for (final entry in headers.entries) {
        request.headers.add(entry.key, entry.value);
      }
      if (authenticated && _token != null) {
        request.headers.add('Authorization', 'Bearer $_token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw RestException(response.statusCode, text);
      }
      return RestResponse(response.statusCode, text);
    } finally {
      client.close();
    }
  }
}
