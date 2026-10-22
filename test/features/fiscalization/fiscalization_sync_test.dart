import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/models/fiscalization_mode.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import '../data/sync/marked_sale_sync_test.dart'
    show ScriptedRemote, sale, accepted, timeout;

DioException fiscalRequired() {
  final request = RequestOptions(path: '/sales');
  return DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: request, statusCode: 422, data: {
        'errors': {
          'fiscalization_mode': [
            'Продажу с маркированным товаром нельзя провести без фискального чека.'
          ]
        }
      }));
}

void main() {
  late PosSyncLocalStore store;
  late ScriptedRemote remote;
  late PosSyncService sync;
  setUp(() {
    store = PosSyncLocalStore(database: sqlite3.openInMemory());
    remote = ScriptedRemote();
    sync = PosSyncService(store, remote);
  });
  tearDown(() => sync.dispose());
  Future<QueueOperationResult> send(FiscalizationMode mode,
          {bool background = false}) =>
      sync.createSale(
          key: 'KEY',
          deviceId: 'DEVICE',
          sale: sale().copyWith(fiscalizationMode: mode),
          payments: [
            {'account_id': 'ACCOUNT', 'amount': 360}
          ],
          requireOnline: !background,
          sendInBackground: background);
  test('422 keeps the selected mode and reports field validation', () async {
    remote.handler = (_) async => throw fiscalRequired();
    final result = await send(FiscalizationMode.skip);
    expect(result.result, QueueSendResult.manual);
    expect(remote.requests, hasLength(1));
    expect(result.fieldErrors, contains('fiscalization_mode'));
    expect(
        (await store.findOperation(OutboxOperationType.sale, sale().localId))!
            .payload['fiscalization_mode'],
        'skip');
  });
  test(
      'timeout retry preserves original mode despite caller changing selection',
      () async {
    remote.handler = (_) async => throw timeout();
    await send(FiscalizationMode.skip);
    remote.handler = (p) async => accepted(p, codes: []);
    await send(FiscalizationMode.fiscal);
    expect(remote.requests, hasLength(2));
    expect(remote.requests.last, remote.requests.first);
    expect(remote.requests.last['fiscalization_mode'], 'skip');
  });
  test('unknown result followed by 422 never changes mode or repeats POST',
      () async {
    remote.handler = (_) async => throw timeout();
    await send(FiscalizationMode.skip);
    remote.handler = (_) async => throw fiscalRequired();
    final result = await send(FiscalizationMode.fiscal);
    expect(result.result, QueueSendResult.manual);
    expect(remote.requests, hasLength(2));
    expect(remote.requests.every((r) => r['fiscalization_mode'] == 'skip'),
        isTrue);
  });
  test('automatic mode survives background persistence and delivery', () async {
    await send(FiscalizationMode.automatic, background: true);
    expect(remote.requests, isEmpty);
    expect((await store.loadPendingSales()).single.fiscalizationMode,
        FiscalizationMode.automatic);
    remote.handler = (p) async => accepted(p, codes: []);
    await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
    expect(remote.requests.single['fiscalization_mode'], 'automatic');
    expect(remote.requests.single['device_id'], 'DEVICE');
  });
}
