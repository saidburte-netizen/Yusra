import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart'; // ignore: depend_on_referenced_packages
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_models.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/pos/screens/pos_screen.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';

class _FakeAuth extends AuthController {
  _FakeAuth() {
    state = const AuthState(
      status: AuthStatus.authenticated,
      profile: UserProfile(
        id: 'u1',
        email: 'cashier@yusra.test',
        fullName: 'Cashier',
        role: AppRole.cashier,
        isActive: true,
        branchId: 'b1',
      ),
    );
  }

  @override
  Future<void> bootstrap() async {}
}

class _FakeSalesRepo extends SalesRepository {
  bool saleCreated = false;
  String? lastShiftId;
  final List<Map<String, dynamic>> lastItems = [];
  final List<Map<String, dynamic>> lastPayments = [];

  @override
  Future<String> createSale({
    required String branchId,
    required String shiftId,
    String? customerId,
    String? prescriptionId,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    required double discount,
    String? note,
    String? idempotencyKey,
  }) async {
    saleCreated = true;
    lastShiftId = shiftId;
    lastItems
      ..clear()
      ..addAll(items);
    lastPayments
      ..clear()
      ..addAll(payments);
    return 'sale-1';
  }

  @override
  Future<Sale> sale(String id) async => Sale(
        id: id,
        invoiceNo: 'INV-001',
        branchId: 'b1',
        shiftId: 'shift-1',
        cashierId: 'u1',
        status: 'completed',
        subtotal: 12.5,
        total: 12.5,
        discount: 0,
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  Future<List<SaleItem>> saleItems(String saleId) async => const [
        SaleItem(
          id: 'si1',
          saleId: 'sale-1',
          medicineId: 'm1',
          medicineName: 'Amoxicillin 500mg',
          quantity: 1,
          unitPrice: 12.5,
          lineTotal: 12.5,
        ),
      ];

  @override
  Future<List<SalePayment>> salePayments(String saleId) async => const [
        SalePayment(
          id: 'sp1',
          saleId: 'sale-1',
          method: 'cash',
          amount: 12.5,
        ),
      ];
}

class _FakePrinting extends PrintingPlatform with MockPlatformInterfaceMixin {
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(
        canPrint: true,
        canConvertHtml: false,
        canListPrinters: false,
        canShare: false,
        directPrint: false,
        dynamicLayout: false,
        canRaster: false,
      );

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    try {
      await onLayout(format);
    } catch (_) {}
    return true;
  }

  @override
  Future<List<Printer>> listPrinters() async => const [];

  @override
  Future<Printer?> pickPrinter(Rect bounds) async => null;

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async =>
      true;

  @override
  Future<Uint8List> convertHtml(
          String html, String? baseUrl, PdfPageFormat format) async =>
      Uint8List(0);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream<PdfRaster>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrintingPlatform.instance = _FakePrinting();
  });

  tearDown(() {});

  testWidgets('POS: tap stock item, pay cash, sale saved and cart cleared',
      (tester) async {
    final fakeSales = _FakeSalesRepo();
    const medicine = Medicine(
      id: 'm1',
      name: 'Amoxicillin 500mg',
      sku: 'AMX',
      sellingPrice: 12.5,
      costPrice: 8,
      isActive: true,
    );
    const stock = StockSummary(
      branchId: 'b1',
      medicineId: 'm1',
      name: 'Amoxicillin 500mg',
      availableQty: 10,
      reorderLevel: 0,
      sellingPrice: 12.5,
      costPrice: 8,
    );
    final shift = Shift(
      id: 'shift-1',
      branchId: 'b1',
      cashierId: 'u1',
      openedAt: DateTime(2026, 1, 1),
      status: 'open',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuth()),
          salesRepositoryProvider.overrideWithValue(fakeSales),
          myOpenShiftProvider.overrideWith((ref) async => shift),
          receiptSettingsProvider
              .overrideWith((ref) async => const ReceiptSettings(
                    pharmacyName: 'Yusra Pharmacy',
                    tagline: 'Care',
                    address: '',
                    phone: '',
                    tin: '',
                    licenseNo: '',
                    footer: '',
                    vatRate: 0,
                    maxCashierDiscountPct: 100,
                  )),
          posMedicinesProvider.overrideWith((ref) async => [medicine]),
          stockSummaryProvider.overrideWith((ref) async => [stock]),
        ],
        child: const MaterialApp(home: PosScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Medicine is visible
    expect(find.text('Amoxicillin 500mg'), findsWidgets);

    // Tap medicine with stock to add to cart
    await tester.tap(find.text('Amoxicillin 500mg').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap Pay in bottom bar (narrow screen in test default 800x600)
    final payFinder = find.byWidgetPredicate(
      (w) =>
          w is FilledButton &&
          w.child is Text &&
          ((w.child as Text).data ?? '').contains('Pay'),
    );
    expect(payFinder, findsOneWidget);
    await tester.tap(payFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Payment dialog appears; confirm cash payment (pre-filled)
    final confirmFinder = find.byWidgetPredicate(
      (w) =>
          w is ElevatedButton &&
          (w.child is Text
              ? ((w.child as Text).data ?? '').contains('Confirm')
              : false),
    );
    expect(confirmFinder, findsOneWidget);
    await tester.tap(confirmFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Sale saved and cart cleared
    expect(fakeSales.saleCreated, isTrue);
    expect(fakeSales.lastShiftId, 'shift-1');
    expect(fakeSales.lastItems, isNotEmpty);
    // Cart cleared - Pay button should be disabled / cart empty (0 items)
    expect(find.textContaining('Cart (0 items)'), findsOneWidget);
  });
}
