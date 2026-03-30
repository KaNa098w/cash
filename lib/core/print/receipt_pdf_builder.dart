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

class ShiftReportPdfData {
  const ShiftReportPdfData({
    required this.pageFormat,
    required this.money,
    required this.storeName,
    required this.posName,
    required this.cashierName,
    required this.sessionId,
    required this.openedAt,
    required this.closedAt,
    required this.openingCashAmount,
    required this.closingCashAmount,
    required this.salesCount,
    required this.cashTotal,
    required this.cardTotal,
    required this.transferTotal,
    required this.grandTotal,
    required this.items,
  });

  final PdfPageFormat pageFormat;
  final String Function(num) money;
  final String storeName;
  final String posName;
  final String cashierName;
  final String sessionId;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final num openingCashAmount;
  final num closingCashAmount;
  final int salesCount;
  final num cashTotal;
  final num cardTotal;
  final num transferTotal;
  final num grandTotal;
  final List<ReceiptPdfItem> items;
}

String formatReceiptDate(DateTime dt) {
  final d = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Future<pw.Document> buildReceiptPdf(ReceiptPdfData data) async {
  final base = await PdfGoogleFonts.robotoRegular();

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
              data.storeName,
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

Future<pw.Document> buildShiftReportPdf(ShiftReportPdfData data) async {
  final base = await PdfGoogleFonts.robotoRegular();
  final bold = await PdfGoogleFonts.robotoBold();

  final doc = pw.Document();

  pw.Widget divider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 4),
        height: 0.6,
        color: PdfColors.grey600,
      );

  pw.Widget kv(String left, String right, {bool strong = false}) {
    final style = pw.TextStyle(
      font: strong ? bold : base,
      fontSize: 8,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Text(left, style: style)),
        pw.SizedBox(width: 8),
        pw.Text(right, style: style, textAlign: pw.TextAlign.right),
      ],
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: data.pageFormat,
      margin: const pw.EdgeInsets.fromLTRB(10, 12, 18, 12),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Z-OTCHET (Zakrytie smeny)',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 10),
          ),
          divider(),
          kv('Magazin:', data.storeName),
          kv('Kassa:', data.posName),
          kv('Kassir:', data.cashierName),
          kv('Smena:', '#${data.sessionId}'),
          divider(),
          kv('Otkrytie:', data.openedAt == null ? '-' : formatReceiptDate(data.openedAt!)),
          kv('Zakrytie:', data.closedAt == null ? '-' : formatReceiptDate(data.closedAt!)),
          divider(),
          pw.Text('N  Tovar', style: pw.TextStyle(font: bold, fontSize: 8)),
          pw.SizedBox(height: 2),
          for (var i = 0; i < data.items.length; i++) ...[
            pw.Text(
              '${i + 1}. ${data.items[i].name}',
              style: pw.TextStyle(font: base, fontSize: 8),
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Kol: ${data.items[i].quantity}',
                  style: pw.TextStyle(font: base, fontSize: 7),
                ),
                pw.Text(
                  data.money(data.items[i].lineTotal),
                  style: pw.TextStyle(font: base, fontSize: 7),
                ),
              ],
            ),
            pw.SizedBox(height: 3),
          ],
          divider(),
          kv('Kol-vo prodazh:', '${data.salesCount}'),
          kv('Nalichnye:', data.money(data.cashTotal)),
          kv('Karta:', data.money(data.cardTotal)),
          kv('Perevod:', data.money(data.transferTotal)),
          divider(),
          kv('ITOGO:', data.money(data.grandTotal), strong: true),
          divider(),
          kv('Nalichnye pri otkrytii:', data.money(data.openingCashAmount)),
          kv('Nalichnye pri zakrytii:', data.money(data.closingCashAmount)),
          kv(
            'Raznitsa:',
            data.money(data.closingCashAmount - data.openingCashAmount),
            strong: true,
          ),
          pw.SizedBox(height: 24 * PdfPageFormat.mm),
        ],
      ),
    ),
  );

  return doc;
}
