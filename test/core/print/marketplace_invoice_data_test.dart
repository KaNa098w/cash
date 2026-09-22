import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/core/print/marketplace_invoice_data.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';

MarketplaceOrder order(List<Map<String, dynamic>> items, {Object? total}) =>
    MarketplaceOrder.fromJson({
      'id': 'order-1',
      'number': 'MP-123',
      'createdAt': '2026-09-19T12:00:00',
      'status': 'processing',
      'customer': {'name': 'Покупатель'},
      'items': items,
      if (total != null) 'total': total,
    });

InvoicePdfData invoice(MarketplaceOrder order) =>
    marketplaceInvoiceData(order, cashierName: 'Кассир', storeName: 'Магазин');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses decimal quantities and money objects and keeps row totals', () {
    final value = order([
      {
        'name': 'Молоко',
        'qty': '2,5',
        'price': {'amount': 12345, 'precision': 2}
      },
      {'name': 'Хлеб', 'quantity': 2, 'unitPrice': 100, 'lineTotal': 150},
    ]);
    final data = invoice(value);
    expect(value.groupedItems.first.remainingQuantity, 2.5);
    expect(data.items.first.quantity, 2.5);
    expect(data.items.first.unitPrice, 123.45);
    expect(data.items.first.lineTotal, 308.63);
    expect(data.items.last.discountPercent, 25);
    expect(data.total, 458.63);
  });

  test('explicit zero totals are preserved for free items and orders', () {
    final value = order([
      {'name': 'Подарок', 'quantity': 2, 'price': 100, 'total': 0},
    ], total: 0);
    expect(value.displayTotal, 0);
    final data = invoice(value);
    expect(data.items.single.lineTotal, 0);
    expect(data.items.single.discountPercent, 100);
    expect(data.total, 0);
  });

  test('all money aliases handle precision and a missing price is derived', () {
    for (final key in [
      'total',
      'lineTotal',
      'line_total',
      'totalAmount',
      'total_amount',
      'totalPrice',
      'total_price'
    ]) {
      final data = invoice(order([
        {
          'name': 'Товар',
          'requested_quantity': 3,
          key: {'amount': 90075, 'precision': 2}
        },
      ]));
      expect(data.items.single.lineTotal, 900.75, reason: key);
      expect(data.items.single.unitPrice, 300.25, reason: key);
    }
  });

  test('accepts formatted numeric strings', () {
    final data = invoice(order([
      {'name': 'Товар', 'quantity': 2, 'unitPrice': '1\u00a0234,50'},
    ]));
    expect(data.total, 2469);
  });

  test('rejects missing quantities and empty invoices', () {
    expect(() => invoice(order([])), throwsStateError);
    expect(
        () => invoice(order([
              {'name': 'Товар', 'price': 100}
            ])),
        throwsStateError);
  });

  test('invoice keeps full order quantity and separates order adjustments',
      () async {
    final value = order([
      {
        'name': 'Молоко',
        'requestedQuantity': 3,
        'shippedQuantity': 1,
        'price': 100,
        'total': 270
      },
      {'name': 'Подарок', 'quantity': 1, 'price': 50, 'total': 0},
    ], total: {
      'amount': 32000,
      'precision': 2
    });
    final data = invoice(value);
    expect(data.items.first.quantity, 3);
    expect(data.items.first.discountPercent, 10);
    expect(data.total, 270);
    expect(data.orderTotal, 320);
    final doc = await buildInvoicePdf(data);
    final bytes = await doc.save();
    expect(doc.document.pdfPageList.pages.length, 1);
    final output = Platform.environment['INVOICE_QA_OUTPUT'];
    if (output != null) {
      await Directory(output).create(recursive: true);
      await File('$output/marketplace.pdf').writeAsBytes(bytes);
    }
  });
}
