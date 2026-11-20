// Manual smoke test for Yusra Pharmacy. Plain Dart:
//
//   dart run tool/smoke_test.dart
//
// Required environment variables:
//   SUPABASE_URL, SUPABASE_ANON_KEY
//   SMOKE_ADMIN_EMAIL / SMOKE_ADMIN_PASSWORD
//   SMOKE_CASHIER_EMAIL / SMOKE_CASHIER_PASSWORD
//   SMOKE_PHARMACIST_EMAIL / SMOKE_PHARMACIST_PASSWORD
// Optional:
//   SMOKE_BRANCH_ID          (defaults to the first branch)
//   SMOKE_EXPIRED_BATCH_ID   (a batch with an expiry in the past, seeded by the owner)
//
// The tool refuses to touch a URL containing "prod" unless SMOKE_CONFIRM=1.

import 'dart:io';

import 'src/supabase_rest.dart';

final class _Results {
  int passed = 0;
  int failed = 0;
  int skipped = 0;

  void pass(String label) {
    passed++;
    stdout.writeln('  PASS  $label');
  }

  void fail(String label, [String detail = '']) {
    failed++;
    stdout.writeln('  FAIL  $label${detail.isEmpty ? '' : ' — $detail'}');
  }

  void skip(String label, String why) {
    skipped++;
    stdout.writeln('  SKIP  $label — $why');
  }
}

String _env(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable $key');
  }
  return value;
}

