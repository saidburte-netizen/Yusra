import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/strings.dart';
import '../data/purchasing.dart' as purchase;
import '../../suppliers/data/suppliers.dart';

/// Branded purchase order and goods received note PDFs (B11/B12).
abstract final class PurchaseDocuments {
  static pw.Widget _header(String title, String subtitle) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(S.appName,
              style:
                  const pw.TextStyle(fontSize: 20, color: PdfColors.pink800)),
          pw.Text(S.tagline, style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(color: PdfColor.fromHex('#A8841F')),
          pw.Text(title, style: const pw.TextStyle(fontSize: 15)),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 10),
        ],
      );

  static Future<void> printOrder({
    required purchase.PurchaseOrder order,
    required Supplier? supplier,
    required List<purchase.PurchaseOrderItem> items,
    bool goodsReceivedNote = false,
  }) async {
    final document = pw.Document();
    const currency = 'ETB ';
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(
            goodsReceivedNote ? 'Goods received note' : 'Purchase order',
            '${order.poNo}   •   ${order.status.toUpperCase()}',
          ),
          pw.Text('Supplier: ${supplier?.name ?? '—'}'),
          if (supplier?.address != null) pw.Text(supplier!.address!),
          if (supplier?.tin != null) pw.Text('TIN: ${supplier!.tin}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Medicine',
              'Ordered',
              'Received',
              'Unit cost',
              'Line total'
            ],
            data: [
              for (final item in items)
                [
                  item.medicineName,
                  '${item.quantityOrdered}',
                  '${item.quantityReceived}',
                  '$currency${item.unitCost.toStringAsFixed(2)}',
                  '$currency${item.lineTotal.toStringAsFixed(2)}',
                ],
            ],
            border: pw.TableBorder.all(color: PdfColors.grey400),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.pink50),
            headerStyle: const pw.TextStyle(fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                    'Subtotal: $currency${order.subtotal.toStringAsFixed(2)}'),
                pw.Text('Tax: $currency${order.tax.toStringAsFixed(2)}'),
                pw.Text('Total: $currency${order.total.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          if (order.notes != null && order.notes!.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('Notes: ${order.notes}'),
          ],
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Prepared by: ________________'),
              pw.Text('Received by: ________________'),
            ],
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: goodsReceivedNote
          ? 'yusra-grn-${order.poNo}.pdf'
          : 'yusra-po-${order.poNo}.pdf',
    );
  }
}
