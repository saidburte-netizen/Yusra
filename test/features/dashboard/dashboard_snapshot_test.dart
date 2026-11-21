import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_metrics.dart';

void main() {
  group('topMedicinesFrom', () {
    test('ranks by quantity and uses the joined medicine name', () {
      final rows = [
        {
          'medicine_id': 'a',
          'medicine_name': 'Fallback A',
          'quantity': 2,
          'medicines': [
            {'name': 'Paracetamol'},
          ],
        },
        {
          'medicine_id': 'b',
          'medicine_name': 'Fallback B',
          'quantity': 6,
        },
        {
          'medicine_id': 'a',
          'medicine_name': 'Fallback A',
          'quantity': 3,
          'medicines': {'name': 'Paracetamol'},
        },
      ];

      final ranked = dashboardTopMedicines(rows);
      expect(ranked.first, {'name': 'Fallback B', 'qty': 6});
      expect(ranked.last, {'name': 'Paracetamol', 'qty': 5});
    });

    test('caps the list at five and tolerates a null result', () {
      final rows = List.generate(
        8,
        (index) => {
          'medicine_id': 'm$index',
          'medicine_name': 'Medicine $index',
          'quantity': index + 1,
        },
      );
      expect(dashboardTopMedicines(rows), hasLength(5));
      expect(dashboardTopMedicines(null), isEmpty);
    });
  });

  group('grossProfitFrom', () {
    test('subtracts cost of goods from line totals', () {
      final profit = dashboardGrossProfit([
        {'line_total': 100, 'cost_price': 20, 'quantity': 2},
        {'line_total': '50.5', 'cost_price': '10', 'quantity': 3},
      ]);
      expect(profit, closeTo(80.5, 0.001));
    });

    test('returns null when the underlying query failed', () {
      expect(dashboardGrossProfit(null), isNull);
    });
  });

  test('isExpiredBatch reads boolean and text flags', () {
    expect(dashboardIsExpiredBatch({'is_expired': true}), isTrue);
    expect(dashboardIsExpiredBatch({'is_expired': 'true'}), isTrue);
    expect(dashboardIsExpiredBatch({'is_expired': false}), isFalse);
    expect(dashboardIsExpiredBatch({}), isFalse);
  });
}
