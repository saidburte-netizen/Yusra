// Demo data seeder for Yusra Pharmacy. Plain Dart:
//
//   dart run tool/seed_demo.dart
//
// Required environment variables:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Optional:
//   SEED_DEMO_PASSWORD   (defaults to a clearly-labelled demo password)
//   SEED_CONFIRM=1       (required when the URL contains "prod")
//
// The service-role key is read from the environment at runtime. It is never
// written to a file, printed, or committed. Seeding goes through the Supabase
// Auth admin endpoint and the REST API only.

import 'dart:io';

import 'src/supabase_rest.dart';

const _categories = [
  'Antibiotics',
  'Pain relief',
  'Cardiovascular',
  'Diabetes care',
  'Respiratory',
  'Digestive health',
  'Vitamins & supplements',
  'Skin care',
];

// name, generic name, form, strength, category index, cost, price, vat, rx
const _medicines = [
  ('Amoxicillin 500mg Capsule', 'Amoxicillin', 'Capsule', '500 mg', 0, 4.20, 7.50, true, true),
  ('Amoxicillin 250mg Capsule', 'Amoxicillin', 'Capsule', '250 mg', 0, 2.60, 4.80, true, true),
  ('Azithromycin 500mg Tablet', 'Azithromycin', 'Tablet', '500 mg', 0, 7.80, 13.00, true, true),
  ('Ciprofloxacin 500mg Tablet', 'Ciprofloxacin', 'Tablet', '500 mg', 0, 5.40, 9.20, true, true),
  ('Doxycycline 100mg Capsule', 'Doxycycline', 'Capsule', '100 mg', 0, 3.10, 5.60, true, true),
  ('Metronidazole 500mg Tablet', 'Metronidazole', 'Tablet', '500 mg', 0, 2.90, 5.20, true, true),
  ('Ceftriaxone 1g Injection', 'Ceftriaxone', 'Injection', '1 g', 0, 22.00, 38.00, true, true),
  ('Paracetamol 500mg Tablet', 'Paracetamol', 'Tablet', '500 mg', 1, 0.90, 1.80, true, false),
  ('Ibuprofen 400mg Tablet', 'Ibuprofen', 'Tablet', '400 mg', 1, 1.40, 2.60, true, false),
  ('Diclofenac 75mg Injection', 'Diclofenac', 'Injection', '75 mg', 1, 3.20, 6.00, true, true),
  ('Tramadol 50mg Capsule', 'Tramadol', 'Capsule', '50 mg', 1, 4.10, 7.40, true, true),
  ('Aspirin 81mg Tablet', 'Aspirin', 'Tablet', '81 mg', 1, 1.10, 2.20, true, false),
  ('Amlodipine 5mg Tablet', 'Amlodipine', 'Tablet', '5 mg', 2, 1.80, 3.40, true, true),
  ('Enalapril 10mg Tablet', 'Enalapril', 'Tablet', '10 mg', 2, 2.10, 3.90, true, true),
  ('Losartan 50mg Tablet', 'Losartan', 'Tablet', '50 mg', 2, 2.80, 5.00, true, true),
  ('Atorvastatin 20mg Tablet', 'Atorvastatin', 'Tablet', '20 mg', 2, 4.60, 8.20, true, true),
  ('Metoprolol 50mg Tablet', 'Metoprolol', 'Tablet', '50 mg', 2, 2.30, 4.20, true, true),
  ('Metformin 500mg Tablet', 'Metformin', 'Tablet', '500 mg', 3, 1.20, 2.40, true, true),
  ('Metformin 1000mg Tablet', 'Metformin', 'Tablet', '1000 mg', 3, 2.00, 3.80, true, true),
  ('Glibenclamide 5mg Tablet', 'Glibenclamide', 'Tablet', '5 mg', 3, 1.60, 3.00, true, true),
  ('Insulin Glargine 100IU/ml', 'Insulin Glargine', 'Injection', '100 IU/ml', 3, 78.00, 125.00, true, true),
  ('Salbutamol Inhaler 100mcg', 'Salbutamol', 'Inhaler', '100 mcg', 4, 12.50, 21.00, true, true),
  ('Beclomethasone Inhaler', 'Beclomethasone', 'Inhaler', '50 mcg', 4, 15.00, 25.00, true, true),
  ('Cetirizine 10mg Tablet', 'Cetirizine', 'Tablet', '10 mg', 4, 1.30, 2.50, true, false),
  ('Loratadine 10mg Tablet', 'Loratadine', 'Tablet', '10 mg', 4, 1.40, 2.70, true, false),
  ('Omeprazole 20mg Capsule', 'Omeprazole', 'Capsule', '20 mg', 5, 2.20, 4.10, true, false),
  ('Ranitidine 150mg Tablet', 'Ranitidine', 'Tablet', '150 mg', 5, 1.70, 3.20, true, false),
  ('Oral Rehydration Salt', 'ORS', 'Powder', '21 g', 5, 0.60, 1.20, false, false),
  ('Vitamin C 500mg Tablet', 'Ascorbic Acid', 'Tablet', '500 mg', 6, 1.90, 3.60, true, false),
  ('Hydrocortisone 1% Cream', 'Hydrocortisone', 'Cream', '1%', 7, 3.40, 6.20, true, false),
];

