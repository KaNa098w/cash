import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart';

void main() {
  test('sale item preserves original marking data', () {
    final item = SaleItemModel.fromApiJson({
      'id': 'sale-item-1',
      'sale_id': 'sale-1',
      'product_id': 'product-1',
      'quantity': 1,
      'price': 1000,
      'total_price': 1000,
      'mark_codes': ['raw\x1Dcode'],
      'marking_gtin': '04714033305983',
      'marking_ntin': '0200017227494',
      'marking_parts': [
        {
          'code': 'raw\x1Dcode',
          'quantity': 3,
          'package_quantity': 5,
        },
      ],
    });

    expect(item.markCodes, ['raw\x1Dcode']);
    expect(item.markingGtin, '04714033305983');
    expect(item.markingNtin, '0200017227494');
    expect(item.markingParts.single.quantity, 3);
    expect(item.markingParts.single.packageQuantity, 5);
    expect(item.toApiJson()['mark_codes'], ['raw\x1Dcode']);
  });

  test('refund item preserves returned marking codes', () {
    final item = RefundItemModel.fromJson({
      'id': 'refund-item-1',
      'refund_id': 'refund-1',
      'sale_item_id': 'sale-item-1',
      'product_id': 'product-1',
      'quantity': 1,
      'price': 1000,
      'max_quantity': 1,
      'mark_codes': ['raw\x1Dcode'],
      'marking_parts': [
        {
          'code': 'raw\x1Dcode',
          'quantity': 1,
          'package_quantity': 5,
        },
      ],
    });

    expect(item.markCodes, ['raw\x1Dcode']);
    expect(item.markingParts.single.quantity, 1);
    expect(item.toJson()['mark_codes'], ['raw\x1Dcode']);
  });
}
