import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/prescriptions/data/prescription_model.dart';
import 'package:yusra_pharmacy/features/prescriptions/data/prescription_paths.dart';

void main() {
  group('prescriptionImagePath', () {
    test('scopes uploads by branch and generated id', () {
      final path = prescriptionImagePath(
        branchId: 'branch-1',
        prescriptionId: 'rx-42',
        fileName: 'scan.jpg',
      );

      expect(path, startsWith('branch-1/rx-42/'));
      expect(path, endsWith('.jpg'));
    });

    test('sanitises unsafe extensions and falls back to .img', () {
      final weird = prescriptionImagePath(
        branchId: 'b',
        prescriptionId: 'id',
        fileName: 'photo.JPEG?token=1',
      );
      final none = prescriptionImagePath(
        branchId: 'b',
        prescriptionId: 'id',
        fileName: 'no-extension',
      );

      expect(weird, endsWith('.jpeg'));
      expect(none, endsWith('.img'));
      expect(weird, isNot(contains('?')));
    });
  });

  group('Prescription.fromJson', () {
    test('parses age, status and attached sale', () {
      final rx = Prescription.fromJson({
        'id': 'rx-1',
        'rx_no': 'RX-1',
        'branch_id': 'b',
        'patient_name': 'Test Patient',
        'patient_age': '32',
        'prescriber_name': 'Dr Test',
        'status': 'dispensed',
        'image_path': 'b/rx-1/scan.jpg',
        'sales': [
          {'id': 'sale-9'},
        ],
      });

      expect(rx.patientAge, 32);
      expect(rx.status, 'dispensed');
      expect(rx.imagePath, 'b/rx-1/scan.jpg');
      expect(rx.saleId, 'sale-9');
    });

    test('defaults missing fields without throwing', () {
      final rx = Prescription.fromJson({'id': 'rx-2'});
      expect(rx.status, 'pending');
      expect(rx.patientName, '');
      expect(rx.saleId, isNull);
    });
  });
}
