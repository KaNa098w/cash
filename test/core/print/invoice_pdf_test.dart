import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/features/data/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in InvoicePdfKind.values) {
    for (final count in [3, 100]) {
      test(
          '${kind.name} invoice renders $count rows offline on A4 without overflow',
          () async {
        final items = List.generate(
            count,
            (i) => ReceiptPdfItem(
                  name:
                      'Товар ${i + 1}: Молоко «Солнечное» длительного хранения 3,2%',
                  quantity: 2.5,
                  unitPrice: 1234567.89,
                  baseUnitPrice: 1234567.89,
                  lineTotal: 3086419.725,
                ));
        final doc = await buildInvoicePdf(InvoicePdfData(
          kind: kind,
          money: money,
          invoiceDate: DateTime(2026, 9, 19),
          invoiceNumber: 'ПР-12345',
          cashierName: 'Иван Петров',
          storeName: 'Магазин «Лимон»',
          buyerName: 'ТОО «Покупатель»',
          items: items,
          total: items.fold<num>(0, (sum, item) => sum + item.lineTotal),
          paymentMethodLabel: 'Безналичный',
        ));
        final bytes = await doc.save();
        expect(bytes.length, greaterThan(1000));
        expect(doc.document.pdfPageList.pages.length,
            count == 3 ? 1 : greaterThan(1));
        for (final page in doc.document.pdfPageList.pages) {
          expect(page.pageFormat.width, closeTo(595.28, .1));
          expect(page.pageFormat.height, closeTo(841.89, .1));
        }
        final output = Platform.environment['INVOICE_QA_OUTPUT'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File('$output/${kind.name}-invoice-$count.pdf')
              .writeAsBytes(bytes);
        }
      });
    }
  }
}
