import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/core/print/marketplace_invoice_data.dart';

Map<String, dynamic> money(int amount) =>
    {'amount': amount, 'precision': 2, 'currency': 'KZT'};
Map<String, dynamic> line(String id, int price, int total,
        {int quantity = 1}) =>
    {
      'id': id,
      'requestedQuantity': quantity,
      'price': money(price),
      'totalPrice': money(total),
      'offer': {
        'price': money(999999),
        'productId': 'product-1',
        'product': {'id': 'product-1', 'name': 'Товар'}
      },
    };
Map<String, dynamic> group(List<String> ids, {int quantity = 1}) => {
      'productId': 'product-1',
      'name': 'Товар',
      'requestedQuantity': quantity,
      'confirmedQuantity': quantity,
      'remainingQuantity': quantity,
      'items': ids.map((id) => {'id': id, 'requestedQuantity': 1}).toList(),
    };
void main() {
  final capturedDirectory = Platform.environment['MARKETPLACE_QA_RESPONSES'];
  if (capturedDirectory != null) {
    test('captured backend details agree with raw item snapshot amounts', () {
      for (final file in Directory(capturedDirectory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('-detail.json'))) {
        final body =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final order = MarketplaceOrder.fromJson(body['data'] is Map
            ? Map<String, dynamic>.from(body['data'])
            : body);
        final rawTotal = order.items.whereType<Map>().fold<num>(0, (sum, item) {
          final amount = item['totalPrice'] as Map;
          final precision = amount['precision'] as int;
          var divisor = 1;
          for (var i = 0; i < precision; i++) {
            divisor *= 10;
          }
          return sum + (amount['amount'] as num) / divisor;
        });
        final displayedTotal = order.groupedItems
            .fold<num>(0, (sum, item) => sum + item.lineTotal);
        expect(displayedTotal, rawTotal);
        expect(order.groupedItems.every((item) => item.unitPrice > 0), isTrue);
      }
    });
  }

  test('real response shape joins grouped quantities to order snapshot money',
      () {
    final order = MarketplaceOrder.fromJson({
      'id': 'order-1',
      'number': 36,
      'totalPrice': money(283000),
      'groupedItems': [
        group(['item-1'])
      ],
      'items': [line('item-1', 133000, 133000)],
    });
    final item = order.groupedItems.single;
    expect(item.unitPrice, 1330);
    expect(item.lineTotal, 1330);
    expect(item.confirmedQuantity, 1);
    expect(order.displayTotal, 2830);
    final invoice =
        marketplaceInvoiceData(order, cashierName: '', storeName: '');
    expect(invoice.items.single.lineTotal, 1330);
    expect(invoice.orderTotal, 2830);
  });
  test(
      'history quantity four uses line total instead of unit price or order total',
      () {
    final order = MarketplaceOrder.fromJson({
      'totalPrice': money(1390000),
      'groupedItems': [
        group(['item-1'], quantity: 4)
      ],
      'items': [line('item-1', 310000, 1240000, quantity: 4)],
    });
    expect(order.groupedItems.single.unitPrice, 3100);
    expect(order.groupedItems.single.lineTotal, 12400);
    expect(order.displayTotal, 13900);
  });
  test('multiple members aggregate only matching IDs and preserve discounts',
      () {
    final order = MarketplaceOrder.fromJson({
      'groupedItems': [
        group(['one', 'two'], quantity: 3)
      ],
      'items': [
        line('other', 90000, 90000),
        line('two', 20000, 30000, quantity: 2),
        line('one', 10000, 10000)
      ],
    });
    final item = order.groupedItems.single;
    expect(item.lineTotal, 400);
    expect(item.unitPrice, closeTo(500 / 3, 0.0001));
  });
  test('explicit grouped zero price and total are not replaced', () {
    final order = MarketplaceOrder.fromJson({
      'groupedItems': [
        {
          ...group(['one']),
          'unitPrice': 0,
          'lineTotal': 0
        }
      ],
      'items': [line('one', 10000, 10000)],
    });
    expect(order.groupedItems.single.unitPrice, 0);
    expect(order.groupedItems.single.lineTotal, 0);
  });
  test('unmatched member does not borrow another product price', () {
    final order = MarketplaceOrder.fromJson({
      'groupedItems': [
        group(['missing'])
      ],
      'items': [line('one', 10000, 10000)],
    });
    expect(order.groupedItems.single.unitPrice, 0);
    expect(order.groupedItems.single.hasExplicitTotal, isFalse);
  });
}
