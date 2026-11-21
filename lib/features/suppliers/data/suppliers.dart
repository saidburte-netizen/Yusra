import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.tin,
    this.paymentTerms,
    this.notes,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? tin;
  final String? paymentTerms;
  final String? notes;
  final bool isActive;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        contactPerson: json['contact_person'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        tin: json['tin'] as String?,
        paymentTerms: json['payment_terms'] as String?,
        notes: json['notes'] as String?,
        isActive: json['is_active'] == true || json['is_active'] == 'true',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'contact_person': contactPerson,
        'phone': phone,
        'email': email,
        'address': address,
        'tin': tin,
        'payment_terms': paymentTerms,
        'notes': notes,
      };
}

class SupplierRepository {
  SupabaseClient get _db => SupabaseService.client;

  Future<List<Supplier>> list({String query = ''}) async {
    var request = _db.from('suppliers').select();
    if (query.trim().isNotEmpty) {
      final q = query.trim().replaceAll(RegExp(r'[,()]'), ' ');
      request = request
          .or('name.ilike.%$q%,contact_person.ilike.%$q%,phone.ilike.%$q%');
    }
    final rows = await request.order('name') as List;
    return rows
        .map((row) => Supplier.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> save(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await _db.from('suppliers').insert(data);
    } else {
      await _db.from('suppliers').update(data).eq('id', id);
    }
  }

  Future<void> setActive(String id, bool active) =>
      _db.from('suppliers').update({'is_active': active}).eq('id', id);
}

final supplierRepositoryProvider =
    Provider<SupplierRepository>((ref) => SupplierRepository());

final suppliersProvider =
    FutureProvider.family<List<Supplier>, String>((ref, query) async {
  if (!SupabaseService.isReady) return const <Supplier>[];
  return ref.read(supplierRepositoryProvider).list(query: query);
});
