import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/features/data/datasources/marketplace_orders_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/marketplace_orders/marketplace_orders_controller.dart';

MarketplaceOrder _order(String id, String status) => MarketplaceOrder.fromJson({
      'id': id,
      'status': status,
      'items': [
        {'name': id, 'quantity': 1, 'price': 100}
      ],
    });

class _Remote extends MarketplaceOrdersRemoteDataSource {
  _Remote() : super(Dio());
  final newOrder = _order('new-1', 'awaiting_confirmation');
  final activeOrder = _order('active-1', 'processing');
  final historyOrder = _order('history-1', 'shipped');
  bool emptyActive = false;
  bool failDetails = false;
  @override
  Future<MarketplacePosInfo> fetchPosInfo({required String key}) async =>
      MarketplacePosInfo.fromJson({'has_marketplace_integration': true});
  @override
  Future<MarketplaceOrdersPage> listOrders(
          {required String key,
          required MarketplaceOrderScope scope,
          int skip = 0,
          int take = 20}) async =>
      MarketplaceOrdersPage(
          items: switch (scope) {
        MarketplaceOrderScope.newOrders => [newOrder],
        MarketplaceOrderScope.active => emptyActive ? [] : [activeOrder],
        MarketplaceOrderScope.history => [historyOrder],
      });
  @override
  Future<MarketplaceOrder> getOrder(
      {required String key, required String orderId}) async {
    if (failDetails) throw Exception('details unavailable');
    return [newOrder, activeOrder, historyOrder]
        .firstWhere((order) => order.id == orderId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('repeated scope changes keep visible list and selected order consistent',
      () async {
    final remote = _Remote();
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    for (var cycle = 0; cycle < 3; cycle++) {
      for (final scope in [
        MarketplaceOrderScope.active,
        MarketplaceOrderScope.history,
        MarketplaceOrderScope.newOrders
      ]) {
        await controller.setScope(scope);
        expect(controller.scope, scope);
        expect(
            controller.selectedOrder?.id, controller.visibleOrders.single.id);
        expect(controller.loading, isFalse);
      }
    }
    remote.emptyActive = true;
    await controller.setScope(MarketplaceOrderScope.active);
    expect(controller.visibleOrders, isEmpty);
    expect(controller.selectedOrder, isNull);
    remote.emptyActive = false;
    await controller.refreshVisibleOrders();
    expect(controller.selectedOrder?.id, remote.activeOrder.id);
    remote.failDetails = true;
    await controller.setScope(MarketplaceOrderScope.newOrders);
    expect(controller.selectedOrder?.id, remote.newOrder.id);
  });
}
