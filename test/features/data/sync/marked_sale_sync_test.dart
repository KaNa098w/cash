import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/repositories/sale_repository_impl.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

const oldCode = '010460026601046921OLD';
const newCode = '010460026601046921NEW';

class ScriptedRemote extends PosSyncRemoteDataSource {
  ScriptedRemote() : super(Dio());
  final requests = <Map<String, dynamic>>[];
  final events = <String>[];
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? handler;
  List<SyncPullChange> changes = [];
  Object? pullError;

  @override
  Future<Map<String, dynamic>?> sendOperation(
      {required OutboxOperationType type,
      required String key,
      required Map<String, dynamic> payload}) async {
    events.add('POST');
    requests.add(Map<String, dynamic>.from(jsonDecode(jsonEncode(payload))));
    return handler!(payload);
  }

  @override
  Future<SyncPullBatch> pullChanges(
      {required String key, required int cursor, int limit = 500}) async {
    events.add('PULL');
    if (pullError != null) throw pullError!;
    return SyncPullBatch(
        items: changes, nextCursor: cursor + changes.length, hasMore: false);
  }
}

DioException apiError(String code,
    {Map<String, dynamic> context = const {}, int status = 409}) {
  final request = RequestOptions(path: '/sales');
  return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: request, statusCode: status, data: {
        'message': 'Ошибка $code',
        'error_code': code,
        'context': context,
        if (status == 422)
          'errors': {
            'items.0.mark_codes.0': ['GTIN не совпадает']
          },
      }));
}

DioException timeout() => DioException(
    requestOptions: RequestOptions(path: '/sales'),
    type: DioExceptionType.receiveTimeout);

SaleModel sale(
        {String id = '9dcff52a-c601-4e99-b461-ae58c132bd33',
        double qty = 3,
        List<String> codes = const []}) =>
    SaleModel(
      localId: id,
      number: '',
      date: DateTime(2026, 9, 17, 15, 30),
      totalAmount: (qty * 120).round(),
      paymentMethod: 'cash',
      posId: 'POS',
      storeId: 'STORE',
      userId: 'USER',
      accountId: 'ACCOUNT',
      items: [
        SaleItemModel(
            id: '',
            saleId: '',
            productId: 'PRODUCT',
            quantity: qty,
            price: 120,
            totalPrice: qty * 120,
            markCodes: codes)
      ],
    );

Map<String, dynamic> accepted(Map<String, dynamic> payload,
        {List<String> codes = const [oldCode]}) =>
    {
      ...payload,
      'id': 'SALE',
      'number': '1042',
      'completed': true,
      'fiscal_receipt': null,
      'items': [
        {
          ...(payload['items'] as List).single as Map<String, dynamic>,
          'id': 'ITEM',
          'sale_id': 'SALE',
          'mark_codes': codes,
          'marking_parts': [
            for (var i = 0; i < codes.length; i++)
              {
                'code': codes[i],
                'quantity': codes.length == 1 ? 3 : (i == 0 ? 2 : 1),
                'package_quantity': 10
              }
          ],
        }
      ],
    };