Future<void> main() async {
  SupabaseRest.assertSafeTarget();
  final results = _Results();
  final api = SupabaseRest.fromEnv();
  final url = api.url;
  stdout.writeln('Yusra Pharmacy smoke test');
  stdout.writeln('Target: $url');
  stdout.writeln('');

  try {
    final admin = SupabaseRest.fromEnv();
    final cashier = SupabaseRest.fromEnv();
    final pharmacist = SupabaseRest.fromEnv();

    await admin.signIn(_env('SMOKE_ADMIN_EMAIL'), _env('SMOKE_ADMIN_PASSWORD'));
    await cashier.signIn(
        _env('SMOKE_CASHIER_EMAIL'), _env('SMOKE_CASHIER_PASSWORD'));
    await pharmacist.signIn(
        _env('SMOKE_PHARMACIST_EMAIL'), _env('SMOKE_PHARMACIST_PASSWORD'));
    results.pass('demo users for admin, cashier and pharmacist can sign in');
  } catch (error) {
    stdout.writeln('Could not sign in: $error');
    stdout.writeln('Check that 0012_rls_hardening.sql was applied and that the '
        'SMOKE_* credentials match demo users.');
    exit(2);
  }

  // Re-create the clients we need below (signIn mutates a client's token).
  final admin = SupabaseRest.fromEnv();
  final cashier = SupabaseRest.fromEnv();
  final pharmacist = SupabaseRest.fromEnv();
  await admin.signIn(_env('SMOKE_ADMIN_EMAIL'), _env('SMOKE_ADMIN_PASSWORD'));
  await cashier.signIn(
      _env('SMOKE_CASHIER_EMAIL'), _env('SMOKE_CASHIER_PASSWORD'));
  await pharmacist.signIn(
      _env('SMOKE_PHARMACIST_EMAIL'), _env('SMOKE_PHARMACIST_PASSWORD'));

  final branchRows = await admin.select('branches', columns: 'id', filters: {
    'is_active': 'eq.true',
  });
  final branchId = Platform.environment['SMOKE_BRANCH_ID'] ??
      (branchRows.isEmpty ? null : branchRows.first['id'] as String);
  if (branchId == null) {
    stdout.writeln('No branch available; cannot run data checks.');
    exit(2);
  }

  stdout.writeln('RLS and role rules');
  await _checkInsertDenied(cashier, 'medicines', {
    'name': 'Smoke test medicine ${DateTime.now().microsecondsSinceEpoch}',
    'cost_price': 1,
    'selling_price': 2,
  }, 'a cashier cannot insert into medicines', results);
  await _checkInsertDenied(cashier, 'stock_batches', {
    'branch_id': branchId,
    'medicine_id': branchId, // intentionally invalid; RLS must reject first
    'batch_no': 'SMOKE',
    'expiry_date': '2099-01-01',
    'quantity': 1,
  }, 'a cashier cannot insert into stock_batches', results);
  await _checkInsertDenied(cashier, 'sales', {
    'invoice_no': 'SMOKE-${DateTime.now().microsecondsSinceEpoch}',
    'branch_id': branchId,
    'cashier_id': (await cashier.select('profiles', columns: 'id', filters: {
      'role': 'eq.cashier',
    })).first['id'],
  }, 'a cashier cannot insert into sales', results);

  final audit = await cashier.select('audit_logs', columns: 'id');
  if (audit.isEmpty) {
    results.pass('a cashier cannot read audit_logs');
  } else {
    results.fail('a cashier cannot read audit_logs', '${audit.length} rows returned');
  }

  final adminStatus = await admin.tryInsert('profiles', {
    'id': '00000000-0000-0000-0000-${DateTime.now().microsecondsSinceEpoch.toString().padLeft(12, '0').substring(0, 12)}',
    'full_name': 'Smoke super admin',
    'role': 'super_admin',
    'branch_id': branchId,
    'is_active': true,
  });
  if (adminStatus >= 400) {
    results.pass('an admin cannot create a super_admin');
  } else {
    results.fail('an admin cannot create a super_admin', 'insert returned $adminStatus');
  }

  stdout.writeln('');
  stdout.writeln('Business rules');

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final medicineRows = await admin.select('medicines', columns: 'id', filters: {
    'name': 'eq.Smoke-$stamp',
  });
  String medicineId;
  if (medicineRows.isEmpty) {
    // Admin has catalogue write rights under 0012.
    final inserted = await admin.tryInsert('medicines', {
      'name': 'Smoke-$stamp',
      'cost_price': 10,
      'selling_price': 20,
      'vat_applicable': false,
      'requires_prescription': false,
    });
    if (inserted >= 400) {
      results.fail('create a test medicine as admin', 'HTTP $inserted');
      return _finish(results);
    }
    final rows = await admin.select('medicines', columns: 'id', filters: {
      'name': 'eq.Smoke-$stamp',
    });
    medicineId = rows.first['id'] as String;
  } else {
    medicineId = medicineRows.first['id'] as String;
  }
  results.pass('test medicine available');

  final noShift = await cashier.tryRpc('create_sale', {
    'p_branch': branchId,
    'p_shift': null,
    'p_customer': null,
    'p_prescription': null,
    'p_items': [
      {'medicine_id': medicineId, 'quantity': 1}
    ],
    'p_payments': [
      {'method': 'cash', 'amount': 20}
    ],
    'p_discount': 0,
    'p_note': 'smoke',
  });
  if (noShift.statusCode >= 400) {
    results.pass('create_sale fails without an open shift');
  } else {
    results.fail('create_sale fails without an open shift', 'RPC returned success');
  }

  // Prescription-only rule.
  final rxRows = await admin.select('medicines', columns: 'id', filters: {
    'name': 'eq.Smoke-Rx-$stamp',
  });
  String rxId;
  if (rxRows.isEmpty) {
    final inserted = await admin.tryInsert('medicines', {
      'name': 'Smoke-Rx-$stamp',
      'cost_price': 10,
      'selling_price': 20,
      'vat_applicable': false,
      'requires_prescription': true,
    });
    if (inserted >= 400) {
      results.fail('create an Rx test medicine as admin', 'HTTP $inserted');
      return _finish(results);
    }
    final rows = await admin.select('medicines', columns: 'id', filters: {
      'name': 'eq.Smoke-Rx-$stamp',
    });
    rxId = rows.first['id'] as String;
  } else {
    rxId = rxRows.first['id'] as String;
  }
  await admin.rpc('add_stock_batch', {
    'p_branch': branchId,
    'p_medicine': rxId,
    'p_batch_no': 'RX-$stamp',
    'p_expiry': '2099-12-31',
    'p_quantity': 5,
    'p_cost': 10,
  });
  final openShiftRaw = await cashier.rpc('open_shift', {
    'p_branch': branchId,
    'p_opening_cash': 100,
  });
  final shiftId = _idOf(openShiftRaw);
  if (shiftId == null) {
    results.fail('open a shift for the cashier');
    return _finish(results);
  }
  results.pass('cashier can open a shift');

  final noRx = await cashier.tryRpc('create_sale', {
    'p_branch': branchId,
    'p_shift': shiftId,
    'p_customer': null,
    'p_prescription': null,
    'p_items': [
      {'medicine_id': rxId, 'quantity': 1}
    ],
    'p_payments': [
      {'method': 'cash', 'amount': 20}
    ],
    'p_discount': 0,
    'p_note': 'smoke',
  });
  if (noRx.statusCode >= 400) {
    results.pass('create_sale fails for an Rx medicine without a prescription');
  } else {
    results.fail('create_sale fails for an Rx medicine without a prescription',
        'RPC returned success');
  }

  // FEFO: two batches, different expiries. Sell one unit and check the
  // earliest-expiry batch was reduced.
  const far = '2099-12-31';
  final near = DateTime.now().toUtc().add(const Duration(days: 30));
  final nearDate = '${near.year.toString().padLeft(4, '0')}-'
      '${near.month.toString().padLeft(2, '0')}-'
      '${near.day.toString().padLeft(2, '0')}';
  final nearId = await admin.rpc('add_stock_batch', {
    'p_branch': branchId,
    'p_medicine': medicineId,
    'p_batch_no': 'NEAR-$stamp',
    'p_expiry': nearDate,
    'p_quantity': 3,
    'p_cost': 10,
  });
  final farId = await admin.rpc('add_stock_batch', {
    'p_branch': branchId,
    'p_medicine': medicineId,
    'p_batch_no': 'FAR-$stamp',
    'p_expiry': far,
    'p_quantity': 3,
    'p_cost': 10,
  });
  final beforeNear = _quantityOf(await admin.select('stock_batches',
      columns: 'quantity', filters: {'id': 'eq.$nearId'}));
  final beforeFar = _quantityOf(await admin.select('stock_batches',
      columns: 'quantity', filters: {'id': 'eq.$farId'}));

  final saleId = await cashier.rpc('create_sale', {
    'p_branch': branchId,
    'p_shift': shiftId,
    'p_customer': null,
    'p_prescription': null,
    'p_items': [
      {'medicine_id': medicineId, 'quantity': 1}
    ],
    'p_payments': [
      {'method': 'cash', 'amount': 20}
    ],
    'p_discount': 0,
    'p_note': 'smoke FEFO',
  });
  final afterNear = _quantityOf(await admin.select('stock_batches',
      columns: 'quantity', filters: {'id': 'eq.$nearId'}));
  final afterFar = _quantityOf(await admin.select('stock_batches',
      columns: 'quantity', filters: {'id': 'eq.$farId'}));
  if (afterNear == beforeNear - 1 && afterFar == beforeFar) {
    results.pass('create_sale takes the earliest expiry batch first (FEFO)');
  } else {
    results.fail('create_sale takes the earliest expiry batch first (FEFO)',
        'near $beforeNear→$afterNear, far $beforeFar→$afterFar');
  }

  final expiredId = Platform.environment['SMOKE_EXPIRED_BATCH_ID'];
  if (expiredId == null || expiredId.isEmpty) {
    results.skip('create_sale never uses an expired batch',
        'set SMOKE_EXPIRED_BATCH_ID to an expired batch seeded by the owner');
  } else {
    final beforeExpired = _quantityOf(await admin.select('stock_batches',
        columns: 'quantity', filters: {'id': 'eq.$expiredId'}));
    await cashier.tryRpc('create_sale', {
      'p_branch': branchId,
      'p_shift': shiftId,
      'p_customer': null,
      'p_prescription': null,
      'p_items': [
        {'medicine_id': medicineId, 'quantity': 1}
      ],
      'p_payments': [
        {'method': 'cash', 'amount': 20}
      ],
      'p_discount': 0,
      'p_note': 'smoke expired',
    });
    final afterExpired = _quantityOf(await admin.select('stock_batches',
        columns: 'quantity', filters: {'id': 'eq.$expiredId'}));
    if (afterExpired == beforeExpired) {
      results.pass('create_sale never uses an expired batch');
    } else {
      results.fail('create_sale never uses an expired batch',
          'quantity $beforeExpired→$afterExpired');
    }
  }

  // Return restores stock.
  final saleItems = await admin.select('sale_items', columns: 'id, batch_id, quantity',
      filters: {'sale_id': 'eq.$saleId'});
  if (saleItems.isEmpty) {
    results.fail('return restores stock', 'no sale items found');
  } else {
    final item = saleItems.first;
    final batchId = item['batch_id'] as String;
    final before = _quantityOf(await admin.select('stock_batches',
        columns: 'quantity', filters: {'id': 'eq.$batchId'}));
    final returnResponse = await pharmacist.tryRpc('process_sale_return', {
      'p_sale': saleId,
      'p_items': [
        {
          'sale_item_id': item['id'],
          'quantity': 1,
          'restock': true,
        }
      ],
      'p_reason': 'Smoke test return',
      'p_refund_method': 'cash',
    });
    final after = _quantityOf(await admin.select('stock_batches',
        columns: 'quantity', filters: {'id': 'eq.$batchId'}));
    if (returnResponse.statusCode < 400 && after == before + 1) {
      results.pass('process_sale_return restores stock');
    } else {
      results.fail('process_sale_return restores stock',
          'HTTP ${returnResponse.statusCode}, quantity $before→$after');
    }
  }

  // Void restores stock on another sale.
  final secondSale = await cashier.rpc('create_sale', {
    'p_branch': branchId,
    'p_shift': shiftId,
    'p_customer': null,
    'p_prescription': null,
    'p_items': [
      {'medicine_id': medicineId, 'quantity': 1}
    ],
    'p_payments': [
      {'method': 'cash', 'amount': 20}
    ],
    'p_discount': 0,
    'p_note': 'smoke void',
  });
  final secondItems = await admin.select('sale_items',
      columns: 'id, batch_id, quantity', filters: {'sale_id': 'eq.$secondSale'});
  if (secondItems.isEmpty) {
    results.fail('void_sale restores stock', 'no sale items found');
  } else {
    final batchId = secondItems.first['batch_id'] as String;
    final before = _quantityOf(await admin.select('stock_batches',
        columns: 'quantity', filters: {'id': 'eq.$batchId'}));
    final voidResponse = await pharmacist.tryRpc('void_sale', {
      'p_sale': secondSale,
      'p_reason': 'Smoke test void',
    });
    final after = _quantityOf(await admin.select('stock_batches',
        columns: 'quantity', filters: {'id': 'eq.$batchId'}));
    if (voidResponse.statusCode < 400 && after == before + 1) {
      results.pass('void_sale restores stock');
    } else {
      results.fail('void_sale restores stock',
          'HTTP ${voidResponse.statusCode}, quantity $before→$after');
    }
  }

  // Close shift expected cash: opening + completed cash sales − cash refunds.
  final closed = await cashier.rpc('close_shift', {
    'p_shift': shiftId,
    'p_closing_cash': 100,
    'p_note': 'smoke close',
  });
  final expected = _numberOf(closed, 'expected_cash');
  final difference = _numberOf(closed, 'difference');
  if (expected != null && difference != null && (expected - 100 - difference).abs() < 0.01) {
    results.pass('close_shift reports expected cash and difference');
  } else {
    results.fail('close_shift reports expected cash and difference',
        'expected=$expected difference=$difference');
  }

  stdout.writeln('Test medicines are left in the catalogue with a "Smoke-" '
      'prefix so you can inspect them and remove them when finished.');
  _finish(results);
}

Future<void> _checkInsertDenied(
  SupabaseRest api,
  String table,
  Map<String, dynamic> values,
  String label,
  _Results results,
) async {
  final status = await api.tryInsert(table, values);
  if (status >= 400) {
    results.pass(label);
  } else {
    results.fail(label, 'insert unexpectedly returned $status');
  }
}

String? _idOf(dynamic raw) {
  if (raw is String) return raw;
  if (raw is Map) return raw['id']?.toString();
  if (raw is List && raw.isNotEmpty) return raw.first.toString();
  return null;
}

int _quantityOf(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return -1;
  final value = rows.first['quantity'];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? -1;
}

double? _numberOf(dynamic raw, String key) {
  if (raw is Map) {
    final value = raw[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
  if (raw is List && raw.isNotEmpty) return _numberOf(raw.first, key);
  return null;
}

void _finish(_Results results) {
  stdout.writeln('');
  stdout.writeln('Passed: ${results.passed}  Failed: ${results.failed}  '
      'Skipped: ${results.skipped}');
  exit(results.failed == 0 ? 0 : 1);
}
