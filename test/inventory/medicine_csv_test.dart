import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/inventory/logic/medicine_csv.dart';

void main() {
  test('template parses into a valid row', () {
    final result = MedicineCsv.parse(MedicineCsv.template);
    expect(result.isValid, isTrue, reason: result.errors.toString());
    expect(result.rows, hasLength(1));
    expect(result.rows.single.name, 'Paracetamol 500mg');
    expect(result.rows.single.costPrice, 28);
    expect(result.rows.single.sellingPrice, 40);
    expect(result.rows.single.reorderLevel, 20);
  });

  test('reports missing required columns', () {
    final result =
        MedicineCsv.parse('name,category\nParacetamol,Pain and fever\n');
    expect(result.isValid, isFalse);
    expect(result.errors[1], contains('cost_price'));
  });

  test('flags invalid numeric and boolean cells row by row', () {
    final csv = '${MedicineCsv.headers.join(',')}\n'
        'Good,Generic,,Pain and fever,Tablet,500mg,Pack,Yusra,10,20,yes,no,no,5,\n'
        'Bad,Generic,,Pain and fever,Tablet,500mg,Pack,Yusra,abc,-1,maybe,no,no,5,\n';
    final result = MedicineCsv.parse(csv);
    expect(result.rows, hasLength(1));
    expect(result.errors[3], contains('cost_price'));
    expect(result.errors[3], contains('selling_price'));
    expect(result.errors[3], contains('vat_applicable'));
  });

  test('skips blank lines and maps booleans', () {
    final csv = '${MedicineCsv.headers.join(',')}\n\n'
        'Rx item,,,Diabetes,Tablet,5mg,Pack,Yusra,1,2,TRUE,1,yes,,\n';
    final result = MedicineCsv.parse(csv);
    expect(result.isValid, isTrue, reason: result.errors.toString());
    expect(result.rows.single.vatApplicable, isTrue);
    expect(result.rows.single.requiresPrescription, isTrue);
    expect(result.rows.single.isControlled, isTrue);
    expect(result.rows.single.reorderLevel, 10);
  });
}
