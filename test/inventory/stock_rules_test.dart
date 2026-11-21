import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/inventory/logic/stock_rules.dart';

void main() {
  group('reorder suggestions', () {
    test('reorder level times two minus available', () {
      expect(StockRules.suggestedOrder(20, 8), 32);
      expect(StockRules.suggestedOrder(10, 0), 20);
    });

    test('never suggests zero or a negative quantity', () {
      expect(StockRules.suggestedOrder(5, 30), 1);
      expect(StockRules.suggestedOrder(0, 0), 1);
    });
  });

  group('expiry colours', () {
    test('expired is danger and near expiry is warning', () {
      expect(StockRules.expiryTone(-1, alertDays: 90), ExpiryTone.danger);
      expect(StockRules.expiryTone(29, alertDays: 90), ExpiryTone.warning);
    });

    test('configured alert window is gold, beyond it is neutral', () {
      expect(StockRules.expiryTone(60, alertDays: 90), ExpiryTone.gold);
      expect(StockRules.expiryTone(120, alertDays: 90), ExpiryTone.ok);
    });
  });

  group('stock status', () {
    StockStatus status(int available, int expired, int days) =>
        StockRules.status(
          available: available,
          expiredQty: expired,
          reorderLevel: 10,
          daysToNearestExpiry: days,
          alertDays: 90,
        );

    test('expired stock wins over every other status', () {
      expect(status(50, 1, 200), StockStatus.expired);
    });

    test('out of stock, low, expiring and healthy', () {
      expect(status(0, 0, 200), StockStatus.outOfStock);
      expect(status(8, 0, 200), StockStatus.low);
      expect(status(40, 0, 60), StockStatus.expiringSoon);
      expect(status(40, 0, 200), StockStatus.inStock);
    });
  });

  group('stock take variance', () {
    test('counted minus system quantity', () {
      expect(StockRules.variance(counted: 18, systemQty: 20), -2);
      expect(StockRules.adjustmentFor(counted: 25, systemQty: 20), 5);
      expect(StockRules.variance(counted: 20, systemQty: 20), 0);
    });
  });
}
