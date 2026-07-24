import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class _PdfFontSet {
  const _PdfFontSet({
    required this.regular,
    required this.bold,
  });

  final pw.Font regular;
  final pw.Font bold;
}

Future<pw.Font?> _loadSystemFont(List<String> candidates) async {
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    return pw.Font.ttf(ByteData.sublistView(bytes));
  }
  return null;
}

Future<_PdfFontSet> _loadPdfFonts() async {
  if (Platform.isWindows) {
    final regular = await _loadSystemFont(const [
      r'C:\Windows\Fonts\arial.ttf',
      r'C:\Windows\Fonts\segoeui.ttf',
    ]);
    final bold = await _loadSystemFont(const [
      r'C:\Windows\Fonts\arialbd.ttf',
      r'C:\Windows\Fonts\segoeuib.ttf',
    ]);

    if (regular != null && bold != null) {
      return _PdfFontSet(regular: regular, bold: bold);
    }
  }

  final regular = await PdfGoogleFonts.robotoRegular();
  final bold = await PdfGoogleFonts.robotoBold();
  return _PdfFontSet(regular: regular, bold: bold);
}

class ReceiptPdfItem {
  const ReceiptPdfItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.baseUnitPrice,
    this.discountPercent,
    this.discountAmount,
    this.totalDiscount,
  });

  final String name;
  final num quantity;
  final num unitPrice;
  final num lineTotal;
  final num? baseUnitPrice;
  final num? discountPercent;
  final num? discountAmount;
  final num? totalDiscount;

  bool get hasDiscount => (totalDiscount ?? 0) > 0;
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
    this.customerName,
    this.previousDebt,
    this.newDebt,
    this.debtAmount,
    this.paidNow,
    this.rightPaddingMm = 24,
    this.documentTitle,
    this.footerText = 'Спасибо за покупку!',
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
  final String? customerName;
  final num? previousDebt;
  final num? newDebt;
  final num? debtAmount;
  final num? paidNow;

  final double rightPaddingMm;
  final String? documentTitle;
  final String footerText;
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
    required this.creditTotal,
    required this.grandTotal,
    required this.refundsTotal,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.expectedCashAmount,
    required this.items,
    this.reportTitle = 'Z-ОТЧЕТ',
    this.reportSubtitle = 'Закрытие смены',
    this.footerText = 'Смена успешно закрыта',
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
  final num creditTotal;
  final num grandTotal;
  final num refundsTotal;
  final num incomeTotal;
  final num expenseTotal;
  final num expectedCashAmount;
  final List<ReceiptPdfItem> items;
  final String reportTitle;
  final String reportSubtitle;
  final String footerText;
}

class InvoicePdfData {
  const InvoicePdfData({
    required this.money,
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.cashierName,
    required this.storeName,
    required this.items,
    required this.total,
    required this.paymentMethodLabel,
    this.discountSum = 0,
    this.buyerName = '',
    this.ndsAmount,
    this.amountInWords = '',
  });

  final String Function(num) money;
  final DateTime invoiceDate;
  final String invoiceNumber;
  final String cashierName;
  final String storeName;
  final List<ReceiptPdfItem> items;
  final num total;
  final num discountSum;
  final String paymentMethodLabel;
  final String buyerName;
  final num? ndsAmount;
  final String amountInWords;
}

