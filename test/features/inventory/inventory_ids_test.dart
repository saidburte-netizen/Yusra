import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_ids.dart';

void main() {
  test('generates RFC 4122 version 4 UUIDs', () {
    final id = generateUuidV4();
    final parts = id.split('-');

    expect(parts, hasLength(5));
    expect(parts.map((part) => part.length), [8, 4, 4, 4, 12]);
    expect(parts[2][0], '4', reason: 'version nibble must be 4');
    expect('89ab'.contains(parts[3][0]), isTrue,
        reason: 'variant nibble must be 8, 9, a or b');
    expect(RegExp(r'^[0-9a-f-]+$').hasMatch(id), isTrue);
  });

  test('generates a different id each time', () {
    final ids = List.generate(25, (_) => generateUuidV4());
    expect(ids.toSet(), hasLength(ids.length));
  });
}
