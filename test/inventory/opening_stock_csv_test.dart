import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_models.dart';
import 'package:yusra_pharmacy/features/inventory/logic/opening_stock_csv.dart';

void main() {
  test('template has the documented headers and parses as one valid row', () {
    expect(
      OpeningStockCsv.template.split('\n').first,
      OpeningStockCsv.headers.join(','),
    );
    expect(OpeningStockCsv.headers, [
      'medicine_name',
      'sku',
      'barcode',
      'quantity',
      'expiry_date',
      'batch_no',
      'unit_cost',
    ]);

    final result = OpeningStockCsv.parse(OpeningStockCsv.template);
    expect(result.isValid, isTrue, reason: result.errors.toString());
    expect(result.totalRows, 1);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.medicineName, 'Paracetamol 500mg');
    expect(result.rows.single.sku, 'PAR-500');
    expect(result.rows.single.quantity, 120);
    expect(result.rows.single.expiryDate, DateTime(2030, 12, 31));
    expect(result.rows.single.batchNo, isEmpty);
    expect(result.rows.single.unitCost, 8);
  });

  test('parses valid rows with optional batch and cost left blank', () {
    final csv = '${OpeningStockCsv.headers.join(',')}\n'
        'Amoxicillin 500mg,AMX-500,BC-1,12,2031-06-30,,\n';
    final result = OpeningStockCsv.parse(csv);

    expect(result.isValid, isTrue, reason: result.errors.toString());
    expect(result.rows, hasLength(1));
    final row = result.rows.single;
    expect(row.medicineName, 'Amoxicillin 500mg');
    expect(row.barcode, 'BC-1');
    expect(row.quantity, 12);
    expect(row.batchNo, isEmpty);
    expect(row.unitCost, 0);
  });

  test('reports invalid rows with their CSV line number', () {
    final csv = '${OpeningStockCsv.headers.join(',')}\n'
        ',AMX-500,,12,2031-06-30,,2.50\n'
        'Amoxicillin 500mg,AMX-500,,0,2031-06-30,,2.50\n'
        'Amoxicillin 500mg,AMX-500,,4,2031-06-30,,-1\n';
    final result = OpeningStockCsv.parse(csv);

    expect(result.rows, isEmpty);
    expect(result.totalRows, 3);
    expect(result.errors.keys.toSet(), {2, 3, 4});
    expect(result.errors[2], contains('medicine_name is required'));
    expect(result.errors[3], contains('quantity'));
    expect(result.errors[4], contains('unit_cost'));
  });

  test('requires a valid expiry date in the future', () {
    final yesterday =
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    final csv = '${OpeningStockCsv.headers.join(',')}\n'
        'Expired item,EXP-1,,5,$yesterday,,0\n'
        'Invalid item,INV-1,,5,not-a-date,,0\n'
        'Blank item,BLK-1,,5,,,0\n'
        'Future item,FUT-1,,5,2099-12-31,,0\n';
    final result = OpeningStockCsv.parse(csv);

    expect(result.rows, hasLength(1));
    expect(result.rows.single.medicineName, 'Future item');
    expect(result.errors.keys.toSet(), {2, 3, 4});
    expect(result.errors[2], contains('expiry_date must be in the future'));
    expect(result.errors[3], contains('expiry_date must be a valid'));
    expect(result.errors[4], contains('expiry_date is required'));
  });

  test('rejects empty files and missing required columns', () {
    final empty = OpeningStockCsv.parse('');
    expect(empty.isValid, isFalse);
    expect(empty.errors[1], contains('empty'));

    final missing =
        OpeningStockCsv.parse('medicine_name,quantity\nParacetamol,10\n');
    expect(missing.errors[1], contains('expiry_date'));
  });

  test('resolves medicines by SKU, barcode and name and reports misses', () {
    final medicines = [
      const Medicine(id: 'med-1', name: 'Amoxicillin 500mg', sku: 'AMX-500'),
      const Medicine(
        id: 'med-2',
        name: 'Paracetamol 500mg',
        sku: 'PAR-500',
        barcode: 'BC-PAR',
      ),
    ];
    final rows = [
      const OpeningStockCsvRow(
        medicineName: 'wrong name',
        sku: 'amx-500',
        quantity: 1,
      ),
      const OpeningStockCsvRow(
        medicineName: 'wrong name',
        barcode: 'bc-par',
        quantity: 2,
      ),
      const OpeningStockCsvRow(
        medicineName: 'paracetamol 500mg',
        quantity: 3,
      ),
      const OpeningStockCsvRow(
        medicineName: 'Unknown item',
        sku: 'NOPE',
        quantity: 4,
      ),
    ];

    final resolved = resolveOpeningStockMedicines(rows, medicines);
    expect(resolved.rows.map((match) => match.medicine.id), [
      'med-1',
      'med-2',
      'med-2',
    ]);
    expect(resolved.errors, hasLength(1));
    expect(resolved.errors[3], contains('Unknown item'));
    expect(resolved.errors[3], contains('not found'));
    expect(resolved.isValid, isFalse);

    final viaAlias = OpeningStockCsv.resolve(rows, medicines);
    expect(viaAlias.rows, hasLength(3));
  });
}
