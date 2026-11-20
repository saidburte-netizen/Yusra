import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/money.dart';

void main() {
  group('money formatting', () {
    test('ETB prefix with two decimals and grouping', () {
      expect(formatMoney(1234.5), 'ETB 1,234.50');
      expect(formatMoney(0), 'ETB 0.00');
      expect(formatMoney(1234567.891), 'ETB 1,234,567.89');
    });

    test('whole variant drops the decimals', () {
      expect(formatMoneyWhole(1234), 'ETB 1,234');
      expect(formatNumber(1234.5), '1,234.50');
    });

    test('negative amounts keep their sign', () {
      expect(formatMoney(-42.25), 'ETB -42.25');
    });
  });

  group('money parsing', () {
    test('accepts grouping, an ETB prefix and whitespace', () {
      expect(parseMoney('ETB 1,234.50'), 1234.5);
      expect(parseMoney('  1,000  '), 1000);
      expect(parseMoney('250'), 250);
    });

    test('rejects empty or non-numeric input', () {
      expect(parseMoney(''), isNull);
      expect(parseMoney('ETB'), isNull);
      expect(parseMoney('not a number'), isNull);
    });
  });

  test('VAT is removed from a gross amount using a fractional rate', () {
    expect(moneyExcludingVat(1150, 0.15), closeTo(1000, 0.001));
  });
}
