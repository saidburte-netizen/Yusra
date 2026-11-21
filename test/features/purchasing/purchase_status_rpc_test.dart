import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/purchasing/data/purchase_status_helpers.dart';

void main() {
  test('approve uses the generic RPC then the legacy fallback', () {
    expect(
      purchaseStatusRpcCandidates('ordered'),
      ['set_purchase_order_status', 'approve_purchase_order'],
    );
  });

  test('cancel uses the generic RPC then the legacy fallback', () {
    expect(
      purchaseStatusRpcCandidates('cancelled'),
      ['set_purchase_order_status', 'cancel_purchase_order'],
    );
  });

  test('other statuses only try the generic RPC', () {
    expect(purchaseStatusRpcCandidates('draft'), ['set_purchase_order_status']);
    expect(purchaseStatusRpcCandidates(''), ['set_purchase_order_status']);
  });
}
