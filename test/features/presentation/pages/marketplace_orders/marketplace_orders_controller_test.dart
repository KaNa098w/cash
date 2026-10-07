import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/presentation/widgets/incoming_orders_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/footer_panels_widget.dart';
import 'package:leemon_app/features/presentation/widgets/top_bar.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sale_items_box.dart';
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
  MarketplaceOrder newOrder = _order('new-1', 'awaiting_confirmation');
  MarketplaceOrder activeOrder = _order('active-1', 'processing');
  final historyOrder = _order('history-1', 'shipped');
  List<MarketplaceOrder>? historyItems;
  List<MarketplaceOrder>? pendingItems;
  int accepts = 0;
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
        MarketplaceOrderScope.newOrders => pendingItems ??
            (newOrder.status == 'awaiting_confirmation' ? [newOrder] : []),
        MarketplaceOrderScope.active => emptyActive
            ? []
            : [activeOrder, if (newOrder.status == 'processing') newOrder],
        MarketplaceOrderScope.history =>
          (historyItems ?? [historyOrder]).skip(skip).take(take).toList(),
      });
  @override
  Future<MarketplaceAcceptResult> acceptOrder(
      {required String key, required String orderId}) async {
    accepts++;
    newOrder = _order(orderId, 'processing');
    return const MarketplaceAcceptResult(
        ok: true, status: 200, accepted: true, assignmentId: 'assignment');
  }

  @override
  Future<MarketplaceOrder> getOrder(
      {required String key, required String orderId}) async {
    if (failDetails) throw Exception('details unavailable');
    return [
      newOrder,
      activeOrder,
      historyOrder,
      ...?historyItems,
      ...?pendingItems
    ].firstWhere((order) => order.id == orderId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all order statuses share one list and selection survives refresh',
      () async {
    final remote = _Remote();
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    expect(controller.visibleOrders.map((o) => o.id),
        containsAll(['new-1', 'active-1', 'history-1']));
    await controller.selectOrder('active-1');
    await controller.refreshVisibleOrders();
    expect(controller.selectedOrder?.id, 'active-1');
    remote.activeOrder = _order('active-1', 'partially_shipped');
    await controller.refreshVisibleOrders();
    expect(controller.selectedOrder?.status, 'partially_shipped');
    remote.emptyActive = true;
    await controller.refreshVisibleOrders();
    expect(controller.visibleOrders.map((o) => o.id),
        containsAll(['new-1', 'history-1']));
    expect(controller.visibleOrders.any((o) => o.id == 'active-1'), isFalse);
    expect(controller.selectedOrder?.id, isNot('active-1'));
    expect(controller.loading, isFalse);
  });
  test('history refresh keeps current orders available', () async {
    final remote = _Remote();
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    await controller.setScope(MarketplaceOrderScope.history);
    expect(controller.visibleOrders.length, 3);
    await controller.selectOrder('new-1');
    expect(controller.selectedOrder?.status, 'awaiting_confirmation');
  });
  test('unified list deduplicates orders and loads older history', () async {
    final remote = _Remote();
    remote.historyItems = [
      remote.activeOrder,
      ...List.generate(21, (i) => _order('history-$i', 'completed'))
    ];
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    expect(controller.visibleOrders.where((o) => o.id == 'active-1').length, 1);
    expect(controller.historyHasMore, isTrue);
    await controller.loadMoreHistory();
    expect(controller.visibleOrders.length, 23);
    expect(controller.historyHasMore, isFalse);
    expect(controller.historyLoadingMore, isFalse);
  });
  test('accepting new order preserves selection and confirms processing status',
      () async {
    final remote = _Remote();
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    await controller.selectOrder('new-1');
    await controller.acceptSelected();
    expect(controller.selectedOrder?.id, 'new-1');
    expect(controller.selectedOrder?.status, 'processing');
    expect(remote.accepts, 1);
    await controller.acceptSelected();
    expect(remote.accepts, 1);
    expect(controller.actionLoading, isFalse);
  });
  testWidgets(
      'marketplace footer hides secondary controls and keeps primary action usable',
      (tester) async {
    var accepted = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 600,
      height: 170,
      child: FooterControlsOnly(
        smallAmountText: 'Итого',
        bigAmountText: '100 ₸',
        showAdjustmentButtons: false,
        showPayCardButton: false,
        minusLabel: 'Обновить',
        plusLabel: 'Принять',
        payCardLabel: 'Заказы',
        paymentLabel: 'ПРИНЯТЬ',
        onPay: () => accepted = true,
      ),
    )))));
    expect(find.text('Обновить'), findsNothing);
    expect(find.text('Принять'), findsNothing);
    expect(find.text('Заказы'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ПРИНЯТЬ'));
    expect(accepted, isTrue);
  });
  testWidgets('history searches older order numbers and opens order details',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'posKey': 'pos', 'deviceId': 'device'});
    final tokens = AuthTokenProvider();
    await tokens.init();
    final remote = _Remote();
    remote.historyItems =
        List.generate(22, (i) => _order('history-$i', 'shipped'));
    final controller = MarketplaceOrdersController(remote);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    GetIt.I.registerSingleton<MarketplaceOrdersController>(controller);
    addTearDown(() async {
      await GetIt.I.unregister<MarketplaceOrdersController>();
      controller.dispose();
      tokens.dispose();
    });
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: tokens,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showIncomingOrdersDialog(context),
                          child: const Text('Open')),
                    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(controller.selectedOrder?.id, 'new-1');
    expect(find.text('ПРИНЯТЬ'), findsOneWidget);
    expect(tester.widget<PosMenuTab>(find.byType(PosMenuTab)).active, isFalse);
    expect(find.byTooltip('Обновить заказы'), findsOneWidget);
    expect(find.text('Выйти'), findsOneWidget);
    await tester.tap(find.byTooltip('Обновить заказы'));
    await tester.pumpAndSettle();
    expect(controller.selectedOrder?.id, 'new-1');
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(find.text('История'), findsOneWidget);
    final tabs =
        tester.widgetList<PosTicketTab>(find.byType(PosTicketTab)).toList();
    expect(tabs.map((tab) => tab.text), containsAll(['№ new-1', '№ active-1']));
    expect(tabs.any((tab) => tab.text.contains('history-')), isFalse);
    expect(tabs.firstWhere((tab) => tab.text == '№ new-1').statusDotColor,
        const Color(0xFF22B982));
    expect(tabs.firstWhere((tab) => tab.text == '№ active-1').statusDotColor,
        const Color(0xFFF59E0B));
    await tester.enterText(find.byType(TextField), 'history-21');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Найдено заказов: 1'), findsOneWidget);
    final row = find
        .ancestor(of: find.text('№ history-21'), matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Статус заказа № history-21'), findsNothing);
    expect(find.byType(SaleItemsBox), findsOneWidget);
    expect(find.text('Номер заказа'), findsNothing);
    expect(find.text('Покупатель'), findsOneWidget);
    expect(find.text('Телефон'), findsOneWidget);
    expect(controller.selectedOrder?.id, 'history-21');
    expect(find.text('Найдено заказов: 1'), findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Статус заказа № history-21'), findsNothing);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(find.text('Найдено заказов: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await controller.deactivate();
  });
  test('only pending and working orders appear in top bar', () async {
    final remote = _Remote();
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    expect(controller.topBarOrders.map((o) => o.id),
        containsAll(['new-1', 'active-1']));
    expect(controller.topBarOrders.any((o) => o.status == 'shipped'), isFalse);
    expect(controller.visibleOrders.any((o) => o.status == 'shipped'), isTrue);
    expect(controller.shippedOrders.map((o) => o.id), ['history-1']);
    remote.activeOrder = _order('active-1', 'shipped');
    await controller.refreshVisibleOrders();
    expect(controller.topBarOrders.any((o) => o.id == 'active-1'), isFalse);
    expect(controller.visibleOrders.any((o) => o.id == 'active-1'), isTrue);
  });
  test(
      'latest pending order is selected by date and absent when none are pending',
      () async {
    final remote = _Remote();
    remote.pendingItems = [
      MarketplaceOrder.fromJson({
        'id': 'older',
        'status': 'awaiting_confirmation',
        'created_at': '2026-10-07T10:00:00Z'
      }),
      MarketplaceOrder.fromJson({
        'id': 'newest',
        'status': 'awaiting_confirmation',
        'created_at': '2026-10-07T12:00:00Z'
      }),
    ];
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    expect(controller.latestNewOrder?.id, 'newest');
    remote.pendingItems = [];
    await controller.refreshVisibleOrders();
    expect(controller.latestNewOrder, isNull);
  });
  test('order summary remains selected when opening details fails', () async {
    final remote = _Remote();
    final controller = MarketplaceOrdersController(remote);
    addTearDown(controller.dispose);
    await controller.configure(posKey: 'pos', deviceId: 'device');
    remote.failDetails = true;
    await controller.selectOrder('new-1', fallback: remote.newOrder);
    expect(controller.selectedOrder?.id, 'new-1');
    expect(controller.error, isNotNull);
    expect(controller.loading, isFalse);
  });
}