const _users = [
  ('superadmin@yusra.test', 'Super Admin', 'super_admin'),
  ('admin@yusra.test', 'Pharmacy Admin', 'admin'),
  ('pharmacist@yusra.test', 'Senior Pharmacist', 'pharmacist'),
  ('cashier@yusra.test', 'Branch Cashier', 'cashier'),
  ('storekeeper@yusra.test', 'Store Keeper', 'store_keeper'),
  ('accountant@yusra.test', 'Accountant', 'accountant'),
];

Future<void> main() async {
  final url = Platform.environment['SUPABASE_URL'];
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || url.isEmpty || serviceKey == null || serviceKey.isEmpty) {
    stdout.writeln('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.');
    exit(2);
  }
  try {
    SupabaseRest.assertSafeTarget(confirmVar: 'SEED_CONFIRM');
  } on StateError catch (error) {
    // Keep the refusal as a clean message with a non-zero exit code.
    stdout.writeln(error.message);
    exit(2);
  }
  if (url.toLowerCase().contains('prod') &&
      Platform.environment['SEED_CONFIRM'] == '1') {
    stdout.writeln('WARNING: seeding a production-looking URL with SEED_CONFIRM=1.');
  }

  final api = SupabaseRest.service(url: url, serviceRoleKey: serviceKey);
  final password = Platform.environment['SEED_DEMO_PASSWORD'] ?? 'Demo@Yusra2026!';
  stdout.writeln('Yusra Pharmacy demo seeder');
  stdout.writeln('Target: ${api.url}');
  stdout.writeln('');

  // Branch -----------------------------------------------------------------
  var branches = await api.select('branches', columns: 'id', filters: {'code': 'eq.MAIN'});
  if (branches.isEmpty) {
    await api.insert('branches', {
      'name': 'Yusra Main Branch',
      'code': 'MAIN',
      'address': 'Addis Ababa, Ethiopia',
      'is_active': true,
    });
    branches = await api.select('branches', columns: 'id', filters: {'code': 'eq.MAIN'});
  }
  if (branches.isEmpty) {
    stdout.writeln('Branch MAIN is missing. Create it in Supabase and rerun.');
    exit(2);
  }
  final branchId = branches.first['id'] as String;
  stdout.writeln('Branch: $branchId');

  // Users ------------------------------------------------------------------
  final createdIds = <String, String>{};
  for (final (email, name, role) in _users) {
    final created = await api.adminCreateUser(
      email: email,
      password: password,
      fullName: name,
      role: role,
      branchId: branchId,
    );
    if (created != null && created['id'] != null) {
      createdIds[email] = created['id'].toString();
    }
    final label = created == null ? 'exists' : 'created';
    stdout.writeln('  $role: $email ($label)');
  }

  // Profiles are normally created by the handle_new_user trigger. Repair any
  // profile whose role or branch drifted, without inventing RPCs.
  for (final (email, name, role) in _users) {
    final id = createdIds[email];
    final filters = id != null
        ? {'id': 'eq.$id'}
        : {'email': 'eq.$email'};
    final existing = await api.select('profiles', columns: 'id, role, branch_id', filters: filters);
    if (existing.isEmpty && id != null) {
      await api.tryInsert('profiles', {
        'id': id,
        'email': email,
        'full_name': name,
        'role': role,
        'branch_id': branchId,
        'is_active': true,
      });
    } else if (existing.isNotEmpty) {
      final row = existing.first;
      if (row['role'] != role || row['branch_id'] != branchId) {
        await api.update('profiles', {
          'role': role,
          'branch_id': branchId,
          'full_name': name,
        }, filters: {'id': 'eq.${row['id']}'});
      }
    }
  }
  stdout.writeln('Demo password: $password (set SEED_DEMO_PASSWORD to override)');

  // Categories -------------------------------------------------------------
  final categoryIds = <String>[];
  for (final name in _categories) {
    var rows = await api.select('categories', columns: 'id', filters: {'name': 'eq.$name'});
    if (rows.isEmpty) {
      await api.tryInsert('categories', {'name': name, 'is_active': true});
      rows = await api.select('categories', columns: 'id', filters: {'name': 'eq.$name'});
    }
    if (rows.isNotEmpty) categoryIds.add(rows.first['id'] as String);
  }
  stdout.writeln('Categories: ${categoryIds.length}');

  // Supplier ---------------------------------------------------------------
  var suppliers = await api.select('suppliers', columns: 'id', filters: {
    'name': 'eq.Addis Pharma Distributors',
  });
  if (suppliers.isEmpty) {
    await api.tryInsert('suppliers', {
      'name': 'Addis Pharma Distributors',
      'contact_person': 'Mrs. Amina Bekele',
      'phone': '+251 11 555 0100',
      'email': 'sales@addispharma.example',
      'address': 'Addis Ababa, Ethiopia',
      'payment_terms': 'Net 30',
      'is_active': true,
    });
    suppliers = await api.select('suppliers', columns: 'id', filters: {
      'name': 'eq.Addis Pharma Distributors',
    });
  }
  final supplierId = suppliers.isEmpty ? null : suppliers.first['id'] as String;

  // Medicines --------------------------------------------------------------
  final today = DateTime.now().toUtc();
  String dateIn(int days) {
    final value = today.add(Duration(days: days));
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  var medicineCount = 0;
  for (final item in _medicines) {
    final (name, generic, form, strength, categoryIndex, cost, price, vat, rx) = item;
    var rows = await api.select('medicines', columns: 'id', filters: {
      'name': 'eq.$name',
    });
    String medicineId;
    if (rows.isEmpty) {
      final status = await api.tryInsert('medicines', {
        'name': name,
        'generic_name': generic,
        'dosage_form': form,
        'strength': strength,
        'category_id': categoryIndex < categoryIds.length
            ? categoryIds[categoryIndex]
            : null,
        'unit': form == 'Injection' || form == 'Inhaler' ? 'Piece' : 'Pack',
        'cost_price': cost,
        'selling_price': price,
        'vat_applicable': vat,
        'requires_prescription': rx,
        'reorder_level': 20,
        'is_active': true,
      });
      if (status >= 400) continue;
      rows = await api.select('medicines', columns: 'id', filters: {
        'name': 'eq.$name',
      });
    }
    if (rows.isEmpty) continue;
    medicineId = rows.first['id'] as String;
    medicineCount++;

    final existingBatches = await api.select('stock_batches', columns: 'id', filters: {
      'medicine_id': 'eq.$medicineId',
      'branch_id': 'eq.$branchId',
    });
    if (existingBatches.isNotEmpty) continue;

    // Two FEFO batches so a sale demonstrates nearest-expiry-first.
    await api.tryInsert('stock_batches', {
      'branch_id': branchId,
      'medicine_id': medicineId,
      'batch_no': 'DS-${dateIn(400).replaceAll('-', '')}-$medicineCount',
      'expiry_date': dateIn(400),
      'quantity': 40,
      'initial_quantity': 40,
      'cost_price': cost,
      'supplier_id': supplierId,
      'is_active': true,
    });
    await api.tryInsert('stock_batches', {
      'branch_id': branchId,
      'medicine_id': medicineId,
      'batch_no': 'DS-${dateIn(760).replaceAll('-', '')}-$medicineCount',
      'expiry_date': dateIn(760),
      'quantity': 60,
      'initial_quantity': 60,
      'cost_price': cost,
      'supplier_id': supplierId,
      'is_active': true,
    });
  }
  stdout.writeln('Medicines: $medicineCount with two batches each');

  // One expired batch on a dedicated medicine for the smoke test's expired
  // stock rule. Its id is printed so the owner can pass it as
  // SMOKE_EXPIRED_BATCH_ID.
  var expiredMedicine = await api.select('medicines', columns: 'id', filters: {
    'name': 'eq.Demo Expired Stock',
  });
  if (expiredMedicine.isEmpty) {
    await api.tryInsert('medicines', {
      'name': 'Demo Expired Stock',
      'generic_name': 'Seed fixture',
      'cost_price': 1,
      'selling_price': 2,
      'is_active': true,
    });
    expiredMedicine = await api.select('medicines', columns: 'id', filters: {
      'name': 'eq.Demo Expired Stock',
    });
  }
  if (expiredMedicine.isNotEmpty) {
    final id = expiredMedicine.first['id'] as String;
    var expiredBatch = await api.select('stock_batches', columns: 'id', filters: {
      'medicine_id': 'eq.$id',
      'batch_no': 'eq.EXPIRED-DEMO',
    });
    if (expiredBatch.isEmpty) {
      await api.tryInsert('stock_batches', {
        'branch_id': branchId,
        'medicine_id': id,
        'batch_no': 'EXPIRED-DEMO',
        'expiry_date': dateIn(-30),
        'quantity': 10,
        'initial_quantity': 10,
        'cost_price': 1,
        'supplier_id': supplierId,
        'is_active': true,
      });
      expiredBatch = await api.select('stock_batches', columns: 'id', filters: {
        'medicine_id': 'eq.$id',
        'batch_no': 'eq.EXPIRED-DEMO',
      });
    }
    if (expiredBatch.isNotEmpty) {
      stdout.writeln('Expired fixture batch id: ${expiredBatch.first['id']}');
      stdout.writeln('  → set SMOKE_EXPIRED_BATCH_ID to this value when running smoke_test.dart');
    }
  }

  stdout.writeln('');
  stdout.writeln('Seed complete. No secrets were written to disk.');
}
