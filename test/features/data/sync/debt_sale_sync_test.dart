import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/models/fiscal_receipt.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'marked_sale_sync_test.dart' as fixtures;

class DebtRemote extends fixtures.ScriptedRemote {
  final fetchedCustomers = <String>[];
  List<SaleModel> sales = [];

  @override
  Future<List<SaleModel>> fetchCustomerSales(
      {required String key, required String customerId}) async {
    fetchedCustomers.add(customerId);
    return sales;
  }
}

Future<void> seed(PosSyncLocalStore store) => store.replaceBootstrapData(
      posKey: 'KEY',
      deviceId: 'DEVICE',
      cursorBefore: 0,
      posInfo: {},
      products: [],
      sales: [],
      refunds: [],
      expenseTypes: [],
      accounts: [
        {'id': 'CASH', 'name': 'Касса', 'type': 'cash'},
        {'id': 'BANK', 'name': 'Банк', 'type': 'bank'},
        {'id': 'DEBT', 'name': 'Долг', 'type': 'debt'},
      ],
      customers: [
        {
          'id': 'CUSTOMER',
          'name': 'Покупатель',
          'phone': '123',
          'debt_state': 'debt',
          'debt_balance': 1000
        }
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('marked debt accepts no payment and requires a customer', () async {
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    final remote = DebtRemote()..handler = (p) async => fixtures.accepted(p);
    final sync = PosSyncService(store, remote);
    addTearDown(sync.dispose);
    final debt = fixtures.sale(codes: [fixtures.oldCode]).copyWith(
        paymentMethod: 'debt', customerId: 'CUSTOMER');
    final result = await sync
        .createSale(key: 'KEY', deviceId: 'DEVICE', sale: debt, payments: []);
    expect(result.result, QueueSendResult.sent);
    expect(remote.requests.single['payment_method'], 'debt');
    expect(remote.requests.single['payments'], isEmpty);
    expect(
        remote.requests.single['items'][0]['mark_codes'], [fixtures.oldCode]);
    expect(remote.requests.single['local_number'], isPositive);
    await expectLater(
        sync.createSale(
            key: 'KEY',
            deviceId: 'DEVICE',
            sale: fixtures
                .sale(id: 'missing-customer')
                .copyWith(paymentMethod: 'debt'),
            payments: []),
        throwsArgumentError);
    expect(remote.requests, hasLength(1));
  });

  test(
      'settlement survives restart, retries identical payload, stores advance and refreshes customer sales',
      () async {
    final dir = await Directory.systemTemp.createTemp('debt-sync-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/sync.sqlite';
    var store = PosSyncLocalStore(database: sqlite3.open(path));
    await seed(store);
    final remote = DebtRemote()
      ..handler = (_) async => throw fixtures.timeout();
    var sync = PosSyncService(store, remote);
    final first = await sync.settleCustomerDebt(
        key: 'KEY',
        deviceId: 'DEVICE',
        customerId: 'CUSTOMER',
        accountId: 'BANK',
        amount: 1100.25,
        userId: 'USER');
    expect(first.result, QueueSendResult.queued);
    final payload = remote.requests.single;
    expect(payload, isNot(contains('sale_id')));
    expect(payload['date'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
    await sync.dispose();
    store = PosSyncLocalStore(database: sqlite3.open(path));
    sync = PosSyncService(store, remote);
    addTearDown(() => sync.dispose());
    remote.handler = (p) async => {
          'id': 'SETTLEMENT',
          'client_settlement_id': p['client_settlement_id'],
          'agent': {'debt_balance': -100.25}
        };
    await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
    await Future<void>.delayed(Duration.zero);
    expect(remote.requests, hasLength(2));
    expect(remote.requests.last, payload);
    final customer = (await sync.loadCustomers()).single.rawJson;
    expect(customer['debt_balance'], -100.25);
    expect(customer['balance'], -100.25);
    expect(customer['name'], 'Покупатель');
    expect(customer['debt_state'], 'advance');
    expect(remote.fetchedCustomers, ['CUSTOMER']);
    await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
    expect(remote.requests, hasLength(2));
  });

  test('rejects debt accounts and fractional cents before enqueueing',
      () async {
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    await seed(store);
    final remote = DebtRemote();
    final sync = PosSyncService(store, remote);
    addTearDown(sync.dispose);
    for (final amount in [0, 0.001, 1.001, double.nan, double.infinity]) {
      await expectLater(
          sync.settleCustomerDebt(
              key: 'KEY',
              deviceId: 'DEVICE',
              customerId: 'CUSTOMER',
              accountId: 'CASH',
              amount: amount,
              userId: 'USER'),
          throwsArgumentError);
    }
    await expectLater(
        sync.settleCustomerDebt(
            key: 'KEY',
            deviceId: 'DEVICE',
            customerId: 'CUSTOMER',
            accountId: 'DEBT',
            amount: 1,
            userId: 'USER'),
        throwsArgumentError);
    expect(remote.requests, isEmpty);
  });

  test(
      'customer sale refresh persists all FIFO receipts independently of balance',
      () async {
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    final remote = DebtRemote();
    final sync = PosSyncService(store, remote);
    addTearDown(sync.dispose);
    remote.sales = [
      fixtures.sale(id: 'FIRST').copyWith(
          paymentMethod: 'debt',
          customerId: 'CUSTOMER',
          fiscalReceipt: const FiscalReceipt(
              id: 'R1', status: 'pending', printable: false)),
      fixtures.sale(id: 'SECOND').copyWith(
          paymentMethod: 'debt',
          customerId: 'CUSTOMER',
          fiscalReceipt: const FiscalReceipt(
              id: 'R2', status: 'succeeded', printable: true)),
      fixtures.sale(id: 'PARTIAL').copyWith(
          paymentMethod: 'debt',
          customerId: 'CUSTOMER',
          documentUnpaidAmount: 100),
    ];
    await sync.refreshCustomerDebtSales(
        key: 'KEY',
        deviceId: 'DEVICE',
        customerId: 'CUSTOMER',
        attemptsLeft: 1);
    final sales = await sync.loadAllSalesHistory();
    expect(sales, hasLength(3));
    expect(
        sales.firstWhere((s) => s.localId == 'FIRST').fiscalReceipt!.canPrint,
        isFalse);
    expect(
        sales.firstWhere((s) => s.localId == 'SECOND').fiscalReceipt!.canPrint,
        isTrue);
    expect(
        sales.firstWhere((s) => s.localId == 'PARTIAL').fiscalReceipt, isNull);
  });

  test('discovers receipt that is still null immediately after settlement',
      () async {
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    final remote = DebtRemote();
    final sync = PosSyncService(store, remote);
    addTearDown(sync.dispose);
    final debt = fixtures
        .sale(id: 'LATE')
        .copyWith(paymentMethod: 'debt', customerId: 'CUSTOMER');
    remote.sales = [debt];
    await sync.refreshCustomerDebtSales(
        key: 'KEY',
        deviceId: 'DEVICE',
        customerId: 'CUSTOMER',
        attemptsLeft: 2);
    expect((await sync.loadAllSalesHistory()).single.fiscalReceipt, isNull);
    remote.sales = [
      debt.copyWith(
          fiscalReceipt: const FiscalReceipt(
              id: 'LATE-RECEIPT', status: 'pending', printable: false))
    ];
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(remote.fetchedCustomers, ['CUSTOMER', 'CUSTOMER']);
    expect((await sync.loadAllSalesHistory()).single.fiscalReceipt!.id,
        'LATE-RECEIPT');
  });

  test('fiscal statuses preserve null polling and printing restrictions', () {
    for (final status in ['pending', 'processing', 'failed', 'needs_review']) {
      final receipt = FiscalReceipt.fromJson({
        'id': 'R',
        'status': status,
        'printable': true,
        'poll_after_seconds': null
      });
      expect(receipt.pollAfterSeconds, isNull);
      expect(receipt.canPrint, isFalse);
      expect(FiscalReceipt.fromJson(receipt.toJson()).pollAfterSeconds, isNull);
    }
    expect(
        FiscalReceipt.fromJson(
            {'id': 'R', 'status': 'succeeded', 'printable': false}).canPrint,
        isFalse);
    expect(
        FiscalReceipt.fromJson({'id': 'R', 'status': 'needs_review'})
            .webkassaGuidance,
        contains('Webkassa'));
  });
}
