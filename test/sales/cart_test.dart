import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/sales/logic/cart.dart';

CartLine line({
  String id = 'm1',
  int quantity = 1,
  int available = 10,
  double price = 10,
  bool vat = false,
  bool rx = false,
}) =>
    CartLine(
      medicineId: id,
      name: 'Medicine $id',
      quantity: quantity,
      availableQty: available,
      unitPrice: price,
      vatApplicable: vat,
      requiresPrescription: rx,
    );

void main() {
  group('cart totals', () {
    test('prices exclude VAT and VAT applies only to flagged lines', () {
      final cart = Cart(lines: [
        line(id: 'a', quantity: 2, price: 10, vat: true),
        line(id: 'b', quantity: 1, price: 5, vat: false),
      ]);
      expect(cart.subtotal(0.15), 25);
      expect(cart.tax(0.15), 3);
      expect(cart.total(0.15), 28);
    });

    test('discount is subtracted from the total and capped at the subtotal',
        () {
      final cart = Cart(lines: [line(quantity: 2, price: 10)]);
      expect(cart.withDiscount(5, 0.15).total(0.15), 15);
      expect(cart.withDiscount(999, 0.15).discount, 20);
      expect(cart.withDiscount(-4, 0.15).discount, 0);
    });

    test('quantity stepper never exceeds available stock', () {
      final cart = Cart(lines: [line(available: 2)]);
      expect(cart.setQuantity('m1', 9).lines.single.quantity, 2);
      expect(cart.setQuantity('m1', 0).lines.single.quantity, 1);
      expect(cart.hasOverQuantity, isFalse);
    });

    test('adding an existing product increments its quantity', () {
      final cart = Cart(lines: [line(quantity: 1, available: 3)]);
      final added = cart.add(line(quantity: 1, available: 3));
      expect(added.lines, hasLength(1));
      expect(added.lines.single.quantity, 2);
      expect(added.add(line(available: 3)).lines.single.quantity, 3);
    });

    test('out of stock products are not added', () {
      expect(const Cart().add(line(available: 0)).isEmpty, isTrue);
    });
  });

  group('discount rules', () {
    test('cashier above the configured percent gets a readable message', () {
      final message = validateDiscount(
        discount: 11,
        subtotal: 100,
        role: AppRole.cashier,
        maxCashierDiscountPct: 5,
      );
      expect(message, contains('above your limit of 5 percent'));
      expect(message, contains('ETB 5.00'));
    });

    test('pharmacist can grant the same discount', () {
      expect(
        validateDiscount(
          discount: 11,
          subtotal: 100,
          role: AppRole.pharmacist,
          maxCashierDiscountPct: 5,
        ),
        isNull,
      );
    });

    test('negative and over-subtotal discounts are rejected for everyone', () {
      expect(
        validateDiscount(
            discount: -1,
            subtotal: 100,
            role: AppRole.admin,
            maxCashierDiscountPct: 5),
        isNotNull,
      );
      expect(
        validateDiscount(
            discount: 101,
            subtotal: 100,
            role: AppRole.admin,
            maxCashierDiscountPct: 5),
        isNotNull,
      );
    });
  });

  group('payments and change', () {
    test('change is cash paid minus total, never negative', () {
      final payments = [
        const CartPayment(method: 'cash', amount: 50),
        const CartPayment(method: 'card', amount: 2),
      ];
      expect(paidTotal(payments), 52);
      expect(changeDue(total: 48, payments: payments), 4);
      expect(changeDue(total: 60, payments: payments), 0);
    });

    test('only cash can produce change', () {
      expect(
        validatePayments(
          total: 40,
          payments: const [CartPayment(method: 'card', amount: 50)],
        ),
        contains('Only cash payments can have change'),
      );
    });

    test('short payment is rejected before calling the RPC', () {
      expect(
        validatePayments(
          total: 50,
          payments: const [CartPayment(method: 'cash', amount: 49)],
        ),
        contains('less than the total'),
      );
    });

    test('quick cash buttons include the exact amount', () {
      expect(quickCashAmounts(37.4).first, 37.4);
      expect(quickCashAmounts(37.4).contains(100.0), isTrue);
    });
  });

  group('held carts', () {
    test('JSON round trip preserves lines, discount and rx selection', () {
      final cart = Cart(
        lines: [line(id: 'rx1', quantity: 2, price: 12.5, vat: true, rx: true)],
        discount: 3,
        customerId: 'c1',
        prescriptionId: 'p1',
      );
      final restored = Cart.fromJson(cart.toJson());
      expect(restored.lines.single.medicineId, 'rx1');
      expect(restored.lines.single.requiresPrescription, isTrue);
      expect(restored.discount, 3);
      expect(restored.prescriptionId, 'p1');
      expect(restored.total(0.15), cart.total(0.15));
    });

    test('a cart containing an Rx line is flagged', () {
      expect(Cart(lines: [line(rx: true)]).needsPrescription, isTrue);
      expect(Cart(lines: [line()]).needsPrescription, isFalse);
    });
  });
}
