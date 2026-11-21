// Models, repository and providers for Agent C's sales and shift domain.
// Money is always numeric from the database. Stock and payment totals are
// computed by the RPCs, never by the client.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/permissions.dart';
import '../../../core/state/app_cache.dart';
import '../../../core/supabase_client.dart';
import '../../inventory/data/inventory_providers.dart';

double _money(dynamic value) => switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value) ?? 0,
      _ => 0,
    };

int _int(dynamic value) => switch (value) {
      num() => value.toInt(),
      String() => int.tryParse(value) ?? 0,
      _ => 0,
    };

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value as String);

String? _text(dynamic value) => value as String?;

class Shift {
  const Shift({
    required this.id,
    required this.branchId,
    required this.cashierId,
    this.openedAt,
    this.closedAt,
    this.openingCash = 0,
    this.expectedCash,
    this.closingCash,
    this.difference,
    this.status = 'open',
    this.note,
    this.cashierName,
  });

  final String id;
  final String branchId;
  final String cashierId;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double openingCash;
  final double? expectedCash;
  final double? closingCash;
  final double? difference;
  final String status;
  final String? note;
  final String? cashierName;

  bool get isOpen => status == 'open';

  Shift copyWith({
    String? id,
    String? branchId,
    String? cashierId,
    DateTime? openedAt,
    DateTime? closedAt,
    double? openingCash,
    double? expectedCash,
    double? closingCash,
    double? difference,
    String? status,
    String? note,
    String? cashierName,
  }) =>
      Shift(
        id: id ?? this.id,
        branchId: branchId ?? this.branchId,
        cashierId: cashierId ?? this.cashierId,
        openedAt: openedAt ?? this.openedAt,
        closedAt: closedAt ?? this.closedAt,
        openingCash: openingCash ?? this.openingCash,
        expectedCash: expectedCash ?? this.expectedCash,
        closingCash: closingCash ?? this.closingCash,
        difference: difference ?? this.difference,
        status: status ?? this.status,
        note: note ?? this.note,
        cashierName: cashierName ?? this.cashierName,
      );

  factory Shift.fromJson(Map<String, dynamic> json) {
    final profile = json['cashier'] ?? json['profiles'];
    return Shift(
      id: (json['id'] as String?) ?? '',
      branchId: (json['branch_id'] as String?) ?? '',
      cashierId: (json['cashier_id'] as String?) ?? '',
      openedAt: _date(json['opened_at']),
      closedAt: _date(json['closed_at']),
      openingCash: _money(json['opening_cash']),
      expectedCash:
          json['expected_cash'] == null ? null : _money(json['expected_cash']),
      closingCash:
          json['closing_cash'] == null ? null : _money(json['closing_cash']),
      difference:
          json['difference'] == null ? null : _money(json['difference']),
      status: (json['status'] as String?) ?? 'open',
      note: _text(json['note']),
      cashierName: profile is Map ? _text(profile['full_name']) : null,
    );
  }
}

/// Result of close_shift. The database is the source of truth for the count.
class ShiftCloseResult {
  const ShiftCloseResult({
    required this.expectedCash,
    required this.closingCash,
    required this.difference,
  });

  final double expectedCash;
  final double closingCash;
  final double difference;

  factory ShiftCloseResult.fromRpc(dynamic raw) {
    final map = raw is List && raw.isNotEmpty
        ? Map<String, dynamic>.from(raw.first as Map)
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    return ShiftCloseResult(
      expectedCash: _money(map['expected_cash']),
      closingCash: _money(map['closing_cash']),
      difference: _money(map['difference']),
    );
  }
}

class Sale {
  const Sale({
    required this.id,
    required this.invoiceNo,
    required this.branchId,
    required this.cashierId,
    this.shiftId,
    this.customerId,
    this.prescriptionId,
    this.status = 'completed',
    this.subtotal = 0,
    this.discount = 0,
    this.tax = 0,
    this.total = 0,
    this.paid = 0,
    this.changeDue = 0,
    this.note,
    this.voidReason,
    this.createdAt,
    this.cashierName,
    this.customerName,
  });

  final String id;
  final String invoiceNo;
  final String branchId;
  final String cashierId;
  final String? shiftId;
  final String? customerId;
  final String? prescriptionId;
  final String status;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final double changeDue;
  final String? note;
  final String? voidReason;
  final DateTime? createdAt;
  final String? cashierName;
  final String? customerName;

