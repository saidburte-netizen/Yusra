// Plain models for Agent B's tables and views. Supabase returns numeric columns
// as num or String depending on the client version, so all numbers are parsed.

double moneyValue(dynamic value) => switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value) ?? 0,
      _ => 0,
    };

int intValue(dynamic value) => switch (value) {
      num() => value.toInt(),
      String() => int.tryParse(value) ?? 0,
      _ => 0,
    };

bool boolValue(dynamic value) => value == true || value == 'true';

class Category {
  const Category({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? description;
  final bool isActive;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        isActive: boolValue(json['is_active']),
      );
}

class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    this.sku = '',
    this.barcode,
    this.genericName,
    this.categoryId,
    this.dosageForm,
    this.strength,
    this.unit = 'Pack',
    this.manufacturer,
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.vatApplicable = false,
    this.requiresPrescription = false,
    this.isControlled = false,
    this.reorderLevel = 10,
    this.storageNotes,
    this.imageUrl,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String? genericName;
  final String? categoryId;
  final String? dosageForm;
  final String? strength;
  final String unit;
  final String? manufacturer;
  final double costPrice;
  final double sellingPrice;
  final bool vatApplicable;
  final bool requiresPrescription;
  final bool isControlled;
  final int reorderLevel;
  final String? storageNotes;
  final String? imageUrl;
  final bool isActive;

  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        sku: (json['sku'] as String?) ?? '',
        barcode: json['barcode'] as String?,
        genericName: json['generic_name'] as String?,
        categoryId: json['category_id'] as String?,
        dosageForm: json['dosage_form'] as String?,
        strength: json['strength'] as String?,
        unit: (json['unit'] as String?) ?? 'Pack',
        manufacturer: json['manufacturer'] as String?,
        costPrice: moneyValue(json['cost_price']),
        sellingPrice: moneyValue(json['selling_price']),
        vatApplicable: boolValue(json['vat_applicable']),
        requiresPrescription: boolValue(json['requires_prescription']),
        isControlled: boolValue(json['is_controlled']),
        reorderLevel: intValue(json['reorder_level']),
        storageNotes: json['storage_notes'] as String?,
        imageUrl: json['image_url'] as String?,
        isActive: boolValue(json['is_active']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'generic_name': genericName,
        'barcode': barcode,
        'category_id': categoryId,
        'dosage_form': dosageForm,
        'strength': strength,
        'unit': unit,
        'manufacturer': manufacturer,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'vat_applicable': vatApplicable,
        'requires_prescription': requiresPrescription,
        'is_controlled': isControlled,
        'reorder_level': reorderLevel,
        'storage_notes': storageNotes,
        'image_url': imageUrl,
      };
}

class StockSummary {
  const StockSummary({
    required this.branchId,
    required this.medicineId,
    required this.name,
    this.genericName,
    this.sku,
    this.categoryId,
    this.unit = 'Pack',
    this.reorderLevel = 10,
    this.sellingPrice = 0,
    this.costPrice = 0,
    this.isActive = true,
    this.availableQty = 0,
    this.expiredQty = 0,
    this.nearestExpiry,
  });

  final String branchId;
  final String medicineId;
  final String name;
  final String? genericName;
  final String? sku;
  final String? categoryId;
  final String unit;
  final int reorderLevel;
  final double sellingPrice;
  final double costPrice;
  final bool isActive;
  final int availableQty;
  final int expiredQty;
  final DateTime? nearestExpiry;

  factory StockSummary.fromJson(Map<String, dynamic> json) => StockSummary(
        branchId: (json['branch_id'] as String?) ?? '',
        medicineId: (json['medicine_id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        genericName: json['generic_name'] as String?,
        sku: json['sku'] as String?,
        categoryId: json['category_id'] as String?,
        unit: (json['unit'] as String?) ?? 'Pack',
        reorderLevel: intValue(json['reorder_level']),
        sellingPrice: moneyValue(json['selling_price']),
        costPrice: moneyValue(json['cost_price']),
        isActive: boolValue(json['is_active']),
        availableQty: intValue(json['available_qty']),
        expiredQty: intValue(json['expired_qty']),
        nearestExpiry: json['nearest_expiry'] == null
            ? null
            : DateTime.tryParse(json['nearest_expiry'] as String),
      );

  int get daysToNearestExpiry {
    final expiry = nearestExpiry;
    if (expiry == null) return 3650;
    final now = DateTime.now();
    return DateTime(expiry.year, expiry.month, expiry.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }
}

class StockBatch {
  const StockBatch({
    required this.id,
    required this.branchId,
    required this.medicineId,
    required this.batchNo,
    required this.expiryDate,
    this.quantity = 0,
    this.initialQuantity = 0,
    this.costPrice = 0,
    this.supplierId,
    this.purchaseOrderId,
    this.isActive = true,
    this.medicineName,
  });

  final String id;
  final String branchId;
  final String medicineId;
  final String batchNo;
  final DateTime expiryDate;
  final int quantity;
  final int initialQuantity;
  final double costPrice;
  final String? supplierId;
  final String? purchaseOrderId;
  final bool isActive;
  final String? medicineName;

  int get daysLeft {
    final now = DateTime.now();
    return DateTime(expiryDate.year, expiryDate.month, expiryDate.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  factory StockBatch.fromJson(Map<String, dynamic> json) => StockBatch(
        id: (json['id'] as String?) ?? '',
        branchId: (json['branch_id'] as String?) ?? '',
        medicineId: (json['medicine_id'] as String?) ?? '',
        batchNo: (json['batch_no'] as String?) ?? '',
        expiryDate: DateTime.tryParse((json['expiry_date'] as String?) ?? '') ??
            DateTime(2099),
        quantity: intValue(json['quantity']),
        initialQuantity: intValue(json['initial_quantity']),
        costPrice: moneyValue(json['cost_price']),
        supplierId: json['supplier_id'] as String?,
        purchaseOrderId: json['purchase_order_id'] as String?,
        isActive: boolValue(json['is_active']),
        medicineName: json['name'] as String?,
      );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.branchId,
    required this.medicineId,
    required this.type,
    required this.quantityChange,
    this.batchId,
    this.referenceType,
    this.referenceId,
    this.reason,
    this.createdBy,
    this.createdAt,
    this.medicineName,
  });

  final int id;
  final String branchId;
  final String medicineId;
  final String type;
  final int quantityChange;
  final String? batchId;
  final String? referenceType;
  final String? referenceId;
  final String? reason;
  final String? createdBy;
  final DateTime? createdAt;
  final String? medicineName;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: intValue(json['id']),
        branchId: (json['branch_id'] as String?) ?? '',
        medicineId: (json['medicine_id'] as String?) ?? '',
        type: (json['movement_type'] as String?) ?? '',
        quantityChange: intValue(json['quantity_change']),
        batchId: json['batch_id'] as String?,
        referenceType: json['reference_type'] as String?,
        referenceId: json['reference_id'] as String?,
        reason: json['reason'] as String?,
        createdBy: json['created_by'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
        medicineName: json['name'] as String?,
      );
}
