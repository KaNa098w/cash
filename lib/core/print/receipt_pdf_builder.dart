import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReceiptPdfItem {
  const ReceiptPdfItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.discountPercent,
  });

  final String name;
  final num quantity;
  final num unitPrice;
  final num lineTotal;
  final num? discountPercent;
}

class ReceiptPdfData {
  const ReceiptPdfData({
    required this.pageFormat,
    required this.money,
    required this.receiptDate,
    required this.receiptNumber,
    required this.cashierName,
    required this.storeName,
    required this.items,
    required this.total,
    required this.paymentMethodLabel,
    required this.isCashPayment,
    this.discountSum = 0,
    this.received,
    this.change,
    this.title = 'ЧЕК',
    this.rightPaddingMm = 24,
  });

  final PdfPageFormat pageFormat;
  final String Function(num) money;

  final DateTime receiptDate;
  final String receiptNumber;
  final String cashierName;
  final String storeName;

  final List<ReceiptPdfItem> items;
  final num total;
  final num discountSum;

  final String paymentMethodLabel;
  final bool isCashPayment;
  final num? received;
  final num? change;

  final String title;
  final double rightPaddingMm;
}

String formatReceiptDate(DateTime dt) {
  final d = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Future<pw.Document> buildReceiptPdf(ReceiptPdfData data) async {
  final base = await PdfGoogleFonts.robotoRegular();
  final bold = await PdfGoogleFonts.robotoBold();
  final mono = await PdfGoogleFonts.robotoMonoRegular();

  final doc = pw.Document();

  pw.Widget rowKV(String k, String v, {bool strong = false, double fs = 7}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(
            k,
            style: pw.TextStyle(font: base, fontSize: fs),
          ),
        ),
        pw.Text(
          v,
          style: pw.TextStyle(font: base, fontSize: fs),
        ),
      ],
    );
  }

  pw.Widget divider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.LayoutBuilder(
          builder: (context, constraints) {
            const dashWidth = 4.0; // длина штриха
            const dashGap = 2.0; // расстояние между штрихами
            const thickness = 0.4; // толщина (уменьшил)

            final width = constraints!.maxWidth;
            final dashCount = (width / (dashWidth + dashGap)).floor();

            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: List.generate(dashCount, (_) {
                return pw.Container(
                  width: dashWidth,
                  height: thickness,
                  color: PdfColors.grey700, // можешь сделать lighter/darker
                );
              }),
            );
          },
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: data.pageFormat,
      orientation: pw.PageOrientation.portrait,
      margin: pw.EdgeInsets.only(
        right: data.rightPaddingMm,
        top: 12,
        bottom: 12,
      ),
      build: (_) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '${data.storeName}',
              style: pw.TextStyle(font: base, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Дата: ${formatReceiptDate(data.receiptDate)}',
              style: pw.TextStyle(font: base, fontSize: 7),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Чек №: ${data.receiptNumber}',
              style: pw.TextStyle(font: base, fontSize: 7),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Кассир: ${data.cashierName}',
              style: pw.TextStyle(font: base, fontSize: 7),
            ),
            divider(),
            for (final it in data.items) ...[
              pw.Text(it.name, style: pw.TextStyle(font: base, fontSize: 7)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${it.quantity} x ${data.money(it.unitPrice)}'
                    '${(it.discountPercent ?? 0) > 0 ? '  (-${it.discountPercent!.toStringAsFixed(0)}%)' : ''}',
                    style: pw.TextStyle(font: base, fontSize: 7),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    data.money(it.lineTotal),
                    style: pw.TextStyle(font: base, fontSize: 7),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
            ],
            divider(),
            if (data.discountSum > 0) ...[
              rowKV('Без скидок', data.money(data.total + data.discountSum)),
              rowKV('Скидка', data.money(data.discountSum)),
            ],
            rowKV('ИТОГО', data.money(data.total), strong: true),
            if (data.isCashPayment) ...[
              pw.SizedBox(height: 3),
              rowKV('Получено', data.money(data.received ?? 0)),
              rowKV('Сдача', data.money((data.change ?? 0)), strong: true),
            ],
            pw.SizedBox(height: 4),
            rowKV('Метод', data.paymentMethodLabel),
            pw.SizedBox(height: 6),
            pw.Text(
              'Спасибо за покупку!',
              style: pw.TextStyle(font: base, fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 35 * PdfPageFormat.mm),
          ],
        );
      },
    ),
  );

  return doc;
}
