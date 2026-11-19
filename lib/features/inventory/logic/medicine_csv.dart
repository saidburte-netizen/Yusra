import 'package:csv/csv.dart';

/// A validated row from the medicine CSV import (B1). Import never writes to
/// the database: the caller previews errors and then inserts valid rows.
class MedicineCsvRow {
  const MedicineCsvRow({
    required this.name,
    required this.genericName,
    required this.barcode,
    required this.categoryName,
    required this.dosageForm,
    required this.strength,
    required this.unit,
    required this.manufacturer,
    required this.costPrice,
    required this.sellingPrice,
    required this.vatApplicable,
    required this.requiresPrescription,
    required this.isControlled,
    required this.reorderLevel,
    required this.storageNotes,
  });

  final String name;
  final String genericName;
  final String barcode;
  final String categoryName;
  final String dosageForm;
  final String strength;
  final String unit;
  final String manufacturer;
  final double costPrice;
  final double sellingPrice;
  final bool vatApplicable;
  final bool requiresPrescription;
  final bool isControlled;
  final int reorderLevel;
  final String storageNotes;

  Map<String, dynamic> toJson({String? categoryId}) => {
        'name': name,
        'generic_name': genericName.isEmpty ? null : genericName,
        'barcode': barcode.isEmpty ? null : barcode,
        if (categoryId != null) 'category_id': categoryId,
        'dosage_form': dosageForm.isEmpty ? null : dosageForm,
        'strength': strength.isEmpty ? null : strength,
        'unit': unit.isEmpty ? 'Pack' : unit,
        'manufacturer': manufacturer.isEmpty ? null : manufacturer,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'vat_applicable': vatApplicable,
        'requires_prescription': requiresPrescription,
        'is_controlled': isControlled,
        'reorder_level': reorderLevel,
        'storage_notes': storageNotes.isEmpty ? null : storageNotes,
      };
}

class MedicineCsvResult {
  const MedicineCsvResult({
    required this.rows,
    required this.errors,
    required this.totalRows,
  });

  final List<MedicineCsvRow> rows;
  final Map<int, String> errors;
  final int totalRows;

  bool get isValid => errors.isEmpty;
}

abstract final class MedicineCsv {
  // The csv package defaults to CRLF; uploaded files usually use LF.
  static final CsvCodec codec = CsvCodec(eol: '\n');

  static const List<String> headers = [
    'name',
    'generic_name',
    'barcode',
    'category',
    'dosage_form',
    'strength',
    'unit',
    'manufacturer',
    'cost_price',
    'selling_price',
    'vat_applicable',
    'requires_prescription',
    'is_controlled',
    'reorder_level',
    'storage_notes',
  ];

  static String get template =>
      '${codec.encoder.convert([headers])}\n'
      'Paracetamol 500mg,Paracetamol,,Pain and fever,Tablet,500mg,Pack,Yusra,28.00,40.00,no,no,no,20,Store below 30C';

  static MedicineCsvResult parse(String source) {
    final errors = <int, String>{};
    final rows = <MedicineCsvRow>[];
    final table = codec.decoder.convert(source.replaceAll('\r\n', '\n'));
    if (table.isEmpty) {
      return MedicineCsvResult(rows: rows, errors: {1: 'The file is empty.'}, totalRows: 0);
    }

    final header = table.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    final missing = <String>[];
    for (final required in ['name', 'cost_price', 'selling_price']) {
      if (!header.contains(required)) missing.add(required);
    }
    if (missing.isEmpty) {
      final index = <String, int>{for (var i = 0; i < header.length; i++) header[i]: i};
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
        final name = cell('name');
        if (name.isEmpty) rowErrors.add('name is required');
        final cost = double.tryParse(cell('cost_price').replaceAll(',', ''));
        final selling = double.tryParse(cell('selling_price').replaceAll(',', ''));
        if (cost == null || cost < 0) rowErrors.add('cost_price must be a positive number');
        if (selling == null || selling < 0) rowErrors.add('selling_price must be a positive number');
        final reorder = int.tryParse(cell('reorder_level'));
        if (cell('reorder_level').isNotEmpty && (reorder == null || reorder < 0)) {
          rowErrors.add('reorder_level must be a whole number');
        }
        bool? boolFlag(String key) => switch (cell(key).toLowerCase()) {
              'yes' || 'true' || '1' || 'y' => true,
              '' || 'no' || 'false' || '0' || 'n' => false,
              _ => null,
            };
        for (final key in ['vat_applicable', 'requires_prescription', 'is_controlled']) {
          if (boolFlag(key) == null) rowErrors.add('$key must be yes or no');
        }

        if (rowErrors.isNotEmpty) {
          errors[i + 1] = rowErrors.join('; ');
          continue;
        }
        rows.add(MedicineCsvRow(
          name: name,
          genericName: cell('generic_name'),
          barcode: cell('barcode'),
          categoryName: cell('category'),
          dosageForm: cell('dosage_form'),
          strength: cell('strength'),
          unit: cell('unit'),
          manufacturer: cell('manufacturer'),
          costPrice: cost!,
          sellingPrice: selling!,
          vatApplicable: boolFlag('vat_applicable')!,
          requiresPrescription: boolFlag('requires_prescription')!,
          isControlled: boolFlag('is_controlled')!,
          reorderLevel: reorder ?? 10,
          storageNotes: cell('storage_notes'),
        ));
      }
    } else {
      errors[1] = 'Missing columns: ${missing.join(', ')}';
    }
    return MedicineCsvResult(
      rows: rows,
      errors: errors,
      totalRows: table.length - 1,
    );
  }
}
