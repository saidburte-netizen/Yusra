import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/nav/app_shell.dart';

void main() {
  final branches = [
    {'id': 'br-1', 'name': 'Main'},
    {'id': 'br-2', 'name': 'East'},
  ];

  test('super admin with no branch defaults to their own branch', () {
    expect(
      initialBranchId(branches,
          ownBranchId: 'br-2', touched: false, selected: null),
      'br-2',
    );
  });

  test('otherwise the first active branch is used', () {
    expect(
      initialBranchId(branches,
          ownBranchId: null, touched: false, selected: null),
      'br-1',
    );
  });

  test('an inactive own branch is not used', () {
    expect(
      initialBranchId(branches,
          ownBranchId: 'br-deleted', touched: false, selected: null),
      'br-1',
    );
  });

  test('an explicit choice, including All branches, is never overwritten', () {
    expect(
      initialBranchId(branches,
          ownBranchId: null, touched: true, selected: null),
      isNull,
    );
    expect(
      initialBranchId(branches,
          ownBranchId: null, touched: false, selected: 'br-2'),
      isNull,
    );
  });

  test('no branches means no fallback', () {
    expect(
      initialBranchId(const [],
          ownBranchId: null, touched: false, selected: null),
      isNull,
    );
  });
}