void main() {
  late PosSyncLocalStore store;
  late ScriptedRemote remote;
  late PosSyncService sync;
  setUp(() {
    store = PosSyncLocalStore(database: sqlite3.openInMemory());
    remote = ScriptedRemote();
    sync = PosSyncService(store, remote);
  });
  tearDown(() async => sync.dispose());

  test('closing a registered checkout uses local confirmation without POST',
      () async {
    await store.saveAcceptedOperation(OutboxOperationType.sale,
        accepted({...sale().toJson(), 'client_sale_id': sale().localId}));
    expect(
        await sync.isSaleRegistered(
            clientSaleId: sale().localId, key: 'KEY', deviceId: 'DEVICE'),
        isTrue);
    expect(remote.events, isEmpty);
  });

  test('closing a checkout pulls server confirmation without POST', () async {
    remote.changes = [
      SyncPullChange(
          entity: 'sale',
          action: 'upsert',
          payload:
              accepted({...sale().toJson(), 'client_sale_id': sale().localId}))
    ];
    expect(
        await sync.isSaleRegistered(
            clientSaleId: sale().localId, key: 'KEY', deviceId: 'DEVICE'),
        isTrue);
    expect(remote.events, ['PULL']);
    expect(remote.requests, isEmpty);
  });

  test('unconfirmed checkout cannot be closed and is never resubmitted',
      () async {
    expect(
        await sync.isSaleRegistered(
            clientSaleId: sale().localId, key: 'KEY', deviceId: 'DEVICE'),
        isFalse);
    expect(remote.requests, isEmpty);
  });

  test('failed reconciliation preserves uncertainty without POST', () async {
    remote.pullError = timeout();
    await expectLater(
        sync.isSaleRegistered(
            clientSaleId: sale().localId, key: 'KEY', deviceId: 'DEVICE'),
        throwsA(isA<DioException>()));
    expect(remote.requests, isEmpty);
  });

  Future<QueueOperationResult> send(SaleModel value) => sync.createSale(
      key: 'KEY',
      deviceId: 'DEVICE',
      sale: value,
      payments: [
        {'account_id': 'ACCOUNT', 'amount': value.items.single.totalPrice}
      ],
      requireOnline: true);

  test(
      'opening package: retry preserves UUID, local number, payment and error context',
      () async {
    remote.handler = (payload) async {
      if ((payload['items'][0]['mark_codes'] as List).isEmpty) {
        throw apiError('MARKING_PACKAGE_CHANGED', context: {
          'product_id': 'PRODUCT',
          'missing_quantity': 3,
          'action': 'scan_new_mark_code'
        });
      }
      return accepted(payload);
    };
    final first = await send(sale());
    expect(first.errorCode, 'MARKING_PACKAGE_CHANGED');
    expect(first.errorContext['missing_quantity'], 3);
    expect(first.result, QueueSendResult.manual);
    final second = await send(sale(codes: [oldCode]));
    expect(second.result, QueueSendResult.sent);
    expect(
        remote.requests[0]['local_number'], remote.requests[1]['local_number']);
    expect(remote.requests[0]['client_sale_id'],
        remote.requests[1]['client_sale_id']);
    expect(remote.requests[0]['payments'], remote.requests[1]['payments']);
    expect(remote.requests[1]['total_amount'], '360.00');
    expect(remote.requests[1]['items'][0]['price'], '120.00');
  });

  test('sale preserves AIM prefix, separators and case on timeout retry',
      () async {
    const code = ']d2010460026601046921MiXeD\x1D93AbC';
    remote.handler = (_) async => throw timeout();
    await send(sale(codes: [code]));
    remote.handler = (payload) async => accepted(payload);
    await send(sale(codes: ['must-not-replace-frozen-code']));
    expect(remote.requests, hasLength(2));
    expect(remote.requests.first['items'][0]['mark_codes'], [code]);
    expect(remote.requests.last, remote.requests.first);
  });

  test(
      'active package needs no scan; server distribution replaces local codes in history and repository',
      () async {
    remote.handler = (p) async => accepted(p, codes: [oldCode, newCode]);
    final repo = SaleRepositoryImpl(Object(), Object(), sync);
    final result = await repo.createSale(
        key: 'KEY',
        deviceId: 'DEVICE',
        sale: sale(),
        payments: [
          {'account_id': 'ACCOUNT', 'amount': 360}
        ],
        requireOnline: true);
    expect(remote.requests.single['items'][0]['mark_codes'], isEmpty);
    expect(result.sale.items.single.markCodes, [oldCode, newCode]);
    expect(
        result.sale.items.single.markingParts.map((p) => p.quantity), [2, 1]);
    final history = await store.loadSalesHistoryPage();
    expect(history.total, 1);
    expect(history.items.single.items.single.markCodes, [oldCode, newCode]);
    await send(sale());
    expect(remote.requests.length, 1,
        reason: 'Accepted UUID must not be POSTed again');
  });

  test(
      'timeout reconciles an accepted sale before POST and retains server allocated code',
      () async {
    remote.handler = (p) async {
      remote.changes = [
        SyncPullChange(entity: 'sale', action: 'upsert', payload: accepted(p))
      ];
      throw timeout();
    };
    final first = await send(sale());
    expect(first.errorCode, 'NETWORK_RECONCILIATION_REQUIRED');
    final next = await send(sale(qty: 9));
    expect(next.result, QueueSendResult.sent);
    expect(remote.events, ['POST', 'PULL']);
    expect(next.responseData!['items'][0]['mark_codes'], [oldCode]);
    expect(next.payload['total_amount'], '360.00');
  });

  test('timeout without accepted sale pulls first and retries exact payload',
      () async {
    remote.handler = (p) async {
      if (remote.requests.length == 1) throw timeout();
      return accepted(p);
    };
    await send(sale());
    final next = await send(sale(qty: 9, codes: [newCode]));
    expect(next.result, QueueSendResult.sent);
    expect(remote.events, ['POST', 'PULL', 'POST']);
    expect(remote.requests[1], remote.requests[0]);
  });

  test('failed reconciliation never blindly POSTs again', () async {
    remote.handler = (_) async => throw timeout();
    await send(sale());
    remote.pullError = timeout();
    final next = await send(sale());
    expect(next.result, QueueSendResult.manual);
    expect(remote.events, ['POST', 'PULL']);
  });

  test('idempotency conflict is preserved and does not trigger another POST',
      () async {
    remote.handler = (_) async => throw apiError('IDEMPOTENCY_CONFLICT');
    final first = await send(sale());
    expect(first.errorCode, 'IDEMPOTENCY_CONFLICT');
    final next = await send(sale());
    expect(next.errorCode, 'IDEMPOTENCY_CONFLICT');
    expect(remote.requests.length, 1);
  });

  test('MARKING_CONFLICT and field errors retain structured API details',
      () async {
    remote.handler = (_) async => throw apiError('MARKING_CONFLICT');
    final first = await send(sale(codes: [newCode]));
    expect(first.errorCode, 'MARKING_CONFLICT');
    expect(remote.requests.length, 1);
    remote.handler =
        (_) async => throw apiError('VALIDATION_FAILED', status: 422);
    final next = await send(sale());
    expect(next.fieldErrors['items.0.mark_codes.0'], ['GTIN не совпадает']);
  });

  test('simultaneous submit of same sale claims only one request', () async {
    final done = Completer<Map<String, dynamic>>();
    remote.handler = (_) => done.future;
    final first = send(sale());
    final second = send(sale());
    await Future<void>.delayed(Duration.zero);
    expect(remote.requests.length, 1);
    await store.ensureSyncState(posKey: 'KEY', deviceId: 'DEVICE');
    expect(
        await store.claimSpecificPendingOperation(
            type: OutboxOperationType.sale, clientId: sale().localId),
        isNull);
    done.complete(accepted(remote.requests.single));
    expect((await first).result, QueueSendResult.sent);
    expect((await second).result, QueueSendResult.sent);
  });

  test('uncertain financial operation cannot be edited or deleted from queue',
      () async {
    remote.handler = (_) async => throw timeout();
    final first = await send(sale());
    await expectLater(
        store.deleteQueueOperation(first.operationId), throwsStateError);
    await expectLater(
        store.updateQueueOperationPayload(
            operationId: first.operationId, payload: {}),
        throwsStateError);
  });

  test('refund retry uses UUID, reverse_sale and frozen contents', () async {
    remote.handler = (p) async {
      if (remote.requests.length == 1) throw timeout();
      return {...p, 'id': 'REFUND', 'fiscal_receipt': null};
    };
    Future<QueueOperationResult> refund(num qty) => sync.createRefund(
        key: 'KEY',
        deviceId: 'DEVICE',
        posSessionId: '',
        saleId: 'SALE',
        totalAmount: qty * 120,
        paymentMethod: 'cash',
        payments: [],
        date: DateTime.now(),
        reasonCode: 'duplicate_sale',
        items: [
          {
            'product_id': 'PRODUCT',
            'sale_item_id': 'ITEM',
            'quantity': qty,
            'price': 120,
            'mark_codes': [']d2$oldCode']
          }
        ]);
    final first = await refund(2);
    final second = await refund(5);
    expect(first.clientId, matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(second.clientId, first.clientId);
    expect(remote.events, ['POST', 'PULL', 'POST']);
    expect(remote.requests[1], remote.requests[0]);
    expect(remote.requests.last['inventory_action'], 'reverse_sale');
    expect(remote.requests.last['items'][0]['mark_codes'], [oldCode]);
    expect(second.result, QueueSendResult.sent);
  });
  test(
      'accepted refund replay returns canonical server data without another POST',
      () async {
    remote.handler = (p) async => {
          ...p,
          'id': 'REFUND',
          'fiscal_receipt': {
            'id': 'FISCAL',
            'status': 'needs_review',
            'printable': false
          },
          'items': [
            {
              'id': 'RI',
              'product_id': 'PRODUCT',
              'sale_item_id': 'ITEM',
              'quantity': 2,
              'price': '120.25',
              'mark_codes': [oldCode],
              'marking_parts': [
                {'code': oldCode, 'quantity': 2, 'package_quantity': 10}
              ]
            }
          ]
        };
    Future<QueueOperationResult> refund() => sync.createRefund(
        key: 'KEY',
        deviceId: 'DEVICE',
        posSessionId: '',
        saleId: 'SALE',
        clientRefundId: '73e262a2-4dc0-49cf-98d5-83144947810c',
        totalAmount: 240.50,
        paymentMethod: 'cash',
        payments: [],
        date: DateTime(2026, 9, 17),
        reasonCode: 'duplicate_sale',
        inventoryAction: 'write_off',
        items: [
          {
            'product_id': 'PRODUCT',
            'quantity': 2,
            'price': 120.25,
            'mark_codes': [']d2$oldCode']
          }
        ]);
    final first = await refund();
    final second = await refund();
    expect(second.result, QueueSendResult.sent);
    expect(second.clientId, first.clientId);
    expect(remote.requests.length, 1);
    expect(remote.requests.single['inventory_action'], 'write_off');
    final history = await store.loadAllRefundsHistory();
    expect(history.length, 1);
    expect(history.single.items.single.markCodes, [oldCode]);
    expect(history.single.items.single.price, 120.25);
    expect(history.single.items.single.markingParts.single.quantity, 2);
    expect(history.single.fiscalReceipt!.status, 'needs_review');
  });

  test(
      'accepted financial records stay immutable after an earlier marking error',
      () async {
    remote.handler = (_) async => throw apiError('MARKING_PACKAGE_CHANGED');
    final first = await send(sale());
    remote.handler = (p) async => accepted(p);
    await send(sale(codes: [oldCode]));
    await expectLater(
        store.deleteQueueOperation(first.operationId), throwsStateError);
    await expectLater(
        store.updateQueueOperationPayload(
            operationId: first.operationId, payload: {}),
        throwsStateError);
  });

  test('receipt counter stays monotonic after catalogue cleanup', () async {
    expect(await store.nextLocalSaleNumber(), 1);
    await store.clearAllLocalData();
    expect(await store.nextLocalSaleNumber(), 2);
  });
  test('restart recovers interrupted POST as requiring reconciliation',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('marked-sale-recovery-');
    final path = '${directory.path}/pos.sqlite';
    var durable = PosSyncLocalStore(database: sqlite3.open(path));
    await durable.enqueueOperation(
        id: 'OP',
        type: OutboxOperationType.sale,
        clientId: sale().localId,
        payload: {'client_sale_id': sale().localId, 'local_number': 42});
    await durable.claimSpecificPendingOperation(
        type: OutboxOperationType.sale, clientId: sale().localId);
    await durable.close();
    durable = PosSyncLocalStore(database: sqlite3.open(path));
    final recovered =
        await durable.findOperation(OutboxOperationType.sale, sale().localId);
    expect(recovered!.status, OutboxOperationStatus.manual);
    expect(recovered.lastErrorCode, 'NETWORK_RECONCILIATION_REQUIRED');
    expect(recovered.payload['local_number'], 42);
    await durable.close();
    directory.deleteSync(recursive: true);
  });

  test(
      'sale amount and paid amount preserve fractional money in cached response',
      () async {
    remote.handler = (p) async => {...accepted(p), 'paid_amount': '360.75'};
    final fractional = sale().copyWith(items: [
      sale().items.single.copyWith(price: 120.25, totalPrice: 360.75)
    ]);
    await send(fractional);
    final cached = (await store.loadSalesHistoryPage()).items.single;
    expect(cached.totalAmount, 360.75);
    expect(cached.paidAmount, 360.75);
    expect(remote.requests.single['total_amount'], '360.75');
  });
}
