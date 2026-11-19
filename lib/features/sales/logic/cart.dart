// Pure POS cart logic. No Flutter, no Supabase — fully unit-testable.
// Prices from the database exclude VAT; VAT is applied per line only when the
// medicine is marked vat_applicable. All quantities are whole units.

import '../../../core/permissions.dart';

/// Round to two decimals the way the database `numeric(14,2)` columns do.
double round2(double value) => (value * 100).roundToDouble() / 100;

class CartLine {
  const CartLine({
    required this.medicineId,
    required this.name,
    required this.quantity,
    required this.availableQty,
    required this.unitPrice,
    this.sku = '',
    this.vatApplicable = false,
    this.requiresPrescription = false,
    this.isControlled = false,
    this.nearestExpiry,
  });

  final String medicineId;
  final String name;
  final int quantity;
  final int availableQty;
  final double unitPrice;
  final String sku;
  final bool vatApplicable;
  final bool requiresPrescription;
  final bool isControlled;
  final DateTime? nearestExpiry;

  double get subtotal => round2(quantity * unitPrice);

  double tax(double vatRate) =>
      vatApplicable ? round2(subtotal * vatRate) : 0;

  double lineTotal(double vatRate) => round2(subtotal + tax(vatRate));

  CartLine copyWith({int? quantity, int? availableQty}) => CartLine(
        medicineId: medicineId,
        name: name,
        quantity: quantity ?? this.quantity,
        availableQty: availableQty ?? this.availableQty,
        unitPrice: unitPrice,
        sku: sku,
        vatApplicable: vatApplicable,
        requiresPrescription: requiresPrescription,
        isControlled: isControlled,
        nearestExpiry: nearestExpiry,
      );
}

class CartPayment {
  const CartPayment({
    required this.method,
    required this.amount,
    this.reference,
  });

  /// `cash`, `mobile_money`, `card` or `bank_transfer`.
  final String method;
  final double amount;
  final String? reference;

  Map<String, dynamic> toJson() => {
        'method': method,
        'amount': amount,
        if (reference != null && reference!.isNotEmpty) 'reference': reference,
      };
}

class Cart {
  const Cart({
    this.lines = const [],
    this.discount = 0,
    this.customerId,
    this.prescriptionId,
    this.note,
  });

  final List<CartLine> lines;
  final double discount;
  final String? customerId;
  final String? prescriptionId;
  final String? note;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  double subtotal(double vatRate) =>
      round2(lines.fold(0.0, (sum, line) => sum + line.subtotal));
  double tax(double vatRate) =>
      round2(lines.fold(0.0, (sum, line) => sum + line.tax(vatRate)));
  double total(double vatRate) =>
      round2(subtotal(vatRate) + tax(vatRate) - discount);

  /// True when at least one line needs a prescription to be dispensed.
  bool get needsPrescription => lines.any((line) => line.requiresPrescription);

  /// True when a line is present but the counted quantity exceeds stock.
  bool get hasOverQuantity =>
      lines.any((line) => line.quantity > line.availableQty || line.quantity < 1);

  int quantityOf(String medicineId) => lines
      .where((line) => line.medicineId == medicineId)
      .fold(0, (sum, line) => sum + line.quantity);

  Cart add(CartLine product) {
    if (product.availableQty < 1) return this;
    final existing = lines
        .where((line) => line.medicineId == product.medicineId)
        .firstOrNull;
    if (existing == null) {
      // Never add more than one unit of a prescription-only medicine without
      // the caller separately confirming the quantity in the UI.
      return copyWith(lines: [...lines, product.copyWith(quantity: 1)]);
    }
    return setQuantity(
      product.medicineId,
      existing.quantity + 1,
      availableQty: product.availableQty,
    );
  }

  Cart setQuantity(String medicineId, int quantity, {int? availableQty}) {
    final next = <CartLine>[];
    for (final line in lines) {
      if (line.medicineId != medicineId) {
        next.add(line);
        continue;
      }
      final capped = quantity.clamp(1, availableQty ?? line.availableQty);
      if (capped > 0) next.add(line.copyWith(quantity: capped));
    }
    return copyWith(lines: next);
  }

  Cart remove(String medicineId) => copyWith(
        lines: lines.where((line) => line.medicineId != medicineId).toList(),
      );

  Cart withDiscount(double value, double vatRate) => copyWith(
        discount: value < 0
            ? 0
            : value > subtotal(vatRate) ? subtotal(vatRate) : round2(value),
      );

