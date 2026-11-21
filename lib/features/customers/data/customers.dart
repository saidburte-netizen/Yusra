import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class CustomerStats {
  const CustomerStats({
    this.visits = 0,
    this.lifetimeSpend = 0,
    this.outstanding = 0,
    this.lastVisit,
  });

  final int visits;
  final double lifetimeSpend;
  final double outstanding;
  final DateTime? lastVisit;

  factory CustomerStats.fromJson(Map<String, dynamic> json) => CustomerStats(
        visits: (json['visits'] as num?)?.toInt() ?? 0,
        lifetimeSpend: (json['lifetime_spend'] as num?)?.toDouble() ?? 0,
        outstanding: (json['outstanding'] as num?)?.toDouble() ?? 0,
        lastVisit: json['last_visit'] == null
            ? null
            : DateTime.tryParse(json['last_visit'] as String),
      );
}

class CustomersRepository {
  SupabaseClient get _db => SupabaseService.client;

  Future<List<Customer>> search(String query) async {
    var request = _db.from('customers').select();
    if (query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      request = request.or('name.ilike.$q,phone.ilike.$q');
    }
    final rows = await request.order('name').limit(100) as List;
    return rows
        .map((row) => Customer.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Customer> byId(String id) async {
    final row = await _db.from('customers').select().eq('id', id).single();
    return Customer.fromJson(Map<String, dynamic>.from(row));
  }

  /// Server-side totals from 0019. Direct table reads are capped and can miss
  /// voided or older sales, so the detail screen must use the RPC.
  Future<CustomerStats> stats(String id) async {
    if (!SupabaseService.isReady) return const CustomerStats();
    final row = await _db.rpc('customer_stats', params: {'p_customer': id})
        as Map<String, dynamic>?;
    return CustomerStats.fromJson(row ?? const {});
  }

  Future<Customer> save(Map<String, dynamic> values, {String? id}) async {
    final payload = <String, dynamic>{
      'name': (values['name'] as String? ?? '').trim(),
      'phone': _emptyToNull(values['phone']),
      'email': _emptyToNull(values['email']),
      'address': _emptyToNull(values['address']),
      'notes': _emptyToNull(values['notes']),
    };
    final rows = id == null
        ? await _db.from('customers').insert(payload).select() as List
        : await _db.from('customers').update(payload).eq('id', id).select()
            as List;
    return Customer.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<void> setActive(String id, bool active) =>
      _db.from('customers').update({'is_active': active}).eq('id', id);

  static String? _emptyToNull(dynamic value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

final customersRepositoryProvider =
    Provider<CustomersRepository>((ref) => CustomersRepository());

final customersProvider =
    FutureProvider.family<List<Customer>, String>((ref, query) async {
  if (!SupabaseService.isReady) return const <Customer>[];
  return ref.read(customersRepositoryProvider).search(query);
});

final customerProvider =
    FutureProvider.family<Customer, String>((ref, id) async {
  return ref.read(customersRepositoryProvider).byId(id);
});

final customerStatsProvider =
    FutureProvider.family<CustomerStats, String>((ref, id) async {
  return ref.read(customersRepositoryProvider).stats(id);
});
