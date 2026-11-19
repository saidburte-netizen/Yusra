import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/supabase_client.dart';
import '../../inventory/data/inventory_providers.dart';

class Prescription {
  const Prescription({
    required this.id,
    required this.rxNo,
    required this.branchId,
    required this.patientName,
    this.patientAge,
    required this.prescriberName,
    this.prescriberLicense,
    this.facility,
    this.rxDate,
    this.imagePath,
    this.notes,
    this.status = 'pending',
    this.customerId,
    this.dispensedBy,
    this.saleId,
  });

  final String id;
  final String rxNo;
  final String branchId;
  final String patientName;
  final int? patientAge;
  final String prescriberName;
  final String? prescriberLicense;
  final String? facility;
  final DateTime? rxDate;
  final String? imagePath;
  final String? notes;
  final String status;
  final String? customerId;
  final String? dispensedBy;
  final String? saleId;

  factory Prescription.fromJson(Map<String, dynamic> json) {
    final sale = json['sales'];
    return Prescription(
      id: (json['id'] as String?) ?? '',
      rxNo: (json['rx_no'] as String?) ?? '',
      branchId: (json['branch_id'] as String?) ?? '',
      patientName: (json['patient_name'] as String?) ?? '',
      patientAge: json['patient_age'] == null ? null : (json['patient_age'] as num).toInt(),
      prescriberName: (json['prescriber_name'] as String?) ?? '',
      prescriberLicense: json['prescriber_license'] as String?,
      facility: json['facility'] as String?,
      rxDate: json['rx_date'] == null ? null : DateTime.tryParse(json['rx_date'] as String),
      imagePath: json['image_path'] as String?,
      notes: json['notes'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      customerId: json['customer_id'] as String?,
      dispensedBy: json['dispensed_by'] as String?,
      saleId: sale is List && sale.isNotEmpty
          ? (sale.first as Map)['id'] as String?
          : null,
    );
  }
}

class PrescriptionsRepository {
  SupabaseClient get _db => SupabaseService.client;
  static const bucket = 'prescriptions';

  Future<List<Prescription>> list({required String? branchId, String? status}) async {
    var query = _db.from('prescriptions').select('*, sales(id)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('created_at', ascending: false).limit(200) as List;
    return rows
        .map((row) => Prescription.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Prescription> save({
    String? id,
    required String branchId,
    required String patientName,
    int? patientAge,
    required String prescriberName,
    String? prescriberLicense,
    String? facility,
    required DateTime rxDate,
    String? notes,
    String? customerId,
    String? imagePath,
  }) async {
    final payload = <String, dynamic>{
      'branch_id': branchId,
      'patient_name': patientName.trim(),
      'patient_age': patientAge,
      'prescriber_name': prescriberName.trim(),
      'prescriber_license': prescriberLicense?.trim(),
      'facility': facility?.trim(),
      'rx_date': formatIsoDate(rxDate),
      'notes': notes?.trim(),
      'customer_id': customerId,
      if (imagePath != null) 'image_path': imagePath,
    };
    final rows = id == null
        ? await _db.from('prescriptions').insert(payload).select() as List
        : await _db.from('prescriptions').update(payload).eq('id', id).select() as List;
    return Prescription.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<void> cancel(String id) => _db
      .from('prescriptions')
      .update({'status': 'cancelled'})
      .eq('id', id)
      .eq('status', 'pending');

  /// Uploads under <branch_id>/<rx_id>/<filename> so the Storage policy can
  /// scope access by the first folder. Returns the stored object path.
  Future<String> uploadImage({
    required String branchId,
    required String prescriptionId,
    required File file,
  }) async {
    final rawName = file.path.split(Platform.pathSeparator).last;
    final dot = rawName.lastIndexOf('.');
    final extension = dot >= 0 ? rawName.substring(dot) : '';
    final name = '${DateTime.now().microsecondsSinceEpoch}$extension';
    final path = '$branchId/$prescriptionId/$name';
    await _db.storage.from(bucket).upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  Future<String?> signedImageUrl(String path) async {
    try {
      return await _db.storage
          .from(bucket)
          .createSignedUrl(path, 60 * 10);
    } catch (_) {
      return null;
    }
  }
}

final prescriptionsRepositoryProvider =
    Provider<PrescriptionsRepository>((ref) => PrescriptionsRepository());

final prescriptionsProvider =
    FutureProvider.family<List<Prescription>, String?>((ref, status) async {
  if (!SupabaseService.isReady) return const <Prescription>[];
  final profile = ref.watch(authProvider).profile;
  if (profile == null) return const <Prescription>[];
  final branchId = ref.watch(branchScopeProvider);
  // A super admin with no branch selected sees every branch.
  return ref
      .read(prescriptionsRepositoryProvider)
      .list(branchId: branchId, status: status);
});
