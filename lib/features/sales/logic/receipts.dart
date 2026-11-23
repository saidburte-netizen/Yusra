// 80 mm thermal-friendly documents for the POS, returns and shift reports.
// Uses the mono cross mark so it prints cleanly on a receipt printer.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../data/sales.dart';

abstract final class Receipts {
  static pw.Widget get _monoLogo => pw.Container(
        width: 34,
        height: 34,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border.all(color: PdfColors.black, width: 1),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text('+',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _shop(ReceiptSettings s) => pw.Column(
        children: [
          _monoLogo,
          pw.SizedBox(height: 4),
          pw.Text(s.pharmacyName,
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text(s.tagline, style: const pw.TextStyle(fontSize: 8)),
          if (s.address.isNotEmpty)
            pw.Text(s.address, style: const pw.TextStyle(fontSize: 7)),
          if (s.phone.isNotEmpty)
            pw.Text('Tel: ${s.phone}', style: const pw.TextStyle(fontSize: 7)),
          if (s.tin.isNotEmpty)
            pw.Text('TIN: ${s.tin}', style: const pw.TextStyle(fontSize: 7)),
          if (s.licenseNo.isNotEmpty)
            pw.Text('Licence: ${s.licenseNo}',
                style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 4),
          pw.Divider(color: PdfColors.black),
        ],
      );

  static Future<void> printSale({
    required Sale sale,
    required List<SaleItem> items,
    required List<SalePayment> payments,
    required ReceiptSettings settings,
    required String cashierName,
    bool reprint = false,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: _paper,
        margin: const pw.EdgeInsets.all(8),
        build: (_) => [
          _shop(settings),
          pw.SizedBox(height: 4),
          pw.Text('INVOICE ${sale.invoiceNo}',
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              '${sale.createdAt == null ? '' : formatDateTime(sale.createdAt!)}   $cashierName',
              style: const pw.TextStyle(fontSize: 7)),
          if (reprint)
            pw.Text('REPRINT', style: const pw.TextStyle(fontSize: 7)),
          if (sale.status != 'completed')
            pw.Text('STATUS: ${sale.status.toUpperCase()}',
                style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(color: PdfColors.black),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty', 'Price', 'Total'],
            data: [
              for (final item in items)
                [
                  item.medicineName,
                  '${item.quantity}',
                  formatMoney(item.unitPrice),
                  formatMoney(item.lineTotal),
                ],
            ],
            headerStyle:
                pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerRight,
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.Divider(color: PdfColors.black),
          _row('Subtotal', sale.subtotal),
          _row('VAT', sale.tax),
          _row('Discount', -sale.discount),
          pw.SizedBox(height: 2),
          _row('TOTAL', sale.total, bold: true),
          pw.Divider(color: PdfColors.black),
          ...[
            for (final payment in payments)
              _row(
                payment.reference != null && payment.reference!.isNotEmpty
                    ? '${_methodLabel(payment.method)} (${payment.reference})'
                    : _methodLabel(payment.method),
                payment.amount,
              ),
          ],
          _row('Change', sale.changeDue),
          pw.SizedBox(height: 8),
          pw.Text(settings.footer,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'Yusra receipt ${sale.invoiceNo}',
    );
  }

  static Future<void> printReturnNote({
    required String returnNo,
    required String invoiceNo,
    required DateTime createdAt,
    required String reason,
    required String refundMethod,
    required double amount,
    required ReceiptSettings settings,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: _paper,
        margin: const pw.EdgeInsets.all(8),
        build: (_) => [
          _shop(settings),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('RETURN NOTE $returnNo',
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Original invoice: $invoiceNo',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text(formatDateTime(createdAt),
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Reason: $reason', style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Refund: ${_methodLabel(refundMethod)}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(color: PdfColors.black),
          _row('REFUND AMOUNT', amount, bold: true),
          pw.SizedBox(height: 10),
          pw.Text(settings.footer,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(), name: 'Yusra return $returnNo');
  }

  /// X report (during a shift) and Z report (at close).
  static Future<void> printShiftReport({
    required String title,
    required ReceiptSettings settings,
    required String branchName,
    required String cashierName,
    required Shift shift,
    required int saleCount,
    required Map<String, double> byMethod,
    required double expectedCash,
    double? closingCash,
    double? difference,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: _paper,
        margin: const pw.EdgeInsets.all(8),
        build: (_) => [
          _shop(settings),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('$title REPORT',
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Branch: $branchName',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Cashier: $cashierName',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
              'Opened: ${shift.openedAt == null ? '' : formatDateTime(shift.openedAt!)}',
              style: const pw.TextStyle(fontSize: 8)),
          if (shift.closedAt != null)
            pw.Text('Closed: ${formatDateTime(shift.closedAt!)}',
                style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(color: PdfColors.black),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Invoices: $saleCount',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Opening cash ${formatMoney(shift.openingCash)}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
          ...[
            for (final entry in byMethod.entries)
              _row(_methodLabel(entry.key), entry.value)
          ],
          pw.Divider(color: PdfColors.black),
          _row('Expected cash', expectedCash, bold: true),
          if (closingCash != null) _row('Counted cash', closingCash),
          if (difference != null) _row('Difference', difference, bold: true),
          pw.SizedBox(height: 10),
          pw.Text('Certified by: ________________',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(), name: 'Yusra $title report');
  }

  static PdfPageFormat get _paper => const PdfPageFormat(
        80 * PdfPageFormat.mm,
        200 * PdfPageFormat.mm,
        marginAll: 3 * PdfPageFormat.mm,
      );

  static pw.Widget _row(String label, double value, {bool bold = false}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: bold ? 9 : 8,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(formatMoney(value),
              style: pw.TextStyle(
                  fontSize: bold ? 9 : 8,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );

  static String _methodLabel(String method) => switch (method) {
        'cash' => 'Cash',
        'mobile_money' => 'Mobile banking',
        'card' => 'Card',
        'bank_transfer' => 'Bank transfer',
        _ => method,
      };
}
