// Plain data for the opening-stock and reorder RPC/view contract (0022).
// Supabase can return numbers as num or String depending on the client, so the
// shared parsers from inventory_models.dart are used here as well.

import 'inventory_models.dart';

class OpeningStockRowInput {
  const OpeningStockRowInput({
    required this.medicineId,
    required this.quantity,
    required this.expiry,
    this.batchNo,
    this.unitCost = 0,
  });

  final String medicineId;
  final int quantity;
  final DateTime expiry;
  final String? batchNo;
  final double unitCost;

  Map<String, dynamic> toJson() {
    final batch = batchNo?.trim();
    return {
      'medicine_id': medicineId,
      'quantity': quantity,
      'expiry_date': _date(expiry),
      'batch_no': batch == null || batch.isEmpty ? null : batch,
      'unit_cost': unitCost,
    };
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class ReorderSuggestion {
  const ReorderSuggestion({
    required this.branchId,
    required this.medicineId,
    required this.name,
    this.sku,
    required this.unit,
    required this.onHand,
    required this.availableQty,
    required this.expiringQty,
    required this.reorderLevel,
    required this.targetLevel,
    required this.suggestedOrderQty,
    this.preferredSupplierId,
    this.preferredSupplierName,
    required this.lastPurchaseCost,
    required this.reason,
  });

  final String branchId;
  final String medicineId;
  final String name;
  final String? sku;
  final String unit;
  final int onHand;
  final int availableQty;
  final int expiringQty;
  final int reorderLevel;
  final int targetLevel;
  final int suggestedOrderQty;
  final String? preferredSupplierId;
  final String? preferredSupplierName;
  final double lastPurchaseCost;
  final String reason;

  factory ReorderSuggestion.fromJson(Map<String, dynamic> json) =>
      ReorderSuggestion(
        branchId: (json['branch_id'] as String?) ?? '',
        medicineId: (json['medicine_id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        sku: json['sku'] as String?,
        unit: (json['unit'] as String?) ?? 'Pack',
        onHand: intValue(json['on_hand']),
        availableQty: intValue(json['available_qty']),
        expiringQty: intValue(json['expiring_qty']),
        reorderLevel: intValue(json['reorder_level']),
        targetLevel: intValue(json['target_level']),
        suggestedOrderQty: intValue(json['suggested_order_qty']),
        preferredSupplierId: json['preferred_supplier_id'] as String?,
        preferredSupplierName: json['preferred_supplier_name'] as String?,
        lastPurchaseCost: moneyValue(json['last_purchase_cost']),
        reason: (json['reason'] as String?) ?? '',
      );
}