String formatReceiptDate(DateTime dt) {
  final d = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String formatPosReceiptNumber({
  required String posNumber,
  required String saleNumber,
  String fallback = '',
}) {
  final existing = saleNumber.trim();
  if (existing.contains('-')) return existing;

  final rawLocal = existing.isNotEmpty ? existing : fallback.trim();
  final localDigits = rawLocal.replaceAll(RegExp(r'\D'), '');
  if (localDigits.isEmpty) return rawLocal;

  final rawPos = posNumber.trim();
  if (rawPos.isEmpty) return localDigits.padLeft(9, '0');

  final posDigits = rawPos.replaceAll(RegExp(r'\D'), '');
  final posPart = posDigits.isEmpty ? rawPos : posDigits.padLeft(3, '0');
  return '$posPart-${localDigits.padLeft(9, '0')}';
}

String _fmtDateRu(DateTime dt) {
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  final d = dt.toLocal();
  return '${d.day} ${months[d.month - 1]} ${d.year} г.';
}

Future<pw.Document> buildReceiptPdf(ReceiptPdfData data) async {
  final fonts = await _loadPdfFonts();
  final base = fonts.regular;
  final bold = fonts.bold;
  final doc = pw.Document();

  const storeFs = 9.4;
  const metaFs = 7.6;
  const itemFs = 7.6;
  const totalFs = 8.8;
  const footerFs = 8.0;
  const titleFs = 8.4;

  pw.Widget rowKV(
    String key,
    String value, {
    bool strong = false,
    bool boldText = false,
    double fs = itemFs,
  }) {
    final effectiveFs = strong && fs == itemFs ? totalFs : fs;
    final style = pw.TextStyle(
      font: boldText ? bold : base,
      fontSize: effectiveFs,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Text(key, style: style)),
        pw.SizedBox(width: 8),
        pw.Text(value, style: style, textAlign: pw.TextAlign.right),
      ],
    );
  }

  pw.Widget divider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.LayoutBuilder(
          builder: (context, constraints) {
            const dashWidth = 4.0;
            const dashGap = 2.0;
            const thickness = 0.4;

            final width = constraints!.maxWidth;
            final dashCount = (width / (dashWidth + dashGap)).floor();

            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: List.generate(dashCount, (_) {
                return pw.Container(
                  width: dashWidth,
                  height: thickness,
                  color: PdfColors.grey700,
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
            if ((data.documentTitle ?? '').trim().isNotEmpty) ...[
              pw.Text(
                data.documentTitle!.trim(),
                style: pw.TextStyle(font: bold, fontSize: titleFs),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 4),
            ],
            pw.Text(
              data.storeName,
              style: pw.TextStyle(font: base, fontSize: storeFs),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Дата: ${formatReceiptDate(data.receiptDate)}',
              style: pw.TextStyle(font: base, fontSize: metaFs),
            ),
            if (data.receiptNumber.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'Чек №: ${data.receiptNumber.trim()}',
                style: pw.TextStyle(font: base, fontSize: metaFs),
              ),
            ],
            pw.SizedBox(height: 2),
            pw.Text(
              'Кассир: ${data.cashierName}',
              style: pw.TextStyle(font: base, fontSize: metaFs),
            ),
            if ((data.customerName ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'Клиент: ${data.customerName!.trim()}',
                style: pw.TextStyle(font: base, fontSize: metaFs),
              ),
            ],
            divider(),
            for (final it in data.items) ...[
              pw.Text(it.name,
                  style: pw.TextStyle(font: base, fontSize: itemFs)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${data.money(it.baseUnitPrice ?? it.unitPrice)} x ${it.quantity}'
                      '  скидка ${(it.discountPercent ?? 0) > 0 ? '${it.discountPercent!.toStringAsFixed(it.discountPercent! % 1 == 0 ? 0 : 1)}%' : '0%'}',
                      style: pw.TextStyle(font: base, fontSize: itemFs),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text(
                    '=${data.money(it.lineTotal)}',
                    style: pw.TextStyle(font: base, fontSize: itemFs),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
            ],
            divider(),
            rowKV(
              'ИТОГ',
              data.money(data.total),
              strong: true,
              boldText: true,
            ),
            if (data.isCashPayment) ...[
              pw.SizedBox(height: 3),
              rowKV('Получено', data.money(data.received ?? 0)),
              rowKV('Сдача', data.money(data.change ?? 0), strong: true),
            ],
            if (data.debtAmount != null) ...[
              pw.SizedBox(height: 3),
              rowKV('Оплачено сейчас', data.money(data.paidNow ?? 0)),
              rowKV('В долг', data.money(data.debtAmount ?? 0), strong: true),
            ],
            if (data.previousDebt != null || data.newDebt != null) ...[
              pw.SizedBox(height: 3),
              rowKV('Предыдущий долг', data.money(data.previousDebt ?? 0)),
              rowKV('Новый долг', data.money(data.newDebt ?? 0), strong: true),
            ],
            pw.SizedBox(height: 4),
            rowKV('Метод', data.paymentMethodLabel),
            pw.SizedBox(height: 6),
            pw.Text(
              data.footerText,
              style: pw.TextStyle(font: base, fontSize: footerFs),
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

Future<pw.Document> buildInvoicePdf(InvoicePdfData data) async {
  final fonts = await _loadPdfFonts();
  final base = fonts.regular;
  final bold = fonts.bold;

  const labelColor = PdfColor.fromInt(0xFF1155BB);
  const borderColor = PdfColor.fromInt(0xFF888888);
  const cellPad = pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4);
  const fs = 9.0;

  pw.Widget cell(
    String text, {
    bool isBold = false,
    pw.Alignment align = pw.Alignment.centerLeft,
    PdfColor? bg,
  }) {
    return pw.Container(
      color: bg,
      padding: cellPad,
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: isBold ? bold : base, fontSize: fs),
      ),
    );
  }

  pw.Widget infoRow(String label, String value, {bool valueBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: base, fontSize: fs, color: labelColor),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: valueBold ? bold : base, fontSize: fs),
            ),
          ),
        ],
      ),
    );
  }

  final nds = data.ndsAmount ?? 0;
  final tableBorder = pw.TableBorder.all(color: borderColor, width: 0.5);
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(20, 20, 20, 20),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Расходная накладная № ${data.invoiceNumber} от ${_fmtDateRu(data.invoiceDate)}',
            style: pw.TextStyle(font: bold, fontSize: 11),
          ),
          pw.Container(
            height: 0.8,
            color: PdfColors.black,
            margin: const pw.EdgeInsets.symmetric(vertical: 4),
          ),
          infoRow('Продавец', data.storeName),
          infoRow(
            'Покупатель',
            data.buyerName.trim().isEmpty ? 'Без указания' : data.buyerName,
          ),
          infoRow('Кассир', data.cashierName, valueBold: true),
          infoRow('Оплата', data.paymentMethodLabel, valueBold: true),
          pw.SizedBox(height: 8),
          pw.Table(
            border: tableBorder,
            columnWidths: const {
              0: pw.FixedColumnWidth(30),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(65),
              3: pw.FixedColumnWidth(65),
              4: pw.FixedColumnWidth(55),
              5: pw.FixedColumnWidth(72),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF5F5F5),
                ),
                children: [
                  cell('№', isBold: true, align: pw.Alignment.center),
                  cell('Товар', isBold: true, align: pw.Alignment.center),
                  cell('Цена', isBold: true, align: pw.Alignment.center),
                  cell('Количество', isBold: true, align: pw.Alignment.center),
                  cell('Скидка', isBold: true, align: pw.Alignment.center),
                  cell('Итого', isBold: true, align: pw.Alignment.center),
                ],
              ),
              for (var i = 0; i < data.items.length; i++)
                pw.TableRow(
                  children: [
                    cell('${i + 1}', align: pw.Alignment.center),
                    cell(data.items[i].name),
                    cell(
                      data.money(
                        data.items[i].baseUnitPrice ?? data.items[i].unitPrice,
                      ),
                      align: pw.Alignment.centerRight,
                    ),
                    cell(
                      '${data.items[i].quantity % 1 == 0 ? data.items[i].quantity.toInt() : data.items[i].quantity} шт.',
                      align: pw.Alignment.center,
                    ),
                    cell(
                      (data.items[i].discountPercent ?? 0) > 0
                          ? '${(data.items[i].discountPercent ?? 0).toStringAsFixed((data.items[i].discountPercent ?? 0) % 1 == 0 ? 0 : 1)}%'
                          : '0%',
                      align: pw.Alignment.center,
                    ),
                    cell(
                      data.money(data.items[i].lineTotal),
                      align: pw.Alignment.centerRight,
                    ),
                  ],
                ),
              if (data.items.isEmpty)
                pw.TableRow(
                  children: [
                    cell(''),
                    cell(''),
                    cell(''),
                    cell(''),
                    cell(''),
                    cell(''),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      'Итого:',
                      style: pw.TextStyle(font: bold, fontSize: fs),
                    ),
                    pw.SizedBox(width: 30),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(
                        data.money(data.total),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(font: bold, fontSize: fs),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      'В том числе НДС:',
                      style: pw.TextStyle(font: bold, fontSize: fs),
                    ),
                    pw.SizedBox(width: 30),
                    pw.SizedBox(
                      width: 80,
                      child: pw.Text(
                        data.money(nds),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(font: bold, fontSize: fs),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Всего наименований ${data.items.length}, на сумму ${data.money(data.total)}',
            style: pw.TextStyle(
              font: base,
              fontSize: fs,
              color: labelColor,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          if (data.amountInWords.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              data.amountInWords,
              style: pw.TextStyle(font: bold, fontSize: fs),
            ),
          ],
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    'Отпустил',
                    style: pw.TextStyle(font: base, fontSize: 10),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(width: 130, height: 0.5, color: PdfColors.black),
                  pw.Text('  /', style: pw.TextStyle(font: base, fontSize: 10)),
                ],
              ),
              pw.Row(
                children: [
                  pw.Text(
                    'Получил',
                    style: pw.TextStyle(font: base, fontSize: 10),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(width: 130, height: 0.5, color: PdfColors.black),
                  pw.Text('  /', style: pw.TextStyle(font: base, fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );

  return doc;
}

Future<pw.Document> buildShiftReportPdf(ShiftReportPdfData data) async {
  final fonts = await _loadPdfFonts();
  final base = fonts.regular;
  final bold = fonts.bold;
  final doc = pw.Document();

  pw.Widget divider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.LayoutBuilder(
          builder: (context, constraints) {
            const dashWidth = 4.0;
            const dashGap = 2.0;
            const thickness = 0.4;

            final width = constraints!.maxWidth;
            final dashCount = (width / (dashWidth + dashGap)).floor();

            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: List.generate(dashCount, (_) {
                return pw.Container(
                  width: dashWidth,
                  height: thickness,
                  color: PdfColors.grey700,
                );
              }),
            );
          },
        ),
      );

  pw.Widget kv(String left, String right,
      {bool strong = false, double fs = 7}) {
    final style = pw.TextStyle(
      font: strong ? bold : base,
      fontSize: fs,
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
      orientation: pw.PageOrientation.portrait,
      margin: const pw.EdgeInsets.only(
        right: 24,
        top: 12,
        bottom: 12,
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            data.storeName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: base, fontSize: 9),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            data.reportTitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 9),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            data.reportSubtitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: base, fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Дата закрытия: ${data.closedAt == null ? '-' : formatReceiptDate(data.closedAt!)}',
            style: pw.TextStyle(font: base, fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Смена №: ${data.sessionId}',
            style: pw.TextStyle(font: base, fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Кассир: ${data.cashierName}',
            style: pw.TextStyle(font: base, fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Касса: ${data.posName}',
            style: pw.TextStyle(font: base, fontSize: 7),
          ),
          divider(),
          kv(
            'Открытие смены',
            data.openedAt == null ? '-' : formatReceiptDate(data.openedAt!),
          ),
          kv(
            'Закрытие смены',
            data.closedAt == null ? '-' : formatReceiptDate(data.closedAt!),
          ),
          divider(),
          pw.Text(
            'Проданные товары',
            style: pw.TextStyle(font: bold, fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          if (data.items.isEmpty)
            pw.Text(
              'Нет проданных товаров',
              style: pw.TextStyle(font: base, fontSize: 7),
            ),
          for (final item in data.items) ...[
            pw.Text(item.name, style: pw.TextStyle(font: base, fontSize: 7)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${item.quantity} шт.',
                  style: pw.TextStyle(font: base, fontSize: 7),
                ),
                pw.SizedBox(width: 10),
                pw.Text(
                  data.money(item.lineTotal),
                  style: pw.TextStyle(font: base, fontSize: 7),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
          ],
          divider(),
          kv('Количество чеков', '${data.salesCount}'),
          kv('Наличные', data.money(data.cashTotal)),
          kv('Карта', data.money(data.cardTotal)),
          kv('Перевод', data.money(data.transferTotal)),
          kv('В долг', data.money(data.creditTotal)),
          divider(),
          kv('ИТОГ', data.money(data.grandTotal), strong: true),
          divider(),
          kv('Наличные при открытии', data.money(data.openingCashAmount)),
          kv('Возвраты', data.money(data.refundsTotal)),
          kv('Приход в кассу', data.money(data.incomeTotal)),
          kv('Расход из кассы', data.money(data.expenseTotal)),
          divider(),
          kv(
            'Должно быть в кассе',
            data.money(data.expectedCashAmount),
            strong: true,
          ),
          if (data.closedAt != null) ...[
            kv(
              'Фактически в кассе',
              data.money(data.closingCashAmount),
            ),
            kv(
              'Разница',
              data.money(data.closingCashAmount - data.expectedCashAmount),
              strong: true,
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Text(
            data.footerText,
            style: pw.TextStyle(font: base, fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 35 * PdfPageFormat.mm),
        ],
      ),
    ),
  );

  return doc;
}
