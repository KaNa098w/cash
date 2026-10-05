import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/sync/refund_request_contract.dart';

class _Adapter implements HttpClientAdapter {
  final bodies = <String>[];
  final headers = <Map<String, dynamic>>[];
  final paths = <String>[];
  void Function(String)? beforeRequest;
  int status = 200;
  Map<String, dynamic>? response;
  bool timeout = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.data as String;
    bodies.add(body);
    headers.add(Map.from(options.headers));
    paths.add(options.path);
    beforeRequest?.call(body);
    if (timeout) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.receiveTimeout);
    }
    final request = jsonDecode(body) as Map<String, dynamic>;
    return ResponseBody.fromString(
        jsonEncode(response ??
            {
              'data': {
                ...request,
                'id': 'SERVER-REFUND',
                'sale_id': null,
                'fiscal_receipt': null
              }
            }),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

class _Remote extends PosSyncRemoteDataSource {
  _Remote(super.dio);
  int pulls = 0;
  @override
  Future<SyncPullBatch> pullChanges(
      {required String key, required int cursor, int limit = 500}) async {
    pulls++;
    return SyncPullBatch(items: [], nextCursor: cursor, hasMore: false);
  }
}

Future<QueueOperationResult> create(PosSyncService sync,
        {String id = 'refund-test', int price = 1540, DateTime? date}) =>
    sync.createRefund(
      key: 'POS-KEY',
      deviceId: 'DEVICE',
      posSessionId: 'SESSION',
      posId: 'POS-ID',
      storeId: 'STORE',
      accountId: 'CASH',
      saleId: '',
      clientRefundId: id,
      totalAmount: price,
      paymentMethod: 'cash',
      payments: [
        {
          'account_id': 'CASH',
          'amount': price,
          'client_payment_id': '$id-payment'
        }
      ],
      date: date ?? DateTime(2026, 9, 13, 15, 10, 44),
      items: [
        {
          'product_id': 'PRODUCT',
          'sale_item_id': 'DO-NOT-SEND',
          'quantity': 1,
          'price': price
        }
      ],
      returnAccessKey: 'TEST-ACCESS-KEY',
      reasonCode: 'other',
      inventoryAction: 'return_to_stock',
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adapter adapter;
  late _Remote remote;
  late PosSyncLocalStore store;
  late PosSyncService sync;
  late Database db;
  setUp(() {
    db = sqlite3.openInMemory();
    store = PosSyncLocalStore(database: db);
    adapter = _Adapter();
    remote = _Remote(Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter);
    sync = PosSyncService(store, remote);
  });
  tearDown(() async {
    sync.dispose();
    await store.close();
  });
  test(
      'no-sale body and header match contract, saved before HTTP, success saves server ID',
      () async {
    adapter.beforeRequest = (body) {
      final saved = jsonDecode(db
          .select('SELECT payload_json FROM outbox_operations')
          .single['payload_json'] as String);
      expect(saved[refundRequestJsonKey], body);
      expect(db.select('SELECT * FROM refund_sync_attempts'), hasLength(1));
    };
    final result = await create(sync);
    final body = jsonDecode(adapter.bodies.single) as Map<String, dynamic>;
    expect(body.keys, isNot(contains('sale_id')));
    expect(body.keys, isNot(contains('client_sale_id')));
    expect(body.keys, isNot(contains('account_id')));
    expect(body.keys, isNot(contains('return_access_key')));
    expect(body['items'][0], isNot(contains('sale_item_id')));
    expect(adapter.paths.single, '/organizations/pos/POS-KEY/refunds');
    expect(adapter.headers.single['X-Return-Access-Key'], 'TEST-ACCESS-KEY');
    expect(result.result, QueueSendResult.sent);
    expect(
        (await store.findOperation(OutboxOperationType.refund, 'refund-test'))!
            .status,
        OutboxOperationStatus.acked);
    expect(
        (await store.acceptedOperation(
            OutboxOperationType.refund, 'refund-test'))!['id'],
        'SERVER-REFUND');
    final log = db.select('SELECT * FROM refund_sync_attempts').single;
    expect(log['operation_kind'], 'refund_without_sale');
    expect(log['http_status'], 200);
    expect(log['response_json'], contains('SERVER-REFUND'));
  });
  test(
      'timeout retries byte-for-byte after restart despite changed date, items and app version',
      () async {
    final dir = await Directory.systemTemp.createTemp('refund-wire-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/sync.sqlite';
    final firstStore = PosSyncLocalStore(database: sqlite3.open(path));
    final firstSync = PosSyncService(firstStore, remote);
    adapter.timeout = true;
    final first = await create(firstSync);
    expect(first.result, QueueSendResult.queued);
    expect(
        (await firstStore.findOperation(
                OutboxOperationType.refund, first.clientId))!
            .status,
        OutboxOperationStatus.pending);
    final original = adapter.bodies.single;
    firstSync.dispose();
    await firstStore.close();
    final interruptedDb = sqlite3.open(path);
    final savedPayload = jsonDecode(interruptedDb
        .select('SELECT payload_json FROM outbox_operations')
        .single['payload_json'] as String) as Map<String, dynamic>;
    savedPayload['app_version'] = 'future-version';
    interruptedDb.execute(
        "UPDATE outbox_operations SET status = 'sending', payload_json = ?",
        [jsonEncode(savedPayload)]);
    interruptedDb.dispose();
    final reopened = PosSyncLocalStore(database: sqlite3.open(path));
    expect(
        (await reopened.findOperation(
                OutboxOperationType.refund, first.clientId))!
            .status,
        OutboxOperationStatus.pending);
    final secondSync = PosSyncService(reopened, remote);
    addTearDown(() async {
      secondSync.dispose();
      await reopened.close();
    });
    adapter.timeout = false;
    final second = await create(secondSync, price: 2200, date: DateTime(2030));
    expect(adapter.bodies.last, original);
    expect(second.clientId, first.clientId);
    expect(second.result, QueueSendResult.sent);
    expect(remote.pulls, 0);
    expect(
        (await reopened.findOperation(
                OutboxOperationType.refund, first.clientId))!
            .status,
        OutboxOperationStatus.acked);
  });
  test('legacy attempted refund without frozen JSON requires manual review',
      () async {
    adapter.timeout = true;
    final first = await create(sync);
    final record =
        await store.findOperation(OutboxOperationType.refund, first.clientId);
    final legacy = Map<String, dynamic>.from(record!.payload)
      ..remove(refundRequestJsonKey);
    db.execute('UPDATE outbox_operations SET payload_json = ?, retry_count = 1',
        [jsonEncode(legacy)]);
    adapter.timeout = false;
    final next = await create(sync);
    expect(next.result, QueueSendResult.manual);
    expect(next.errorCode, 'REFUND_RECONCILIATION_REQUIRED');
    expect(adapter.bodies, hasLength(1));
    expect(remote.pulls, 0);
  });
  test(
      '409 refund conflict never pulls sales, changes ID or replays, journal retains raw error',
      () async {
    adapter.status = 409;
    adapter.response = {
      'error_code': 'IDEMPOTENCY_CONFLICT',
      'message': 'Этот возврат уже отправлялся с другими данными.'
    };
    final first = await create(sync);
    expect(first.result, QueueSendResult.manual);
    expect(first.errorMessage, contains('возврат'));
    expect(first.errorMessage, isNot(contains('Продажа')));
    expect(remote.pulls, 0);
    final next = await create(sync, price: 2200);
    expect(next.clientId, first.clientId);
    await sync.sendQueueOperationById(
        key: 'POS-KEY', deviceId: 'DEVICE', operationId: first.operationId);
    expect(adapter.bodies, hasLength(1));
    expect(remote.pulls, 0);
    expect(
        db
            .select('SELECT response_json FROM refund_sync_attempts')
            .single['response_json'],
        contains('IDEMPOTENCY_CONFLICT'));
  });
  test('422 returns field errors and does not change stored request', () async {
    adapter.status = 422;
    adapter.response = {
      'error_code': 'VALIDATION_FAILED',
      'message': 'Проверьте поля',
      'errors': {
        'payments.0.account_id': ['Счёт недоступен'],
        'items.0.price': ['Неверная цена']
      }
    };
    final result = await create(sync);
    expect(result.result, QueueSendResult.manual);
    expect(result.fieldErrors['payments.0.account_id'], ['Счёт недоступен']);
    expect(result.errorMessage, contains('Счёт недоступен'));
    expect(result.errorMessage, contains('Неверная цена'));
    expect(remote.pulls, 0);
  });
  test('mismatched successful client_refund_id is not synced', () async {
    adapter.response = {
      'data': {'id': 'SERVER', 'client_refund_id': 'OTHER'}
    };
    final result = await create(sync);
    expect(result.result, QueueSendResult.manual);
    expect(
        await store.acceptedOperation(
            OutboxOperationType.refund, 'refund-test'),
        isNull);
  });
  test(
      'separate no-sale returns never reuse one another just because both have no sale ID',
      () async {
    adapter.timeout = true;
    final first = await create(sync, id: 'refund-one');
    final next = await create(sync, id: 'refund-two');
    expect(next.clientId, isNot(first.clientId));
    expect(adapter.bodies, hasLength(2));
  });
  for (final field in ['error_code', 'code']) {
    test('error parser supports $field', () {
      final options = RequestOptions(path: '/refunds');
      final error = DioException(
          requestOptions: options,
          response: Response(
              requestOptions: options,
              statusCode: 409,
              data: {field: 'IDEMPOTENCY_CONFLICT'}));
      expect(remote.extractErrorCode(error), 'IDEMPOTENCY_CONFLICT');
    });
  }
  test('only explicit nested store true permits no-sale refunds', () {
    for (final flag in [false, null, 'true', 1, true]) {
      final pos = PosProvisionResponse.fromJson({
        'data': {
          'id': 'POS',
          'name': 'Касса',
          'key': 'KEY',
          'account_id': 'CASH',
          'store_id': 'STORE',
          'organization_id': 'ORG',
          'allow_refunds_without_sale': true,
          'store': {'allow_refunds_without_sale': flag},
        }
      });
      expect(pos.allowRefundsWithoutSale, flag == true);
    }
  });
  test(
      'validation rejects mismatched money, excessive precision and mixed single payment',
      () {
    void validate(
            {num price = 10,
            num quantity = 1,
            num total = 10,
            num amount = 10,
            String method = 'cash'}) =>
        validateRefundWithoutSale(
            totalAmount: total,
            paymentMethod: method,
            items: [
              {'product_id': 'P', 'price': price, 'quantity': quantity}
            ],
            payments: [
              {
                'account_id': 'CASH',
                'client_payment_id': 'PAY',
                'amount': amount
              }
            ]);
    expect(() => validate(), returnsNormally);
    expect(() => validate(price: 10.001), throwsArgumentError);
    expect(() => validate(quantity: 1.0001), throwsArgumentError);
    expect(() => validate(total: 11), throwsArgumentError);
    expect(() => validate(amount: 9), throwsArgumentError);
    expect(() => validate(amount: 0), throwsArgumentError);
    expect(() => validate(method: 'mixed'), throwsArgumentError);
  });
}