  factory Sale.fromJson(Map<String, dynamic> json) {
    final cashier = json['cashier'] ?? json['profiles'];
    final customer = json['customer'] ?? json['customers'];
    return Sale(
      id: (json['id'] as String?) ?? '',
      invoiceNo: (json['invoice_no'] as String?) ?? '',
      branchId: (json['branch_id'] as String?) ?? '',
      cashierId: (json['cashier_id'] as String?) ?? '',
      shiftId: _text(json['shift_id']),
      customerId: _text(json['customer_id']),
      prescriptionId: _text(json['prescription_id']),
      status: (json['status'] as String?) ?? 'completed',
      subtotal: _money(json['subtotal']),
      discount: _money(json['discount']),
      tax: _money(json['tax']),
      total: _money(json['total']),
      paid: _money(json['paid']),
      changeDue: _money(json['change_due']),
      note: _text(json['note']),
      voidReason: _text(json['void_reason']),
      createdAt: _date(json['created_at']),
      cashierName: cashier is Map ? _text(cashier['full_name']) : null,
      customerName: customer is Map ? _text(customer['name']) : null,
    );
  }
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.saleId,
    required this.medicineId,
    required this.medicineName,
    this.batchId,
    this.batchNo,
    this.expiryDate,
    this.quantity = 0,
    this.returnedQty = 0,
    this.unitPrice = 0,
    this.lineTotal = 0,
    this.tax = 0,
  });

  final String id;
  final String saleId;
  final String medicineId;
  final String medicineName;
  final String? batchId;
  final String? batchNo;
  final DateTime? expiryDate;
  final int quantity;
  final int returnedQty;
  final double unitPrice;
  final double lineTotal;
  final double tax;

  int get remaining => quantity - returnedQty;

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: (json['id'] as String?) ?? '',
        saleId: (json['sale_id'] as String?) ?? '',
        medicineId: (json['medicine_id'] as String?) ?? '',
        medicineName: (json['medicine_name'] as String?) ?? '',
        batchId: _text(json['batch_id']),
        batchNo: _text(json['batch_no']),
        expiryDate: _date(json['expiry_date']),
        quantity: _int(json['quantity']),
        returnedQty: _int(json['returned_qty']),
        unitPrice: _money(json['unit_price']),
        lineTotal: _money(json['line_total']),
        tax: _money(json['tax']),
      );
}

class SalePayment {
  const SalePayment({
    required this.id,
    required this.saleId,
    required this.method,
    required this.amount,
    this.reference,
  });

  final String id;
  final String saleId;
  final String method;
  final double amount;
  final String? reference;

  factory SalePayment.fromJson(Map<String, dynamic> json) => SalePayment(
        id: (json['id'] as String?) ?? '',
        saleId: (json['sale_id'] as String?) ?? '',
        method: (json['method'] as String?) ?? 'cash',
        amount: _money(json['amount']),
        reference: _text(json['reference']),
      );
}

class SaleReturn {
  const SaleReturn({
    required this.id,
    required this.returnNo,
    required this.saleId,
    required this.branchId,
    this.reason = '',
    this.refundMethod = 'cash',
    this.refundAmount = 0,
    this.createdAt,
    this.invoiceNo,
  });

  final String id;
  final String returnNo;
  final String saleId;
  final String branchId;
  final String reason;
  final String refundMethod;
  final double refundAmount;
  final DateTime? createdAt;
  final String? invoiceNo;

