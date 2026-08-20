import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/utils/sales_filter.dart';

void main() {
  SaleModel sale({
    required String id,
    required int total,
    RefundModel? refund,
  }) {
    return SaleModel(
      localId: id,
      number: id,
      date: DateTime(2026, 8, 20),
      totalAmount: total,
      paymentMethod: 'cash',
      posId: 'pos',
      storeId: 'store',
      userId: 'user',
      accountId: 'account',
      items: const [],
      refund: refund,
    );
  }

  RefundModel refund({
    required String id,
    String? saleId,
    required num total,
  }) {
    return RefundModel(
      id: id,
      saleId: saleId,
      totalAmount: total,
      items: const [],
    );
  }

  group('netSalesTotal', () {
    test('subtracts refunds linked to visible sales', () {
      final sales = [
        sale(id: 'sale-1', total: 1500),
        sale(id: 'sale-2', total: 500),
      ];
      final refunds = [
        refund(id: 'refund-1', saleId: 'sale-1', total: 300),
      ];

      expect(netSalesTotal(sales, refunds), 1700);
    });

    test('uses embedded refund when separate history has no match', () {
      final embedded = refund(id: 'refund-1', total: 250);

      expect(
        netSalesTotal(
          [sale(id: 'sale-1', total: 1000, refund: embedded)],
          const [],
        ),
        750,
      );
    });

    test('does not subtract the same embedded refund twice', () {
      final embedded = refund(id: 'refund-1', total: 250);
      final sales = [sale(id: 'sale-1', total: 1000, refund: embedded)];
      final refunds = [
        refund(id: 'refund-1', saleId: 'sale-1', total: 250),
      ];

      expect(netSalesTotal(sales, refunds), 750);
    });
  });
}
