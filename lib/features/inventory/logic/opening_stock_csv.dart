import 'package:csv/csv.dart';

import '../data/inventory_models.dart';

/// One validated row of an opening-stock CSV upload. Import never writes to
/// the database: the caller previews the rows and saves them in one RPC call.
class OpeningStockCsvRow {
  const OpeningStockCsvRow({
    required this.medicineName,
    this.sku = '',
    this.barcode = '',
    required this.quantity,
    this.expiryDate,
    this.batchNo = '',
    this.unitCost = 0,
  });

  final String medicineName;
  final String sku;
  final String barcode;
  final int quantity;
  final DateTime? expiryDate;
  final String batchNo;
  final double unitCost;
}

class OpeningStockCsvResult {
  const OpeningStockCsvResult({
    required this.rows,
    required this.errors,
    required this.totalRows,
  });

  final List<OpeningStockCsvRow> rows;
  final Map<int, String> errors;
  final int totalRows;

  bool get isValid => errors.isEmpty;
}

/// A parsed row paired with the catalogue medicine it refers to.
class OpeningStockCsvMatch {
  const OpeningStockCsvMatch({required this.row, required this.medicine});

  final OpeningStockCsvRow row;
  final Medicine medicine;
}

class OpeningStockCsvResolution {
  const OpeningStockCsvResolution({
    required this.rows,
    required this.errors,
  });

  final List<OpeningStockCsvMatch> rows;
  final Map<int, String> errors;

  bool get isValid => errors.isEmpty;
}

/// Maps parsed CSV rows onto catalogue medicines by name, SKU or barcode.
///
/// Errors are keyed by the parsed row's index so a preview can show exactly
/// which lines need a different name/code or a newly registered medicine.
OpeningStockCsvResolution resolveOpeningStockMedicines(
  List<OpeningStockCsvRow> rows,
  List<Medicine> medicines,
) {
  final byName = <String, Medicine>{};
  final bySku = <String, Medicine>{};
  final byBarcode = <String, Medicine>{};
  String key(String? value) => (value ?? '').trim().toLowerCase();
  for (final medicine in medicines) {
    final name = key(medicine.name);
    if (name.isNotEmpty) byName.putIfAbsent(name, () => medicine);
    final sku = key(medicine.sku);
    if (sku.isNotEmpty) bySku.putIfAbsent(sku, () => medicine);
    final barcode = key(medicine.barcode);
    if (barcode.isNotEmpty) byBarcode.putIfAbsent(barcode, () => medicine);
  }

  final matches = <OpeningStockCsvMatch>[];
  final errors = <int, String>{};
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    final medicine = bySku[key(row.sku)] ??
        byBarcode[key(row.barcode)] ??
        byName[key(row.medicineName)];
    if (medicine == null) {
      errors[index] = 'Medicine "${row.medicineName}" was not found in the '
          'catalogue. Check the name, SKU or barcode.';
      continue;
    }
    matches.add(OpeningStockCsvMatch(row: row, medicine: medicine));
  }
  return OpeningStockCsvResolution(rows: matches, errors: errors);
}

abstract final class OpeningStockCsv {
  // Uploaded files usually use LF; the csv package defaults to CRLF.
  static final CsvCodec codec = CsvCodec(eol: '\n');

  static const List<String> headers = [
    'medicine_name',
    'sku',
    'barcode',
    'quantity',
    'expiry_date',
    'batch_no',
    'unit_cost',
  ];

  static String get template => '${codec.encoder.convert([headers])}\n'
      'Paracetamol 500mg,PAR-500,,120,2030-12-31,,8.00';

  static OpeningStockCsvResult parse(String source) {
    final errors = <int, String>{};
    final rows = <OpeningStockCsvRow>[];
    final table = codec.decoder
        .convert(source.replaceAll('\r\n', '\n').replaceFirst('\uFEFF', ''));
    if (table.isEmpty) {
      return OpeningStockCsvResult(
        rows: rows,
        errors: {1: 'The file is empty.'},
        totalRows: 0,
      );
    }

    final header = table.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    final missing = <String>[];
    for (final required in ['medicine_name', 'quantity', 'expiry_date']) {
      if (!header.contains(required)) missing.add(required);
    }
    if (missing.isNotEmpty) {
      return OpeningStockCsvResult(
        rows: rows,
        errors: {1: 'Missing columns: ${missing.join(', ')}'},
        totalRows: table.length - 1,
      );
    }

    final index = <String, int>{
      for (var i = 0; i < header.length; i++) header[i]: i
    };
    for (var i = 1; i < table.length; i++) {
      final cells = table[i];
      if (cells.every((cell) => cell.toString().trim().isEmpty)) continue;
      String cell(String key) {
        final at = index[key];
        return at == null || at >= cells.length
            ? ''
            : cells[at].toString().trim();
      }

      final rowErrors = <String>[];
      final name = cell('medicine_name');
      if (name.isEmpty) rowErrors.add('medicine_name is required');

      final quantity = int.tryParse(cell('quantity'));
      if (quantity == null || quantity <= 0) {
        rowErrors.add('quantity must be a whole number above zero');
      }

      DateTime? expiry;
      final expiryText = cell('expiry_date');
      if (expiryText.isEmpty) {
        rowErrors.add('expiry_date is required');
      } else {
        expiry = DateTime.tryParse(expiryText);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (expiry == null) {
          rowErrors.add('expiry_date must be a valid YYYY-MM-DD date');
        } else {
          final day = DateTime(expiry.year, expiry.month, expiry.day);
          if (!day.isAfter(today)) {
            rowErrors.add('expiry_date must be in the future');
          }
        }
      }

      final costText = cell('unit_cost').replaceAll(',', '');
      final cost = costText.isEmpty ? 0.0 : double.tryParse(costText);
      if (cost == null || cost < 0) {
        rowErrors.add('unit_cost must be zero or more');
      }

      if (rowErrors.isNotEmpty) {
        // +1 because the first CSV line is the header.
        errors[i + 1] = rowErrors.join('; ');
        continue;
      }

      rows.add(OpeningStockCsvRow(
        medicineName: name,
        sku: cell('sku'),
        barcode: cell('barcode'),
        quantity: quantity!,
        expiryDate: expiry,
        batchNo: cell('batch_no'),
        unitCost: cost ?? 0,
      ));
    }

    return OpeningStockCsvResult(
      rows: rows,
      errors: errors,
      totalRows: table.length - 1,
    );
  }

  /// Alias for [resolveOpeningStockMedicines] for callers that prefer the
  /// parser namespace.
  static OpeningStockCsvResolution resolve(
    List<OpeningStockCsvRow> rows,
    List<Medicine> medicines,
  ) =>
      resolveOpeningStockMedicines(rows, medicines);
}