  factory SaleReturn.fromJson(Map<String, dynamic> json) {
    final sale = json['sale'] ?? json['sales'];
    return SaleReturn(
      id: (json['id'] as String?) ?? '',
      returnNo: (json['return_no'] as String?) ?? '',
      saleId: (json['sale_id'] as String?) ?? '',
      branchId: (json['branch_id'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
      refundMethod: (json['refund_method'] as String?) ?? 'cash',
      refundAmount: _money(json['refund_amount']),
      createdAt: _date(json['created_at']),
      invoiceNo: sale is Map ? _text(sale['invoice_no']) : null,
    );
  }
}

/// Filter for the sales history screen.
typedef SaleFilter = ({
  DateTime? from,
  DateTime? to,
  String? cashierId,
  String? status,
  String? method,
  String? invoice,
});

class SalesRepository {
  SupabaseClient get _db => SupabaseService.client;

  // ---- Shifts -----------------------------------------------------------
  Future<Shift?> openShift(String branchId, double openingCash) async {
    final raw = await _db.rpc('open_shift', params: {
      'p_branch': branchId,
      'p_opening_cash': openingCash,
    });
    final id = raw is Map ? raw['id']?.toString() : raw?.toString();
    if (id == null) return null;
    return shift(id);
  }

  Future<Shift> shift(String id) async {
    final row = await _db
        .from('shifts')
        .select('*, cashier:profiles!shifts_cashier_id_fkey(full_name)')
        .eq('id', id)
        .single();
    return Shift.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Shift?> myOpenShift({String? branchId}) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    var query = _db
        .from('shifts')
        .select('*, cashier:profiles!shifts_cashier_id_fkey(full_name)')
        .eq('cashier_id', user.id)
        .eq('status', 'open');
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows =
        await query.order('opened_at', ascending: false).limit(1) as List;
    if (rows.isEmpty) return null;
    return Shift.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<Shift>> shifts({String? branchId, bool openOnly = false}) async {
    var query = _db
        .from('shifts')
        .select('*, cashier:profiles!shifts_cashier_id_fkey(full_name)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    if (openOnly) query = query.eq('status', 'open');
    final rows =
        await query.order('opened_at', ascending: false).limit(200) as List;
    return rows
        .map((row) => Shift.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<ShiftCloseResult> closeShift(
    String shiftId,
    double closingCash,
    String? note,
  ) async {
    final raw = await _db.rpc('close_shift', params: {
      'p_shift': shiftId,
      'p_closing_cash': closingCash,
      'p_note': note,
    });
    return ShiftCloseResult.fromRpc(raw);
  }

  /// Number of completed sales in a shift, read from the sales table.
  Future<int> shiftSaleCount(String shiftId) async {
    final rows = await _db
        .from('sales')
        .select('id')
        .eq('shift_id', shiftId)
        .eq('status', 'completed') as List;
    return rows.length;
  }

  // ---- Sales ------------------------------------------------------------
  Future<String> createSale({
    required String branchId,
    required String shiftId,
    String? customerId,
    String? prescriptionId,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    required double discount,
    String? note,
  }) async {
    final raw = await _db.rpc('create_sale', params: {
      'p_branch': branchId,
      'p_shift': shiftId,
      'p_customer': customerId,
      'p_prescription': prescriptionId,
      'p_items': items,
      'p_payments': payments,
      'p_discount': discount,
      'p_note': note,
    });
    return raw.toString();
  }

  Future<void> voidSale(String saleId, String reason) =>
      _db.rpc('void_sale', params: {
        'p_sale': saleId,
        'p_reason': reason,
      });

  Future<String> processReturn({
    required String saleId,
    required List<Map<String, dynamic>> items,
    required String reason,
    required String refundMethod,
  }) async {
    final raw = await _db.rpc('process_sale_return', params: {
      'p_sale': saleId,
      'p_items': items,
      'p_reason': reason,
      'p_refund_method': refundMethod,
    });
    return raw.toString();
  }

  Future<List<Sale>> sales(SaleFilter filter, String? branchId) async {
    var query = _db.from('sales').select(
        '*, cashier:profiles!sales_cashier_id_fkey(full_name), customer:customers!sales_customer_id_fkey(name)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    if (filter.from != null) {
      query = query.gte(
          'created_at', startOfAddisDayUtc(filter.from!).toIso8601String());
    }
    if (filter.to != null) {
      query = query.lte(
          'created_at', endOfAddisDayUtc(filter.to!).toIso8601String());
    }
    final cashierId = filter.cashierId;
    final status = filter.status;
    if (cashierId != null) query = query.eq('cashier_id', cashierId);
    if (status != null) query = query.eq('status', status);
    final invoice = filter.invoice;
    if (invoice != null && invoice.isNotEmpty) {
      query = query.ilike('invoice_no', '%$invoice%');
    }
    final rows =
        await query.order('created_at', ascending: false).limit(300) as List;
    var result = rows
        .map((row) => Sale.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    if (filter.method != null) {
      final ids = await _paymentSaleIds(filter.method!);
      result = result.where((sale) => ids.contains(sale.id)).toList();
    }
    return result;
  }

  Future<Set<String>> _paymentSaleIds(String method) async {
    final rows = await _db
        .from('sale_payments')
        .select('sale_id')
        .eq('method', method) as List;
    return rows.map((row) => (row as Map)['sale_id'] as String).toSet();
  }

  Future<Sale> sale(String id) async {
    final row = await _db
        .from('sales')
        .select(
            '*, cashier:profiles!sales_cashier_id_fkey(full_name), customer:customers!sales_customer_id_fkey(name)')
        .eq('id', id)
        .single();
    return Sale.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<SaleItem>> saleItems(String saleId) async {
    final rows = await _db
        .from('sale_items')
        .select()
        .eq('sale_id', saleId)
        .order('id') as List;
    return rows
        .map((row) => SaleItem.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<SalePayment>> salePayments(String saleId) async {
    final rows = await _db
        .from('sale_payments')
        .select()
        .eq('sale_id', saleId)
        .order('id') as List;
    return rows
        .map((row) =>
            SalePayment.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<SaleReturn>> saleReturns({String? branchId}) async {
    var query = _db
        .from('sale_returns')
        .select('*, sale:sales!sale_returns_sale_id_fkey(invoice_no)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows =
        await query.order('created_at', ascending: false).limit(300) as List;
    return rows
        .map(
            (row) => SaleReturn.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Settings needed by the receipt and the cart.
  Future<ReceiptSettings> receiptSettings() async {
    const keys = [
      'pharmacy_name',
      'tagline',
      'address',
      'phone',
      'tin',
      'license_no',
      'receipt_footer',
      'vat_rate',
      'max_cashier_discount_pct',
      'currency',
    ];
    final rows = await _db
        .from('app_settings')
        .select('key, value')
        .or(keys.map((key) => 'key.eq.$key').join(',')) as List;
    final values = <String, dynamic>{};
    for (final row in rows) {
      final map = row as Map;
      values[map['key'] as String] = map['value'];
    }
    String text(String key, [String fallback = '']) {
      final raw = values[key];
      if (raw is String) return raw;
      if (raw is Map) return (raw['_'] ?? raw['value'] ?? '').toString();
      return fallback;
    }

    double number(String key, double fallback) {
      final raw = values[key];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? fallback;
      return fallback;
    }

    return ReceiptSettings(
      pharmacyName: text('pharmacy_name', 'Yusra Pharmacy'),
      tagline: text('tagline', 'Care made easy'),
      address: text('address'),
      phone: text('phone'),
      tin: text('tin'),
      licenseNo: text('license_no'),
      footer: text('receipt_footer', 'Thank you for choosing Yusra Pharmacy.'),
      vatRate: number('vat_rate', 0.15),
      maxCashierDiscountPct: number('max_cashier_discount_pct', 5),
    );
  }
}

class ReceiptSettings {
  const ReceiptSettings({
    required this.pharmacyName,
    required this.tagline,
    required this.address,
    required this.phone,
    required this.tin,
    required this.licenseNo,
    required this.footer,
    required this.vatRate,
    required this.maxCashierDiscountPct,
  });

  final String pharmacyName;
  final String tagline;
  final String address;
  final String phone;
  final String tin;
  final String licenseNo;
  final String footer;
  final double vatRate;
  final double maxCashierDiscountPct;
}

final salesRepositoryProvider =
    Provider<SalesRepository>((ref) => SalesRepository());

final receiptSettingsProvider = FutureProvider<ReceiptSettings>((ref) async {
  const fallback = ReceiptSettings(
    pharmacyName: 'Yusra Pharmacy',
    tagline: 'Care made easy',
    address: '',
    phone: '',
    tin: '',
    licenseNo: '',
    footer: 'Thank you for choosing Yusra Pharmacy.',
    vatRate: 0.15,
    maxCashierDiscountPct: 5,
  );
  if (!SupabaseService.isReady) return fallback;

  final scope = ref.watch(authProvider).profile?.branchId ?? 'global';
  final key = AppCache.scopedKey(CacheTag.settings, scope, 'receipt');
  return ref.read(appCacheProvider).read(
        key,
        const Duration(minutes: 10),
        () => ref.read(salesRepositoryProvider).receiptSettings(),
      );
});

/// The shift the current cashier can sell on. Super admins use the selected
/// branch; other roles are scoped by the branch scope provider.
final myOpenShiftProvider = FutureProvider<Shift?>((ref) async {
  if (!SupabaseService.isReady) return null;
  final role = ref.watch(authProvider).profile?.role;
  if (role == null ||
      role == AppRole.accountant ||
      role == AppRole.storeKeeper) {
    return null;
  }
  return ref
      .read(salesRepositoryProvider)
      .myOpenShift(branchId: ref.watch(branchScopeProvider));
});

final shiftsProvider =
    FutureProvider.family<List<Shift>, bool>((ref, openOnly) async {
  if (!SupabaseService.isReady) return const <Shift>[];
  return ref
      .read(salesRepositoryProvider)
      .shifts(branchId: ref.watch(branchScopeProvider), openOnly: openOnly);
});

final salesProvider =
    FutureProvider.family<List<Sale>, SaleFilter>((ref, filter) async {
  if (!SupabaseService.isReady) return const <Sale>[];
  return ref
      .read(salesRepositoryProvider)
      .sales(filter, ref.watch(branchScopeProvider));
});

final saleProvider = FutureProvider.family<Sale, String>((ref, id) async {
  if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
  return ref.read(salesRepositoryProvider).sale(id);
});

final saleItemsProvider =
    FutureProvider.family<List<SaleItem>, String>((ref, saleId) async {
  if (!SupabaseService.isReady) return const <SaleItem>[];
  return ref.read(salesRepositoryProvider).saleItems(saleId);
});

final salePaymentsProvider =
    FutureProvider.family<List<SalePayment>, String>((ref, saleId) async {
  if (!SupabaseService.isReady) return const <SalePayment>[];
  return ref.read(salesRepositoryProvider).salePayments(saleId);
});

final saleReturnsProvider = FutureProvider<List<SaleReturn>>((ref) async {
  if (!SupabaseService.isReady) return const <SaleReturn>[];
  return ref
      .read(salesRepositoryProvider)
      .saleReturns(branchId: ref.watch(branchScopeProvider));
});