  Cart copyWith({
    List<CartLine>? lines,
    double? discount,
    String? customerId,
    String? prescriptionId,
    String? note,
  }) =>
      Cart(
        lines: lines ?? this.lines,
        discount: discount ?? this.discount,
        customerId: customerId ?? this.customerId,
        prescriptionId: prescriptionId ?? this.prescriptionId,
        note: note ?? this.note,
      );

  Cart clear() => const Cart();

  Map<String, dynamic> toJson({double vatRate = 0.15}) => {
        'lines': [
          for (final line in lines)
            {
              'medicine_id': line.medicineId,
              'name': line.name,
              'quantity': line.quantity,
              'available_qty': line.availableQty,
              'unit_price': line.unitPrice,
              'sku': line.sku,
              'vat_applicable': line.vatApplicable,
              'requires_prescription': line.requiresPrescription,
              'is_controlled': line.isControlled,
            },
        ],
        'discount': discount,
        'customer_id': customerId,
        'prescription_id': prescriptionId,
        'note': note,
      };

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
        lines: [
          for (final raw in (json['lines'] as List? ?? const []))
            CartLine(
              medicineId: (raw as Map)['medicine_id'] as String? ?? '',
              name: raw['name'] as String? ?? '',
              quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
              availableQty: (raw['available_qty'] as num?)?.toInt() ?? 0,
              unitPrice: (raw['unit_price'] as num?)?.toDouble() ?? 0,
              sku: raw['sku'] as String? ?? '',
              vatApplicable: raw['vat_applicable'] as bool? ?? false,
              requiresPrescription: raw['requires_prescription'] as bool? ?? false,
              isControlled: raw['is_controlled'] as bool? ?? false,
            ),
        ],
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        customerId: json['customer_id'] as String?,
        prescriptionId: json['prescription_id'] as String?,
        note: json['note'] as String?,
      );
}

/// The database rejects a cashier discount above this percentage. Mirror the
/// rule in the UI so the cashier sees the limit before they tap Pay.
String? validateDiscount({
  required double discount,
  required double subtotal,
  required AppRole role,
  required double maxCashierDiscountPct,
}) {
  if (discount < 0) return 'Discount cannot be negative.';
  if (discount > subtotal) return 'Discount cannot exceed the subtotal.';
  if (role == AppRole.cashier && subtotal > 0) {
    final limit = round2(subtotal * maxCashierDiscountPct / 100);
    if (discount > limit) {
      final percent = maxCashierDiscountPct.toStringAsFixed(1);
      final cleanPercent = percent.endsWith('.0')
          ? percent.substring(0, percent.length - 2)
          : percent;
      return 'Discount is above your limit of $cleanPercent percent (ETB ${limit.toStringAsFixed(2)}).';
    }
  }
  return null;
}

double paidTotal(List<CartPayment> payments) =>
    round2(payments.fold(0.0, (sum, payment) => sum + payment.amount));

double changeDue({required double total, required List<CartPayment> payments}) {
  final difference = round2(paidTotal(payments) - total);
  return difference > 0 ? difference : 0;
}

/// Mirrors create_sale's payment checks so the dialog can show a clear error
/// before calling the RPC. The RPC remains the source of truth.
String? validatePayments({
  required double total,
  required List<CartPayment> payments,
}) {
  if (payments.isEmpty) return 'Add at least one payment.';
  if (payments.any((payment) => payment.amount <= 0)) {
    return 'Payment amounts must be greater than zero.';
  }
  final paid = paidTotal(payments);
  if (paid < total) return 'Payment is less than the total.';
  final hasCash = payments.any((payment) => payment.method == 'cash');
  if (paid > total && !hasCash) return 'Only cash payments can have change.';
  if (payments.any((payment) =>
      payment.method != 'cash' &&
      payment.method != 'mobile_money' &&
      payment.method != 'card' &&
      payment.method != 'bank_transfer')) {
    return 'Unknown payment method.';
  }
  return null;
}

/// Quick-cash buttons: exact amount, then the common ETB notes rounded up.
List<double> quickCashAmounts(double total) {
  final exact = (total * 100).roundToDouble() / 100;
  final nextHundred = ((total / 100).ceil() * 100).toDouble();
  return <double>{
    exact,
    nextHundred,
    nextHundred + 50,
    nextHundred + 100,
    nextHundred + 200,
  }.toList()..sort();
}
