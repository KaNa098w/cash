import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/marketplace_orders_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/marketplace_orders/marketplace_orders_controller.dart';
import 'package:leemon_app/features/presentation/widgets/incoming_orders_dialog.dart';
import 'package:provider/provider.dart';
import 'package:leemon_app/features/presentation/widgets/top_bar.dart'
    show PosTicketTab;

class _Controller extends MarketplaceOrdersController {
  _Controller() : super(MarketplaceOrdersRemoteDataSource(Dio()));
  final order = MarketplaceOrder.fromJson({
    'id': 'order-1',
    'number': 'MP-123',
    'status': 'processing',
    'customer': {'name': 'Покупатель'},
    'items': [
      {'name': 'Молоко', 'quantity': 2, 'unitPrice': 100}
    ],
  });
  final secondOrder = MarketplaceOrder.fromJson({
    'id': 'order-2',
    'number': 'MP-124',
    'status': 'processing',
    'customer': {'name': 'Другой покупатель'},
    'items': [
      {'name': 'Хлеб', 'quantity': 1, 'unitPrice': 200}
    ],
  });
  bool secondSelected = false;
  @override
  // Future<void> selectOrder(String orderId) async {
  //   secondSelected = orderId == secondOrder.id;
  //   notifyListeners();
  // }

  @override
  Future<void> refreshVisibleOrders() async {}
  MarketplaceOrderScope currentScope = MarketplaceOrderScope.active;
  int shipments = 0;
  @override
  MarketplaceOrder? get selectedOrder => secondSelected ? secondOrder : order;
  @override
  MarketplaceOrderScope get scope => currentScope;
  @override
  List<MarketplaceOrder> get activeOrders => [order, secondOrder];
  @override
  List<MarketplaceOrder> get visibleOrders => [order, secondOrder];
  @override
  Future<void> configure(
      {required String posKey,
      required String deviceId,
      bool force = false}) async {}
  @override
  Future<void> setScope(MarketplaceOrderScope next) async {
    currentScope = next;
    notifyListeners();
  }

  @override
  Future<MarketplaceShipmentResult?> shipSelectedOrder() async {
    shipments++;
    return null;
  }
}

void main() {
  for (final width in [640.0, 800.0, 1024.0, 1440.0]) {
    testWidgets('marketplace actions and order selection at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller();
      GetIt.I.registerSingleton<MarketplaceOrdersController>(controller);
      addTearDown(() async {
        await GetIt.I.unregister<MarketplaceOrdersController>();
        controller.dispose();
      });
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AuthTokenProvider(),
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showIncomingOrdersDialog(context),
                        child: const Text('Открыть'))))),
      ));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.text('Молоко'), findsOneWidget);
      expect(find.text('ОТГРУЗИТЬ'), findsOneWidget);
      final lineTotal = find.byKey(const ValueKey('line-total--Молоко'));
      expect(lineTotal, findsOneWidget);
      final totalBounds = tester.getRect(lineTotal);
      expect(totalBounds.right, lessThanOrEqualTo(width));
      expect(totalBounds.left, greaterThanOrEqualTo(0));
      expect(find.text('В сборке'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('ОТГРУЗИТЬ'));
      await tester.pumpAndSettle();
      expect(find.text('Подтверждение отгрузки'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(controller.shipments, 0);
      final secondTab = find.text('№ MP-124');
      await tester.ensureVisible(secondTab);
      await tester.tap(secondTab);
      await tester.pumpAndSettle();
      expect(find.text('Хлеб'), findsOneWidget);
      expect(find.text('Молоко'), findsNothing);
      final selectedTab = tester.widget<PosTicketTab>(
          find.ancestor(of: secondTab, matching: find.byType(PosTicketTab)));
      expect(selectedTab.active, isTrue);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('История'));
      await tester.tap(find.text('История'));
      await tester.pumpAndSettle();
      expect(controller.scope, MarketplaceOrderScope.history);
      final shipButton = tester.widget<ElevatedButton>(find.ancestor(
          of: find.text('ОТГРУЗИТЬ'), matching: find.byType(ElevatedButton)));
      expect(shipButton.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
