import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/models/fiscalization_mode.dart';
import 'package:leemon_app/features/data/repositories/sale_repository_impl.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'marked_sale_sync_test.dart' show ScriptedRemote, sale, accepted;

class _CountingStore extends PosSyncLocalStore {
  _CountingStore(Database db) : super(database: db);
  int repairs = 0;
  @override
  Future<void> normalizeLegacySessionReferences() {
    repairs++;
    return super.normalizeLegacySessionReferences();
  }
}

class _SlowPullRemote extends ScriptedRemote {
  final started = Completer<void>();
  final response = Completer<SyncPullBatch>();
  @override
  Future<SyncPullBatch> pullChanges(
      {required String key, required int cursor, int limit = 500}) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

void main() {
  test('cash, manual card and mixed sales finish locally while HTTP is stalled',
      () async {
    final db = sqlite3.openInMemory();
    final store = PosSyncLocalStore(database: db);
    final remote = ScriptedRemote();
    final sending = Completer<void>();
    final response = Completer<void>();
    remote.handler = (payload) async {
      if (!sending.isCompleted) sending.complete();
      await response.future;
      return accepted(payload, codes: []);
    };
    final sync = PosSyncService(store, remote);
    sync.startBackgroundLoops(key: 'KEY', deviceId: 'DEVICE');
    final repo = SaleRepositoryImpl(Object(), Object(), sync);
    try {
      for (final method in ['cash', 'card', 'mixed']) {
        final result = await repo
            .createSale(
              key: 'KEY',
              deviceId: 'DEVICE',
              sale: sale().copyWith(
                  localId: 'offline-$method',
                  paymentMethod: method,
                  fiscalizationMode: FiscalizationMode.skip),
              payments: method == 'cash'
                  ? [
                      {'account_id': 'ACCOUNT', 'amount': 360}
                    ]
                  : method == 'card'
                      ? [
                          {'account_id': 'BANK', 'amount': 360}
                        ]
                      : [
                          {'account_id': 'ACCOUNT', 'amount': 100},
                          {'account_id': 'BANK', 'amount': 260}
                        ],
            )
            .timeout(const Duration(seconds: 1));
        expect(result.result, CreateSaleResult.queued);
        expect(result.retryScheduled, isTrue);
        if (method == 'cash') await sending.future;
        expect(response.isCompleted, isFalse);
      }
      expect(
          db.select('SELECT * FROM sales WHERE completed = 1'), hasLength(3));
      expect(remote.requests, hasLength(1));
    } finally {
      response.complete();
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      await sync.dispose();
    }
  });

  test('a growing offline queue is not reparsed on each checkout', () async {
    final db = sqlite3.openInMemory();
    final store = _CountingStore(db);
    addTearDown(store.close);
    db.execute('''INSERT INTO sessions
      (client_session_id, server_session_id, user_id, device_id, opened_at)
      VALUES ('legacy', 'server', 'USER', 'DEVICE', '2026-10-31')''');
    for (var i = 0; i < 500; i++) {
      await store.enqueueOperation(
          id: 'op-$i',
          type: OutboxOperationType.sale,
          clientId: '$i',
          payload: {'pos_session_id': 'legacy', 'items': []});
    }
    await store.ensureSyncState(posKey: 'KEY', deviceId: 'DEVICE');
    final changes = db.select('SELECT total_changes() AS n').single['n'];
    for (var i = 0; i < 40; i++) {
      await store.ensureSyncState(posKey: 'KEY', deviceId: 'DEVICE');
    }
    expect(store.repairs, 1);
    expect(db.select('SELECT total_changes() AS n').single['n'], changes);
    expect(
        (await store.findOperation(OutboxOperationType.sale, '0'))!
            .payload['pos_session_id'],
        'server');
    // New server bindings still repair existing queued references.
    db.execute('''INSERT INTO sessions
      (client_session_id, user_id, device_id, opened_at)
      VALUES ('later', 'USER', 'DEVICE', '2026-10-31')''');
    await store.enqueueOperation(id: 'later-op', type: OutboxOperationType.sale,
        clientId: 'later-sale', payload: {'pos_session_id': 'later'});
    await store.bindServerSessionId(
        clientSessionId: 'later', serverSessionId: 'new-server');
    expect(store.repairs, 2);
    expect((await store.findOperation(OutboxOperationType.sale, 'later-sale'))!
        .payload['pos_session_id'], 'new-server');
  });

  test('a stalled pull does not hold the sender or the next ordinary sale',
      () async {
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    final remote = _SlowPullRemote();
    remote.handler = (payload) async => accepted(payload, codes: []);
    final sync = PosSyncService(store, remote);
    sync.startBackgroundLoops(key: 'KEY', deviceId: 'DEVICE');
    final pull = sync.pullOnce(
        key: 'KEY', deviceId: 'DEVICE', refreshPosInfoAfterPull: false);
    final repo = SaleRepositoryImpl(Object(), Object(), sync);
    try {
      await remote.started.future;
      for (var i = 0; i < 2; i++) {
        final result = await repo.createSale(
            key: 'KEY',
            deviceId: 'DEVICE',
            sale: sale().copyWith(localId: 'slow-$i'),
            payments: [
              {'account_id': 'ACCOUNT', 'amount': 360}
            ]).timeout(const Duration(seconds: 1));
        expect(result.result, CreateSaleResult.queued);
        await sync
            .pushPending(key: 'KEY', deviceId: 'DEVICE')
            .timeout(const Duration(seconds: 1));
      }
      expect(remote.requests, hasLength(2));
      expect(remote.response.isCompleted, isFalse);
    } finally {
      remote.response.complete(
          const SyncPullBatch(items: [], nextCursor: 0, hasMore: false));
      await pull;
      await sync.pushPending(key: 'KEY', deviceId: 'DEVICE');
      await sync.dispose();
    }
  });
}
