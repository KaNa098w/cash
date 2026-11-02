import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart' show SaleModel;
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/print/cash_drawer_service.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/payment_panel.dart';

class _Auth extends AuthTokenProvider {
  @override
  String get posKey => 'KEY';
  @override
  String get deviceId => 'DEVICE';
  @override
  String get storeId => 'STORE';
  @override
  String get posId => 'POS';
  @override
  String get activeUserId => 'USER';
  @override
  String get accountId => 'CASH';
  @override
  bool get receiptPrintingEnabled => false;
  @override
  String get receiptPrinterName => 'PRINTER';
}

class _PosRepository implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

class _Sync implements PosSyncService {
  final accounts = Completer<List<LocalAccount>>();
  @override
  Future<List<LocalAccount>> loadAccounts() => accounts.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sales implements SaleRepository {
  final requests = <SaleModel>[];
  final replies = <Completer<CreateSaleOutcome>>[];
  @override
  Future<CreateSaleOutcome> createSale(
      {required String key,
      required String deviceId,
      required SaleModel sale,
      required List<Map<String, dynamic>> payments,
      bool requireOnline = false,
      bool discardOnFailure = false}) {
    requests.add(sale);
    final reply = Completer<CreateSaleOutcome>();
    replies.add(reply);
    return reply.future;
  }

  void reject(int index) => replies[index].complete(CreateSaleOutcome(
        result: CreateSaleResult.rejected,
        sale: requests[index],
        errorCode: 'NETWORK_ERROR',
        errorMessage: 'Нет ответа сервера',
      ));
  @override
  Future<void> syncPendingSales(
      {required String key, required String deviceId}) async {}
}

Future<void> _drainUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  expect(done(), isTrue);
}

void main() {
  testWidgets(
      'non-fiscal checkout closes while a disconnected drawer is still waiting',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'receiptPrint.openDrawerOnCashSale': true});
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = PosCubit(_PosRepository());
    final sales = _Sales();
    final sync = _Sync()..accounts.complete([]);
    final drawerStarted = Completer<void>();
    final drawerResponse = Completer<void>();
    final drawer = CashDrawerService(writer: (_, __) {
      drawerStarted.complete();
      return drawerResponse.future;
    });
    sl.registerSingleton<PosSyncService>(sync);
    sl.registerSingleton<SaleRepository>(sales);
    addTearDown(() {
      sl.unregister<PosSyncService>();
      sl.unregister<SaleRepository>();
    });
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    cubit.add(const Product(id: 'p', name: 'Product', price: 100));
    await tester.pumpWidget(ChangeNotifierProvider<AuthTokenProvider>(
      create: (_) => _Auth(),
      child: BlocProvider.value(
          value: cubit,
          child: MaterialApp(
              home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () {
                      showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                              child: PaymentPanel(cashDrawerService: drawer)));
                    },
                    child: const Text('Open payment'))),
          ))),
    ));
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
    cubit.setReceived(100);
    await tester.pumpAndSettle();
    final button = find.ancestor(
        of: find.text('ОПЛАТА'), matching: find.byType(TextButton));
    await tester.runAsync(() async {
      tester.widget<TextButton>(button).onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await _drainUntil(tester, () => sales.requests.isNotEmpty);
    expect(sales.requests, hasLength(1));
    await tester.runAsync(() async {
      sales.replies.single.complete(CreateSaleOutcome(
          result: CreateSaleResult.queued,
          sale: sales.requests.single,
          retryScheduled: true));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _drainUntil(
        tester,
        () =>
            find.byType(PaymentPanel).evaluate().isEmpty &&
            drawerStarted.isCompleted);
    expect(drawerStarted.isCompleted, isTrue);
    expect(drawerResponse.isCompleted, isFalse);
    expect(find.byType(PaymentPanel), findsNothing);
    expect(cubit.state.items, isEmpty);
    expect(cubit.paymentOperationInProgress, isFalse);
    cubit.add(const Product(id: 'next', name: 'Next customer', price: 200));
    expect(cubit.total, 200);
    await tester.runAsync(() async {
      drawerResponse.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid taps and Enter submit once; retry retains the sale ID',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = PosCubit(_PosRepository());
    final sales = _Sales();
    final sync = _Sync();
    sl.registerSingleton<PosSyncService>(sync);
    sl.registerSingleton<SaleRepository>(sales);
    addTearDown(() {
      sl.unregister<PosSyncService>();
      sl.unregister<SaleRepository>();
    });
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    cubit.add(const Product(id: 'p', name: 'Product', price: 100));
    await tester.pumpWidget(ChangeNotifierProvider<AuthTokenProvider>(
      create: (_) => _Auth(),
      child: BlocProvider.value(
          value: cubit,
          child: const MaterialApp(
            home: Scaffold(
                body:
                    Align(alignment: Alignment.topLeft, child: PaymentPanel())),
          )),
    ));
    await tester.pump();
    cubit.setReceived(100);
    await tester.pump();
    final button = find.ancestor(
        of: find.text('ОПЛАТА'), matching: find.byType(TextButton));
    final firstTap = tester.widget<TextButton>(button).onPressed!;
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        firstTap();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(sales.requests, isEmpty); // Still waiting for account preparation.
    final preparingButton = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(preparingButton).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.runAsync(() async {
      sync.accounts.complete([]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(sales.requests, hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
    final spinnerButton = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(spinnerButton).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sales.requests, hasLength(1));
    await tester.runAsync(() async {
      sales.reject(0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(cubit.paymentOperationInProgress, isFalse);
    final retry = tester.widget<TextButton>(button).onPressed!;
    await tester.runAsync(() async {
      retry();
      retry();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(sales.requests, hasLength(2));
    expect(sales.requests.last.localId, sales.requests.first.localId);
    expect(sales.requests.last.idempotencyKey,
        sales.requests.first.idempotencyKey);
    await tester.runAsync(() async {
      sales.reject(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
    expect(tester.takeException(), isNull);
  });
}
