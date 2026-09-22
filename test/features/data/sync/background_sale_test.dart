import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/features/data/repositories/sale_repository_impl.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'marked_sale_sync_test.dart'
    show ScriptedRemote, sale, accepted, timeout, apiError;

void main() {
  test('ordinary payment is durable and completes before backend responds',
      () async {
    final database = sqlite3.openInMemory();
    final store = PosSyncLocalStore(database: database);
    final remote = ScriptedRemote();
    final sync = PosSyncService(store, remote);
    final started = Completer<void>();
    final response = Completer<void>();
    remote.handler = (payload) async {
      started.complete();
      await response.future;
      return accepted(payload, codes: []);
    };
    sync.startBackgroundLoops(key: 'KEY', deviceId: 'DEVICE');
    final repo = SaleRepositoryImpl(Object(), Object(), sync);
    try {
      final result = await repo
          .createSale(
              key: 'KEY',
              deviceId: 'DEVICE',
              sale: sale(),
              payments: [
                {'account_id': 'ACCOUNT', 'amount': 360}
              ],
              requireOnline: false)
          .timeout(const Duration(seconds: 2));
      expect(result.result, CreateSaleResult.queued);
      expect(result.retryScheduled, isTrue);
      expect(result.sale.number, isNotEmpty);
      expect(database.select('SELECT completed FROM sales').single['completed'],
          1);
      expect(
          await store.findOperation(OutboxOperationType.sale, sale().localId),
          isNotNull);
      await started.future.timeout(const Duration(seconds: 2));
      expect(response.isCompleted, isFalse);
      response.complete();
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      expect(
          (await store.findOperation(OutboxOperationType.sale, sale().localId))!
              .status,
          OutboxOperationStatus.acked);
      expect(remote.requests, hasLength(1));
    } finally {
      if (!response.isCompleted) response.complete();
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      sync.stopBackgroundLoops();
      await sync.dispose();
    }
  });

  test('queued payment survives restart and retries timeout with identical IDs',
      () async {
    final dir = await Directory.systemTemp.createTemp('background-sale-');
    final file = '${dir.path}/pos.sqlite';
    var store = PosSyncLocalStore(database: sqlite3.open(file));
    var remote = ScriptedRemote();
    var sync = PosSyncService(store, remote);
    try {
      final repo = SaleRepositoryImpl(Object(), Object(), sync);
      final result = await repo.createSale(
          key: 'KEY',
          deviceId: 'DEVICE',
          sale: sale(),
          payments: [
            {'account_id': 'ACCOUNT', 'amount': 360}
          ],
          requireOnline: false);
      final original =
          (await store.findOperation(OutboxOperationType.sale, sale().localId))!
              .payload;
      expect(result.result, CreateSaleResult.queued);
      expect(remote.requests, isEmpty);
      await sync.dispose();
      store = PosSyncLocalStore(database: sqlite3.open(file));
      remote = ScriptedRemote();
      sync = PosSyncService(store, remote);
      remote.handler = (_) async => throw timeout();
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      expect(
          remote.requests.single['client_sale_id'], original['client_sale_id']);
      remote.handler = (payload) async => accepted(payload, codes: []);
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      expect(remote.requests, hasLength(2));
      expect(remote.requests.last, remote.requests.first);
      expect(remote.requests.last['payments'], original['payments']);
      expect(remote.events, ['POST', 'PULL', 'POST']);
      expect(
          (await store.findOperation(OutboxOperationType.sale, sale().localId))!
              .status,
          OutboxOperationStatus.acked);
    } finally {
      await sync.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
      'interrupted background send reconciles on restart without duplicate POST',
      () async {
    final dir = await Directory.systemTemp.createTemp('interrupted-sale-');
    final file = '${dir.path}/pos.sqlite';
    var store = PosSyncLocalStore(database: sqlite3.open(file));
    var remote = ScriptedRemote();
    var sync = PosSyncService(store, remote);
    try {
      await SaleRepositoryImpl(Object(), Object(), sync).createSale(
          key: 'KEY',
          deviceId: 'DEVICE',
          sale: sale(),
          payments: [
            {'account_id': 'ACCOUNT', 'amount': 360}
          ],
          requireOnline: false);
      final sending = await store.claimSpecificPendingOperation(
          type: OutboxOperationType.sale, clientId: sale().localId);
      expect(sending!.status, OutboxOperationStatus.sending);
      await sync.dispose();
      store = PosSyncLocalStore(database: sqlite3.open(file));
      remote = ScriptedRemote();
      sync = PosSyncService(store, remote);
      remote.changes = [
        SyncPullChange(
            entity: 'sale',
            action: 'upsert',
            payload: accepted(sending.payload, codes: []))
      ];
      final restored =
          await store.findOperation(OutboxOperationType.sale, sale().localId);
      expect(restored!.status, OutboxOperationStatus.pending);
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      expect(remote.requests, isEmpty);
      expect(remote.events, ['PULL']);
      expect(
          (await store.findOperation(OutboxOperationType.sale, sale().localId))!
              .status,
          OutboxOperationStatus.acked);
    } finally {
      await sync.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('business rejection stays visible in queue and is not blindly retried',
      () async {
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    final remote = ScriptedRemote()
      ..handler = (_) async => throw apiError('INSUFFICIENT_STOCK');
    final sync = PosSyncService(store, remote);
    try {
      await SaleRepositoryImpl(Object(), Object(), sync).createSale(
          key: 'KEY',
          deviceId: 'DEVICE',
          sale: sale(),
          payments: [
            {'account_id': 'ACCOUNT', 'amount': 360}
          ],
          requireOnline: false);
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      final rejected =
          await store.findOperation(OutboxOperationType.sale, sale().localId);
      expect(rejected!.status, OutboxOperationStatus.manual);
      expect(rejected.lastErrorCode, 'INSUFFICIENT_STOCK');
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      expect(remote.requests, hasLength(1));
      expect(remote.requests.single.containsKey('_local_background_sale'),
          isFalse);
    } finally {
      await sync.dispose();
    }
  });
}
