/// Prescription row model. Pure Dart so mapping database JSON is testable
/// without pulling in Supabase or Flutter widgets.
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
    final age = json['patient_age'];
    return Prescription(
      id: (json['id'] as String?) ?? '',
      rxNo: (json['rx_no'] as String?) ?? '',
      branchId: (json['branch_id'] as String?) ?? '',
      patientName: (json['patient_name'] as String?) ?? '',
      patientAge: age == null
          ? null
          : (age is num ? age.toInt() : int.tryParse(age.toString())),
      prescriberName: (json['prescriber_name'] as String?) ?? '',
      prescriberLicense: json['prescriber_license'] as String?,
      facility: json['facility'] as String?,
      rxDate: json['rx_date'] == null
          ? null
          : DateTime.tryParse(json['rx_date'] as String),
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
