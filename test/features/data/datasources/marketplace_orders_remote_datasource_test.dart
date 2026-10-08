import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/features/data/datasources/marketplace_orders_remote_datasource.dart';

void main() {
  late Dio dio;
  late MarketplaceOrdersRemoteDataSource remote;
  late RequestOptions request;
  Map<String, dynamic> response = {};
  setUp(() {
    dio = Dio();
    remote = MarketplaceOrdersRemoteDataSource(dio);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      request = options;
      handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: response));
    }));
  });
  test('accept sends order item IDs and quantities and requires ok', () async {
    response = {'ok': true, 'status': 200};
    await remote.acceptOrder(
        key: 'pos',
        orderId: 'order',
        items: const [MarketplaceOrderQuantity(id: 'order-item', quantity: 4)]);
    expect(request.data, {
      'items': [
        {'id': 'order-item', 'quantity': 4}
      ]
    });
    expect(request.method, 'POST');
    response = {'ok': false, 'status': 409, 'message': 'Остаток'};
    await expectLater(
        remote.acceptOrder(key: 'pos', orderId: 'order', items: const [
          MarketplaceOrderQuantity(id: 'order-item', quantity: 4)
        ]),
        throwsA(isA<MarketplaceOrdersApiException>()));
    response = {'status': 200};
    await expectLater(
        remote.acceptOrder(key: 'pos', orderId: 'order', items: const [
          MarketplaceOrderQuantity(id: 'order-item', quantity: 4)
        ]),
        throwsA(isA<MarketplaceOrdersApiException>()));
  });
  test('shipment permits success without a globally shipped order', () async {
    response = {'ok': true, 'status': 200, 'sale_created': false};
    final result = await remote.shipOrder(
        key: 'pos', orderId: 'order', idempotencyKey: 'shipment-1');
    expect(result.ok, true);
    expect(request.data, isEmpty);
    expect(request.headers['Idempotency-Key'], 'shipment-1');
    await remote.shipOrder(
        key: 'pos',
        orderId: 'order',
        idempotencyKey: 'shipment-2',
        items: const [MarketplaceOrderQuantity(id: 'order-item', quantity: 2)]);
    expect(request.data, {
      'items': [
        {'id': 'order-item', 'quantity': 2}
      ]
    });
  });
  test('available acceptance quantity subtracts confirmed and cancelled', () {
    final order = MarketplaceOrder.fromJson({
      'items': [
        {
          'id': 'item',
          'product_id': 'product',
          'requestedQuantity': 8,
          'confirmedQuantity': 3,
          'cancelledQuantity': 1
        }
      ]
    });
    expect(order.acceptableItems.single.id, 'item');
    expect(order.acceptableItems.single.availableQuantity, 4);
  });
}
