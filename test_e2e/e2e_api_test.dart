// End-to-end API suite: real repositories -> SupabaseClient -> PostgREST ->
// PostgreSQL 16. The only SQL in this file's world is schema setup and user
// creation (auth.users is not in the public API schema).
//
// Every request is wrapped in `api()` so a PostgREST error fails the test with
// its code and message printed, including the PGRST200/201/204 embed errors.

@Tags(['e2e-api'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yusra_pharmacy/core/dates.dart';
import 'package:yusra_pharmacy/core/supabase_client.dart';
import 'package:yusra_pharmacy/features/customers/data/customers.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_metrics.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_repository.dart';
import 'package:yusra_pharmacy/features/prescriptions/data/prescriptions.dart';
import 'package:yusra_pharmacy/features/purchasing/data/purchasing.dart';
import 'package:yusra_pharmacy/features/reports/data/reports.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';
import 'package:yusra_pharmacy/features/suppliers/data/suppliers.dart';

import 'support/harness.dart';

String _dateIn(int days) {
  final date = DateTime.now().toUtc().add(Duration(days: days));
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

void main() {
  E2eEnv.init();

  setUpAll(() async {
    await PostgrestProxy.start();
    final http = HttpClient();
    try {
      final request = await http.getUrl(Uri.parse('${E2eEnv.postgrestUrl}/'));
      final response = await request.close();
      expect(response.statusCode, 200,
          reason: 'PostgREST must be reachable at ${E2eEnv.postgrestUrl}/');
      await response.drain<void>();
    } finally {
      http.close();
    }
  });

  tearDownAll(() async {
    SupabaseService.clearE2eClient();
    await PostgrestProxy.stop();
  });

  group('e2e-api', () {
    test('golden pharmacy flow, reports, dashboard and role rules', () async {
      final runId = E2eEnv.runId;

      // --- Admin identity and branch -------------------------------------
      final adminId = await createUserViaSql(
          role: 'super_admin', branchId: '', label: 'admin');
      useUser(adminId);
      final admin = SupabaseService.client;
      final adminRole =
          await api('admin role', () => admin.rpc<String>('my_role'));
      stdout.writeln('[e2e] admin role=$adminRole');
      expect(adminRole, 'super_admin',
          reason: 'the seeded owner must resolve as super_admin via PostgREST');

      final branchRow = await api(
          'create branch',
          () => admin
              .from('branches')
              .insert({
                'name': 'E2E Branch $runId',
                'code': 'E2E$runId',
                'address': 'E2E test address',
              })
              .select('id')
              .single());
      final branchId = branchRow['id'] as String;

      final cashierId = await createUserViaSql(
          role: 'cashier', branchId: branchId, label: 'cashier');
      final storeKeeperId = await createUserViaSql(
          role: 'store_keeper', branchId: branchId, label: 'storekeeper');

      // --- Category, supplier and catalogue ------------------------------
      stdout.writeln('[e2e] branch -> category -> supplier -> medicines');
      final inventory = InventoryRepository();
      final categoryName = 'E2E Category $runId';
      await api('save category',
          () => inventory.saveCategory({'name': categoryName}));
      final category = (await api('categories', () => inventory.categories()))
          .firstWhere((item) => item.name == categoryName);

      final supplierName = 'E2E Supplier $runId';
      final suppliers = SupplierRepository();
      await api(
          'save supplier',
          () =>
              suppliers.save({'name': supplierName, 'contact_person': 'E2E'}));
      final supplierId =
          (await api('suppliers', () => suppliers.list(query: supplierName)))
              .firstWhere((item) => item.name == supplierName)
              .id;

      final normalSku = 'E2EN$runId';
      final rxSku = 'E2ER$runId';
      final normalBarcode = 'BCN$runId';
      await api(
          'save normal medicine',
          () => inventory.saveMedicine({
                'name': 'E2E Normal $runId',
                'sku': normalSku,
                'barcode': normalBarcode,
                'category_id': category.id,
                'cost_price': 6.0,
                'selling_price': 10.0,
                'unit': 'Tablet',
                'reorder_level': 2,
                'vat_applicable': false,
              }));
      await api(
          'save Rx medicine',
          () => inventory.saveMedicine({
                'name': 'E2E Rx $runId',
                'sku': rxSku,
                'barcode': 'BCR$runId',
                'category_id': category.id,
                'cost_price': 12.0,
                'selling_price': 20.0,
                'unit': 'Tablet',
                'requires_prescription': true,
                'is_controlled': true,
                'vat_applicable': false,
              }));
      final normal = (await api(
              'normal medicine', () => inventory.medicines(query: normalSku)))
          .single;
      final rxMedicine =
          (await api('Rx medicine', () => inventory.medicines(query: rxSku)))
              .single;
      expect(
          (await api('barcode lookup',
                  () => inventory.findByBarcode(normalBarcode)))
              ?.id,
          normal.id);

      // --- Purchase order: draft -> approve -> receive with batch/expiry --
      stdout.writeln('[e2e] purchase order approve and receive');
      final purchase = PurchaseRepository();
      final poId = await api(
          'create draft PO',
          () => purchase.createDraft(
                branchId: branchId,
                supplierId: supplierId,
                expectedDate:
                    DateTime.now().toUtc().add(const Duration(days: 5)),
                notes: 'E2E purchase order',
                tax: 0.0,
                lines: [
                  PurchaseOrderItem(
                      id: '',
                      poId: '',
                      medicineId: normal.id,
                      quantityOrdered: 20,
                      unitCost: 6.0),
                  PurchaseOrderItem(
                      id: '',
                      poId: '',
                      medicineId: rxMedicine.id,
                      quantityOrdered: 10,
                      unitCost: 12.0),
                ],
              ));
      final poLines = await api('PO lines', () => purchase.items(poId));
      expect(poLines.length, 2);
      final normalLine =
          poLines.firstWhere((line) => line.medicineId == normal.id);
      final rxLine =
          poLines.firstWhere((line) => line.medicineId == rxMedicine.id);
      expect(
          (await api('draft PO', () => purchase.order(poId))).status, 'draft');
      await api('approve PO', () => purchase.setStatus(poId, 'ordered'));
      expect((await api('ordered PO', () => purchase.order(poId))).status,
          'ordered');
      await api(
          'receive PO',
          () => purchase.receive(poId, [
                {
                  'po_item_id': normalLine.id,
                  'quantity': 12,
                  'batch_no': 'BN1-$runId',
                  'expiry_date': _dateIn(30),
                },
                {
                  'po_item_id': normalLine.id,
                  'quantity': 8,
                  'batch_no': 'BN2-$runId',
                  'expiry_date': _dateIn(90),
                },
                {
                  'po_item_id': rxLine.id,
                  'quantity': 6,
                  'batch_no': 'BR1-$runId',
                  'expiry_date': _dateIn(60),
                },
              ]));
      expect((await api('received PO', () => purchase.order(poId))).status,
          'received');
      final stock =
          await api('stock overview', () => inventory.stockSummary(branchId));
      expect(
          stock.firstWhere((row) => row.medicineId == normal.id).availableQty,
          20);
      final normalBatches = await api('batches',
          () => inventory.batches(branchId: branchId, medicineId: normal.id));
      final earliestBatch =
          normalBatches.firstWhere((batch) => batch.batchNo == 'BN1-$runId');

      // --- Customer and prescription -------------------------------------
      final customer = await api(
          'save customer',
          () => CustomersRepository().save({
                'name': 'E2E Customer $runId',
                'phone': '0912345678',
              }));
      final prescriptionId = newUuid();
      await api(
          'create prescription',
          () => PrescriptionsRepository().create(
                id: prescriptionId,
                branchId: branchId,
                patientName: 'E2E Patient',
                prescriberName: 'Dr E2E',
                rxDate: DateTime.now().toUtc(),
                customerId: customer.id,
              ));

      // --- Cashier shift and sales ---------------------------------------
      stdout.writeln('[e2e] shift -> sale -> return -> void -> close');
      useUser(cashierId);
      final sales = SalesRepository();
      final shift =
          await api('open shift', () => sales.openShift(branchId, 100));
      expect(shift, isNotNull);
      final shiftId = shift!.id;

      const SaleFilter allSales = (
        from: null,
        to: null,
        cashierId: null,
        status: null,
        method: null,
        invoice: null,
      );

      // 5% of the 30.00 subtotal is 1.50, so a 5.00 discount must be refused.
      await expectApiError(
          'cashier discount limit',
          () => sales.createSale(
                branchId: branchId,
                shiftId: shiftId,
                customerId: customer.id,
                prescriptionId: prescriptionId,
                items: [
                  {'medicine_id': normal.id, 'quantity': 1},
                  {'medicine_id': rxMedicine.id, 'quantity': 1},
                ],
                payments: [
                  {'method': 'cash', 'amount': 30.0},
                ],
                discount: 5.0,
              ));

      final saleA = await api(
          'create sale A',
          () => sales.createSale(
                branchId: branchId,
                shiftId: shiftId,
                customerId: customer.id,
                prescriptionId: prescriptionId,
                items: [
                  {'medicine_id': normal.id, 'quantity': 1},
                  {'medicine_id': rxMedicine.id, 'quantity': 1},
                ],
                payments: [
                  {'method': 'cash', 'amount': 20.0},
                  {'method': 'card', 'amount': 9.0},
                ],
                discount: 1.0,
                note: 'E2E split payment',
              ));
      final saleDetail = await api('sale A detail', () => sales.sale(saleA));
      expect(saleDetail.total, closeTo(29.0, 0.01));
      expect(saleDetail.cashierName, isNotNull,
          reason: 'cashier:profiles embed must resolve (PGRST200/201)');
      expect(saleDetail.customerName, isNotNull,
          reason: 'customer:customers embed must resolve (PGRST200/201)');
      final saleItems = await api('sale A items', () => sales.saleItems(saleA));
      final salePayments =
          await api('sale A payments', () => sales.salePayments(saleA));
      expect(saleItems.length, 2);
      expect(salePayments.map((payment) => payment.method).toSet(),
          {'cash', 'card'});
      expect(
          saleItems.firstWhere((item) => item.medicineId == normal.id).batchId,
          earliestBatch.id,
          reason: 'sale must consume the earliest-expiring batch (FEFO)');
      final dispensed = await api(
          'dispensed prescriptions',
          () => PrescriptionsRepository()
              .list(branchId: branchId, status: 'dispensed'));
      expect(dispensed.any((rx) => rx.id == prescriptionId), isTrue);

      final history =
          await api('sales history', () => sales.sales(allSales, branchId));
      expect(history.any((sale) => sale.id == saleA), isTrue);
      expect(history.any((sale) => sale.cashierName != null), isTrue);

      // Returns and voids are pharmacist/admin actions.
      useUser(adminId);
      final normalSaleItem =
          saleItems.firstWhere((item) => item.medicineId == normal.id);
      final returnId = await api(
          'partial return',
          () => sales.processReturn(
                saleId: saleA,
                items: [
                  {
                    'sale_item_id': normalSaleItem.id,
                    'quantity': 1,
                    'restock': true,
                  }
                ],
                reason: 'E2E partial return',
                refundMethod: 'cash',
              ));
      expect(returnId, isNotEmpty);
      final returns = await api(
          'sale returns', () => sales.saleReturns(branchId: branchId));
      expect(returns.any((row) => row.id == returnId && row.invoiceNo != null),
          isTrue,
          reason: 'sale:sales embed must resolve (PGRST200/201)');
      expect((await api('sale A after return', () => sales.sale(saleA))).status,
          'partially_returned');

      useUser(cashierId);
      final saleB = await api(
          'create sale B',
          () => sales.createSale(
                branchId: branchId,
                shiftId: shiftId,
                items: [
                  {'medicine_id': normal.id, 'quantity': 1},
                ],
                payments: [
                  {'method': 'cash', 'amount': 10.0},
                ],
                discount: 0.0,
              ));
      useUser(adminId);
      await api('void sale B', () => sales.voidSale(saleB, 'E2E void'));
      expect((await api('sale B', () => sales.sale(saleB))).status, 'voided');

      // Opening 100 + sale A cash 20 - cash refund 10 = 110. Sale B is voided.
      useUser(cashierId);
      final closed = await api(
          'close shift', () => sales.closeShift(shiftId, 110, 'E2E close'));
      expect(closed.expectedCash, closeTo(110.0, 0.01));
      expect(closed.difference, closeTo(0.0, 0.01));

      // --- Expense and approval ------------------------------------------
      stdout.writeln('[e2e] expense and approval');
      useUser(adminId);
      final expenseId = (await api(
          'create expense',
          () => admin
              .from('expenses')
              .insert({
                'branch_id': branchId,
                'category': 'Utilities',
                'description': 'E2E expense',
                'amount': 25.0,
                'expense_date': _dateIn(0),
                'status': 'pending',
              })
              .select('id')
              .single()))['id'] as String;
      await api(
          'approve expense',
          () => admin.rpc('set_expense_status', params: {
                'p_expense': expenseId,
                'p_status': 'approved',
              }));
      final expenseRow = await api(
          'expense status',
          () => admin
              .from('expenses')
              .select('status')
              .eq('id', expenseId)
              .single());
      expect(expenseRow['status'], 'approved');

      // --- All twelve report views ---------------------------------------
      stdout.writeln('[e2e] all 12 report views');
      final now = DateTime.now().toUtc();
      final reports = await api(
          'all report views',
          () => ReportsRepository().allForBranch(
                branchId,
                from: now.subtract(const Duration(days: 1)),
                to: now.add(const Duration(days: 1)),
              ));
      expect(reports.length, reportDefinitions.length);
      expect(reports.keys.toSet(), reportDefinitions.map((r) => r.key).toSet());
      for (final key in const [
        'salesByDay',
        'salesByCashier',
        'salesByPayment',
        'salesByMedicine',
        'profit',
        'stockValuation',
        'purchasesSupplier',
        'expenses',
        'netProfit',
        'shiftVariance',
        'controlledRegister',
      ]) {
        expect(reports[key], isNotEmpty,
            reason: 'report $key should have rows');
      }
      expect(reports['expiryLosses'], isA<List>(),
          reason: 'no expired batches are created by this suite, but the view '
              'must still be queryable');

      // --- Dashboard queries ---------------------------------------------
      stdout.writeln('[e2e] dashboard queries');
      final dashboard = DashboardRepository();
      final fromIso = startOfAddisDayUtc(now).toIso8601String();
      final toIso = endOfAddisDayUtc(now).toIso8601String();
      expect(
          (await api(
                  'dashboard sales',
                  () => dashboard.salesBetween(fromIso, toIso,
                      branchId: branchId)))
              .length,
          greaterThanOrEqualTo(2));
      expect(
          (await api(
                  'dashboard sale items',
                  () => dashboard.saleItemsBetween(fromIso, toIso,
                      branchId: branchId)))
              .length,
          greaterThanOrEqualTo(3));
      await api('dashboard low stock', () => dashboard.lowStock(branchId));
      await api('dashboard expiry', () => dashboard.expiringBatches(branchId));
      await api('dashboard open shifts', () => dashboard.openShifts(branchId));
      await api('dashboard prescriptions',
          () => dashboard.pendingPrescriptions(branchId));
      await api('dashboard orders', () => dashboard.ordersToReceive(branchId));
      final activity = await api(
          'dashboard activity', () => dashboard.activityLog(branchId));
      expect(activity.isNotEmpty, isTrue);
      expect(activity.any((row) => row['entity_type'] == 'sales'), isTrue);
      final team =
          await api('dashboard team', () => dashboard.teamMembers(branchId));
      expect(team.any((member) => member['id'] == cashierId), isTrue);

      // --- Create user (admin-create-user equivalent) + set_user_access ---
      stdout.writeln('[e2e] create user and set_user_access');
      final teammateId = await createUserViaSql(
          role: 'cashier', branchId: branchId, label: 'teammate');
      await api(
          'set_user_access',
          () => admin.rpc('set_user_access', params: {
                'p_user': teammateId,
                'p_role': 'pharmacist',
                'p_branch': branchId,
                'p_active': true,
              }));
      final promoted = await api(
          'promoted profile',
          () => admin
              .from('profiles')
              .select('role, branch_id, is_active')
              .eq('id', teammateId)
              .single());
      expect(promoted['role'], 'pharmacist');
      expect(promoted['branch_id'], branchId);
      useUser(teammateId);
      await api('pharmacist can read catalogue',
          () => inventory.medicines(query: normalSku));

      useUser(adminId);
      final activityAfter = await api(
          'activity after promotion', () => dashboard.activityLog(branchId));
      expect(
          activityAfter.any((row) => row['entity_type'] == 'profiles'), isTrue);
      final accessAudit = await api(
          'team access audit',
          () => admin
              .from('audit_logs')
              .select('action')
              .eq('record_id', teammateId));
      expect(
          accessAudit.any((row) => row['action'] == 'update_access'), isTrue);

      // --- Role-based negative tests -------------------------------------
      stdout.writeln('[e2e] role-based negative tests');
      final secondPoId = await api(
          'second draft PO',
          () => purchase.createDraft(
                branchId: branchId,
                supplierId: supplierId,
                expectedDate: null,
                notes: 'E2E cashier approval probe',
                tax: 0.0,
                lines: [
                  PurchaseOrderItem(
                      id: '',
                      poId: '',
                      medicineId: normal.id,
                      quantityOrdered: 1,
                      unitCost: 6.0),
                ],
              ));

      useUser(cashierId);
      final cashierClient = SupabaseService.client;
      await expectApiError('cashier cannot write medicines', () async {
        await cashierClient.from('medicines').insert({
          'name': 'E2E Forbidden $runId',
          'sku': 'E2EF$runId',
        });
      });
      await expectApiError('cashier cannot write suppliers', () async {
        await cashierClient.from('suppliers').insert({
          'name': 'E2E Forbidden Supplier $runId',
        });
      });
      await expectApiError('cashier cannot write settings', () async {
        await cashierClient.from('app_settings').insert({
          'key': 'e2e_forbidden_$runId',
          'value': 1,
        });
      });
      await expectApiError('cashier cannot approve PO',
          () => purchase.setStatus(secondPoId, 'ordered'));

      useUser(storeKeeperId);
      final visibleSales = await api(
          'store keeper sales visibility',
          () => SupabaseService.client
              .from('sales')
              .select('id')
              .eq('branch_id', branchId));
      expect(visibleSales, isEmpty,
          reason: 'store_keeper must not see sales through RLS');

      stdout.writeln('[e2e] ALL e2e-api CHECKS PASSED');
    }, timeout: const Timeout(Duration(minutes: 8)));
  });
}
