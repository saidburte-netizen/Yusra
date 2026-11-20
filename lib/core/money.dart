import 'package:intl/intl.dart';

final NumberFormat _moneyFormatter = NumberFormat('#,##0.00', 'en_US');
final NumberFormat _wholeFormatter = NumberFormat('#,##0', 'en_US');

/// ETB 1,234.50 — the one canonical money format used across the app.
String formatMoney(num amount) => 'ETB ${_moneyFormatter.format(amount)}';

/// ETB 1,234 — used where whole units are implied (stock counts, invoices).
String formatMoneyWhole(num amount) => 'ETB ${_wholeFormatter.format(amount)}';

/// Plain grouped number without the currency prefix.
String formatNumber(num amount) => _moneyFormatter.format(amount);

/// Parses user input, accepting grouping commas and an optional ETB prefix.
double? parseMoney(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'ETB', caseSensitive: false), '')
      .replaceAll(',', '')
      .trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Amount excluding VAT from a VAT-inclusive total (prices exclude VAT by
/// default, so this is only used when an external document quotes a gross
/// amount). [vatRate] is a fraction, matching the app's `vat_rate` setting:
/// pass 0.15 for 15%, not 15.
double moneyExcludingVat(double gross, double vatRate) => gross / (1 + vatRate);
