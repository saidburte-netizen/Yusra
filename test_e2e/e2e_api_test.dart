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
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:yusra_pharmacy/core/dates.dart';
import 'package:yusra_pharmacy/core/supabase_client.dart';
import 'package:yusra_pharmacy/features/customers/data/customers.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_metrics.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_repository.dart';
import 'package:yusra_pharmacy/features/inventory/data/reorder_models.dart';
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
      late SupabaseClient admin;
      useUser(adminId);
      admin = SupabaseService.client;
      final authUid =
          await api('auth uid', () => admin.rpc<String>('e2e_auth_uid'));
      final profile = await Process.run('bash', [
        'tool/ci_psql.sh',
        '-d',
        'postgres',
        '-Atc',
        "select role || '|' || case when is_active then 'active' else 'inactive' end "
            "from profiles where id = '$adminId';",
      ]);
      stdout.writeln('[e2e] auth uid=$authUid expected=$adminId');
      stdout.writeln('[e2e] admin profile=${profile.stdout.toString().trim()}');
      expect(authUid, adminId,
          reason: 'the signed JWT subject must reach auth.uid() via PostgREST');
      expect(profile.exitCode, 0, reason: '${profile.stderr}');
      expect(profile.stdout.toString().trim(), 'super_admin|active',
          reason: 'the trigger must seed an active super_admin profile');
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
      expect(
          (await api('partially received PO', () => purchase.order(poId)))
              .status,
          'partially_received');
      await api(
          'complete PO receipt',
          () => purchase.receive(poId, [
                {
                  'po_item_id': rxLine.id,
                  'quantity': 4,
                  'batch_no': 'BR2-$runId',
                  'expiry_date': _dateIn(120),
                },
              ]));
      expect((await api('received PO', () => purchase.order(poId))).status,
          'received');
      final stock =
          await api('stock overview', () => inventory.stockSummary(branchId));
      expect(
          stock.firstWhere((row) => row.medicineId == normal.id).availableQty,
          20);
      expect(
          stock
              .firstWhere((row) => row.medicineId == rxMedicine.id)
              .availableQty,
          10);
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
      admin = SupabaseService.client;
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
      admin = SupabaseService.client;
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
      admin = SupabaseService.client;
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
      admin = SupabaseService.client;
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

    test('opening stock, reorder suggestions and draft purchase order flow',
        () async {
      final runId = E2eEnv.runId;
      stdout.writeln('[e2e] opening stock -> reorder -> draft POs');

      // --- Admin identity, branch and users ------------------------------
      final adminId = await createUserViaSql(
          role: 'super_admin', branchId: '', label: 'reorder-admin');
      useUser(adminId);
      var admin = SupabaseService.client;

      final branchRow = await api(
          'create reorder branch',
          () => admin
              .from('branches')
              .insert({
                'name': 'E2E Reorder Branch $runId',
                'code': 'E2ER$runId',
                'address': 'E2E reorder address',
              })
              .select('id')
              .single());
      final branchId = branchRow['id'] as String;

      final storeKeeperId = await createUserViaSql(
          role: 'store_keeper', branchId: branchId, label: 'reorder-keeper');
      final cashierId = await createUserViaSql(
          role: 'cashier', branchId: branchId, label: 'reorder-cashier');

      // --- Catalogue with preferred suppliers and reorder targets --------
      final inventory = InventoryRepository();
      final categoryName = 'E2E Reorder Category $runId';
      await api('save reorder category',
          () => inventory.saveCategory({'name': categoryName}));
      final category =
          (await api('reorder categories', () => inventory.categories()))
              .firstWhere((item) => item.name == categoryName);

      final suppliers = SupplierRepository();
      final supplierAName = 'E2E Supplier A $runId';
      final supplierBName = 'E2E Supplier B $runId';
      await api(
          'save supplier A',
          () =>
              suppliers.save({'name': supplierAName, 'contact_person': 'E2E'}));
      await api(
          'save supplier B',
          () =>
              suppliers.save({'name': supplierBName, 'contact_person': 'E2E'}));
      final supplierRows =
          await api('reorder suppliers', () => suppliers.list());
      final supplierAId =
          supplierRows.firstWhere((item) => item.name == supplierAName).id;
      final supplierBId =
          supplierRows.firstWhere((item) => item.name == supplierBName).id;

      final skuA = 'E2EA$runId';
      final skuB = 'E2EB$runId';
      final noSupplierName = 'E2E No Supplier $runId';
      await api(
          'save reorder medicine A',
          () => inventory.saveMedicine({
                'name': 'E2E Reorder A $runId',
                'sku': skuA,
                'category_id': category.id,
                'cost_price': 5.0,
                'selling_price': 9.0,
                'unit': 'Pack',
                'reorder_level': 10,
                'target_level': 30,
                'preferred_supplier_id': supplierAId,
                'vat_applicable': false,
              }));
      await api(
          'save reorder medicine B',
          () => inventory.saveMedicine({
                'name': 'E2E Reorder B $runId',
                'sku': skuB,
                'category_id': category.id,
                'cost_price': 4.0,
                'selling_price': 8.0,
                'unit': 'Pack',
                'reorder_level': 4,
                'target_level': 12,
                'preferred_supplier_id': supplierBId,
                'vat_applicable': false,
              }));
      // C is the golden-path medicine: no supplier, no SKU supplied by the
      // form (the database generates one), and no barcode or category needed.
      await api(
          'save no-supplier medicine',
          () => inventory.saveMedicine({
                'name': noSupplierName,
                'cost_price': 5.0,
                'selling_price': 9.0,
                'unit': 'Tablet',
                'reorder_level': 10,
                'target_level': 20,
                'vat_applicable': false,
              }));
      final medA = (await api(
              'reorder medicine A', () => inventory.medicines(query: skuA)))
          .single;
      final medB = (await api(
              'reorder medicine B', () => inventory.medicines(query: skuB)))
          .single;
      final medC = (await api('no-supplier medicine',
              () => inventory.medicines(query: noSupplierName)))
          .single;
      expect(medC.preferredSupplierId, isNull,
          reason: 'a medicine must be usable without a preferred supplier');
      expect(medC.sku, matches(RegExp(r'^YP-\d{6}$')),
          reason: 'SKU must be auto-generated when the form leaves it blank');

      final batchesBefore = (await api(
              'batches before opening stock',
              () => admin
                  .from('stock_batches')
                  .select('id')
                  .eq('branch_id', branchId)))
          .length;

      // --- Store keeper registers opening stock in one atomic RPC --------
      useUser(storeKeeperId);
      final saved = await api(
          'add opening stock',
          () => inventory.addOpeningStock(
                branchId: branchId,
                rows: [
                  OpeningStockRowInput(
                    medicineId: medA.id,
                    quantity: 8,
                    expiry:
                        DateTime.now().toUtc().add(const Duration(days: 60)),
                    batchNo: 'OPEN-A-$runId',
                    unitCost: 5.0,
                  ),
                  OpeningStockRowInput(
                    medicineId: medB.id,
                    quantity: 3,
                    expiry:
                        DateTime.now().toUtc().add(const Duration(days: 10)),
                    unitCost: 4.0,
                  ),
                  OpeningStockRowInput(
                    medicineId: medC.id,
                    quantity: 12,
                    expiry:
                        DateTime.now().toUtc().add(const Duration(days: 60)),
                    batchNo: 'OPEN-C-$runId',
                    unitCost: 5.0,
                  ),
                ],
              ));
      expect(saved, 3, reason: 'all opening-stock rows must be registered');

      await expectApiError('past expiry aborts opening stock', () async {
        await inventory.addOpeningStock(
          branchId: branchId,
          rows: [
            OpeningStockRowInput(
              medicineId: medA.id,
              quantity: 1,
              expiry: DateTime.now().toUtc().subtract(const Duration(days: 1)),
            ),
          ],
        );
      });

      // --- Cashiers must not be able to register stock or create POs ------
      useUser(cashierId);
      final cashierClient = SupabaseService.client;
      expect(
          await api('cashier role', () => cashierClient.rpc<String>('my_role')),
          'cashier');
      await expectApiError('cashier cannot add opening stock', () async {
        await inventory.addOpeningStock(
          branchId: branchId,
          rows: [
            OpeningStockRowInput(
              medicineId: medA.id,
              quantity: 1,
              expiry: DateTime.now().toUtc().add(const Duration(days: 30)),
            ),
          ],
        );
      });
      await expectApiError('cashier cannot create draft POs', () async {
        await inventory.createDraftPurchaseOrders(
          branchId: branchId,
          lines: [
            {
              'supplier_id': supplierAId,
              'medicine_id': medA.id,
              'quantity': 1,
              'unit_cost': 5.0,
            },
          ],
        );
      });
      await expectApiError('cashier cannot add a stock batch', () async {
        await inventory.addStock(
          branchId: branchId,
          medicineId: medA.id,
          batchNo: 'CASHIER-$runId',
          expiry: DateTime.now().toUtc().add(const Duration(days: 30)),
          quantity: 1,
          cost: 1.0,
        );
      });

      // --- Admin verifies auto-batches, stock and reorder suggestions ----
      useUser(adminId);
      admin = SupabaseService.client;
      final batches = await api(
          'batches after opening stock',
          () => admin
              .from('stock_batches')
              .select('id, batch_no, medicine_id, quantity, expiry_date')
              .eq('branch_id', branchId));
      expect(batches, hasLength(batchesBefore + 3),
          reason: 'failed calls must not write partial batches');
      final autoBatch =
          batches.firstWhere((row) => row['medicine_id'] == medB.id);
      expect(autoBatch['batch_no'], matches(RegExp(r'^OPEN-\d{8}-\d{3}$')),
          reason: 'a blank batch number gets an OPEN-YYYYMMDD-NNN value');
      expect(autoBatch['quantity'], 3);
      expect(autoBatch['expiry_date'], _dateIn(10));
      final explicitBatch = batches.firstWhere((row) =>
          row['medicine_id'] == medA.id && row['batch_no'] == 'OPEN-A-$runId');
      expect(explicitBatch['expiry_date'], _dateIn(60));
      final goldenBatch = batches.firstWhere((row) =>
          row['medicine_id'] == medC.id && row['batch_no'] == 'OPEN-C-$runId');
      expect(goldenBatch['quantity'], 12);

      final stock = await api(
          'reorder stock summary', () => inventory.stockSummary(branchId));
      expect(
          stock.firstWhere((row) => row.medicineId == medA.id).availableQty, 8);
      expect(
          stock.firstWhere((row) => row.medicineId == medB.id).availableQty, 3);
      expect(stock.firstWhere((row) => row.medicineId == medC.id).availableQty,
          12);

      final suggestions = await api(
          'reorder suggestions', () => inventory.reorderSuggestions(branchId));
      final below =
          suggestions.firstWhere((item) => item.medicineId == medA.id);
      final expiring =
          suggestions.firstWhere((item) => item.medicineId == medB.id);
      expect(below.availableQty, 8);
      expect(below.reorderLevel, 10);
      expect(below.targetLevel, 30);
      expect(below.suggestedOrderQty, 22);
      expect(below.preferredSupplierId, supplierAId);
      expect(below.preferredSupplierName, supplierAName);
      expect(below.reason, 'Below reorder level');
      expect(expiring.onHand, 3);
      expect(expiring.availableQty, 0);
      expect(expiring.expiringQty, 3);
      expect(expiring.suggestedOrderQty, 12);
      expect(expiring.preferredSupplierId, supplierBId);
      expect(expiring.preferredSupplierName, supplierBName);
      expect(expiring.reason, contains('stock expiring within 30 days'));

      // --- Draft POs: one per supplier, supplier required on every line ---
      final poCountBefore = (await api(
              'PO count before invalid draft',
              () => admin
                  .from('purchase_orders')
                  .select('id')
                  .eq('branch_id', branchId)))
          .length;
      await expectApiError('blank supplier aborts draft POs', () async {
        await admin.rpc('create_draft_purchase_orders', params: {
          'p_branch': branchId,
          'p_lines': [
            {
              'supplier_id': null,
              'medicine_id': medA.id,
              'quantity': 1,
              'unit_cost': 5.0,
            },
          ],
        });
      });
      expect(
          (await api(
                  'PO count after invalid draft',
                  () => admin
                      .from('purchase_orders')
                      .select('id')
                      .eq('branch_id', branchId)))
              .length,
          poCountBefore,
          reason: 'a bad line must abort the whole draft-PO batch');

      final purchase = PurchaseRepository();
      final poIds = await api(
          'create draft POs from suggestions',
          () => inventory.createDraftPurchaseOrders(
                branchId: branchId,
                lines: [
                  {
                    'supplier_id': supplierAId,
                    'medicine_id': medA.id,
                    'quantity': below.suggestedOrderQty,
                    'unit_cost': 5.0,
                  },
                  {
                    'supplier_id': supplierBId,
                    'medicine_id': medB.id,
                    'quantity': expiring.suggestedOrderQty,
                    'unit_cost': 4.0,
                  },
                ],
              ));
      expect(poIds, hasLength(2));
      final poSuppliers = <String>{};
      for (final poId in poIds) {
        final order = await api('draft PO $poId', () => purchase.order(poId));
        expect(order.status, 'draft');
        expect(order.branchId, branchId);
        expect(order.notes, 'Created from reorder suggestions');
        poSuppliers.add(order.supplierId);
        final lines =
            await api('draft PO lines $poId', () => purchase.items(poId));
        expect(lines, hasLength(1));
      }
      expect(poSuppliers, {supplierAId, supplierBId},
          reason: 'each supplier gets its own draft PO');

      // --- The 8-argument add_stock_batch keeps source and supplier -------
      final purchaseBatch = await api(
          'purchase source batch',
          () => inventory.addStock(
                branchId: branchId,
                medicineId: medA.id,
                batchNo: 'PUR-A-$runId',
                expiry: DateTime.now().toUtc().add(const Duration(days: 90)),
                quantity: 2,
                cost: 5.5,
                supplierId: supplierAId,
                source: 'purchase',
              ));
      expect(purchaseBatch, 'PUR-A-$runId');
      final purchaseBatchRow = await api(
          'purchase batch row',
          () => admin
              .from('stock_batches')
              .select('id, supplier_id, expiry_date')
              .eq('branch_id', branchId)
              .eq('batch_no', purchaseBatch)
              .single());
      expect(purchaseBatchRow['supplier_id'], supplierAId);
      expect(purchaseBatchRow['expiry_date'], _dateIn(90));
      final movement = await api(
          'purchase movement',
          () => admin
              .from('stock_movements')
              .select('movement_type')
              .eq('batch_id', purchaseBatchRow['id'] as String));
      expect(movement.single['movement_type'], 'purchase');
      await expectApiError('invalid stock source rejected', () async {
        await inventory.addStock(
          branchId: branchId,
          medicineId: medA.id,
          batchNo: 'BAD-$runId',
          expiry: DateTime.now().toUtc().add(const Duration(days: 90)),
          quantity: 1,
          cost: 1.0,
          source: 'invalid',
        );
      });

      // --- Golden path: no-supplier medicine -> sell -> reorder -> PO -----
      stdout.writeln('[e2e] golden no-supplier medicine -> sale -> reorder');
      useUser(cashierId);
      final reorderSales = SalesRepository();
      final reorderShift = await api(
          'open reorder shift', () => reorderSales.openShift(branchId, 100));
      expect(reorderShift, isNotNull);
      final reorderShiftId = reorderShift!.id;
      final reorderSale = await api(
          'sell five no-supplier units',
          () => reorderSales.createSale(
                branchId: branchId,
                shiftId: reorderShiftId,
                items: [
                  {'medicine_id': medC.id, 'quantity': 5},
                ],
                payments: [
                  {'method': 'cash', 'amount': 45.0},
                ],
                discount: 0.0,
                note: 'E2E reorder golden path',
              ));
      expect(reorderSale, isNotEmpty);
      final reorderClosed = await api(
          'close reorder shift',
          () => reorderSales.closeShift(
              reorderShiftId, 145, 'E2E reorder close'));
      expect(reorderClosed.expectedCash, closeTo(145.0, 0.01));
      expect(reorderClosed.difference, closeTo(0.0, 0.01));

      useUser(adminId);
      admin = SupabaseService.client;
      final afterSale = await api(
          'stock after golden sale', () => inventory.stockSummary(branchId));
      expect(
          afterSale.firstWhere((row) => row.medicineId == medC.id).availableQty,
          7);

      final goldenSuggestion = (await api('golden reorder suggestions',
              () => inventory.reorderSuggestions(branchId)))
          .firstWhere((item) => item.medicineId == medC.id);
      expect(goldenSuggestion.onHand, 7);
      expect(goldenSuggestion.availableQty, 7);
      expect(goldenSuggestion.reorderLevel, 10);
      expect(goldenSuggestion.targetLevel, 20);
      expect(goldenSuggestion.suggestedOrderQty, 13);
      expect(goldenSuggestion.preferredSupplierId, isNull,
          reason: 'a no-supplier medicine lands in the Choose supplier group');

      // The screen requires the user to assign a supplier before creating.
      final goldenPoIds = await api(
          'create golden draft PO',
          () => inventory.createDraftPurchaseOrders(
                branchId: branchId,
                lines: [
                  {
                    'supplier_id': supplierBId,
                    'medicine_id': medC.id,
                    'quantity': goldenSuggestion.suggestedOrderQty,
                    'unit_cost': 5.0,
                  },
                ],
              ));
      expect(goldenPoIds, hasLength(1));
      final goldenPoId = goldenPoIds.single;
      expect(
          (await api('golden draft PO', () => purchase.order(goldenPoId)))
              .status,
          'draft');
      final goldenLines =
          await api('golden draft PO lines', () => purchase.items(goldenPoId));
      expect(goldenLines, hasLength(1));
      expect(goldenLines.single.quantityOrdered, 13);

      await api(
          'approve golden PO', () => purchase.setStatus(goldenPoId, 'ordered'));
      expect(
          (await api('golden ordered PO', () => purchase.order(goldenPoId)))
              .status,
          'ordered');
      await api(
          'receive golden PO',
          () => purchase.receive(goldenPoId, [
                {
                  'po_item_id': goldenLines.single.id,
                  'quantity': 13,
                  'batch_no': 'GRN-C-$runId',
                  'expiry_date': _dateIn(60),
                },
              ]));
      expect(
          (await api('golden received PO', () => purchase.order(goldenPoId)))
              .status,
          'received');
      final finalStock = await api(
          'stock after golden receipt', () => inventory.stockSummary(branchId));
      expect(
          finalStock
              .firstWhere((row) => row.medicineId == medC.id)
              .availableQty,
          20);

      stdout.writeln('[e2e] ALL opening-stock/reorder CHECKS PASSED');
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}
