import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/sale_model.dart' show SaleItemModel, SaleModel;

import 'pos_sync_models.dart';

class PosSyncLocalStore {
  sqlite.Database? _db;

  Future<void> initialize() async {
    await _database;
  }

  Future<void> close() async {
    _db?.dispose();
    _db = null;
  }

  Future<sqlite.Database> get _database async {
    final current = _db;
    if (current != null) return current;

    final directory = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(directory.path, 'sync'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }

    final db = sqlite.sqlite3.open(p.join(dbDir.path, 'pos_sync.sqlite'));
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    _createSchema(db);
    _db = db;
    return db;
  }

  void _createSchema(sqlite.Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        pos_key TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        cursor INTEGER NOT NULL DEFAULT 0,
        last_bootstrap_at TEXT NULL,
        last_pull_at TEXT NULL,
        last_push_at TEXT NULL,
        last_error TEXT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS local_counters (
        name TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      );
    ''');

    db.execute('''
      INSERT OR IGNORE INTO local_counters (name, value)
      VALUES ('sale_local_number', 0);
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS pos_info (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        number TEXT NOT NULL,
        key TEXT NOT NULL,
        device_id TEXT NULL,
        account_id TEXT NULL,
        store_id TEXT NOT NULL,
        organization_id TEXT NOT NULL,
        raw_json TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        barcode TEXT NULL,
        sku TEXT NULL,
        price REAL NOT NULL DEFAULT 0,
        quantity REAL NOT NULL DEFAULT 0,
        measurement_unit TEXT NULL,
        cover_url TEXT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL,
        updated_at_local TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NULL,
        value REAL NULL,
        raw_json TEXT NOT NULL,
        updated_at_local TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS expense_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        raw_json TEXT NOT NULL,
        updated_at_local TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NULL,
        raw_json TEXT NOT NULL,
        updated_at_local TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS outbox_operations (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        client_id TEXT NOT NULL,
        related_client_id TEXT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error_code TEXT NULL,
        last_error_message TEXT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS outbox_operations_type_client_id_unique
      ON outbox_operations (type, client_id);
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS outbox_operations_status_created_at_idx
      ON outbox_operations (status, created_at);
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sales_history (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        raw_json TEXT NOT NULL,
        updated_at_local TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS sales_history_date_idx
      ON sales_history (date DESC);
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_errors (
        id TEXT PRIMARY KEY,
        operation_id TEXT NULL,
        error_code TEXT NOT NULL,
        error_message TEXT NOT NULL,
        payload_json TEXT NULL,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> clearAllLocalData() async {
    final db = await _database;
    _inTransaction(db, () {
      for (final table in const [
        'sync_state',
        'pos_info',
        'products',
        'accounts',
        'expense_types',
        'customers',
        'outbox_operations',
        'sync_errors',
        'sales_history',
      ]) {
        db.execute('DELETE FROM $table;');
      }
      db.execute("UPDATE local_counters SET value = 0 WHERE name = 'sale_local_number';");
    });
  }

  Future<void> ensureSyncState({
    required String posKey,
    required String deviceId,
  }) async {
    final db = await _database;
    final now = _nowIso();
    db.execute(
      '''
      INSERT INTO sync_state (
        pos_key, device_id, cursor, last_bootstrap_at, last_pull_at, last_push_at, last_error
      ) VALUES (?, ?, 0, NULL, NULL, NULL, NULL)
      ON CONFLICT(pos_key) DO UPDATE SET
        device_id = excluded.device_id
      ''',
      [posKey, deviceId],
    );
    db.execute(
      '''
      UPDATE sync_state
      SET device_id = ?, last_error = NULL
      WHERE pos_key = ?
      ''',
      [deviceId, posKey],
    );
    db.execute(
      "INSERT OR IGNORE INTO local_counters (name, value) VALUES ('sale_local_number', 0);",
    );
    db.execute(
      '''
      UPDATE outbox_operations
      SET status = ?, updated_at = ?
      WHERE status = ?
      ''',
      [
        OutboxOperationStatus.pending.value,
        now,
        OutboxOperationStatus.sending.value,
      ],
    );
  }

  Future<SyncStateSnapshot?> loadSyncState(String posKey) async {
    final db = await _database;
    final row = _firstRow(
      db.select('SELECT * FROM sync_state WHERE pos_key = ? LIMIT 1', [posKey]),
    );
    if (row == null) return null;
    return SyncStateSnapshot(
      posKey: (row['pos_key'] ?? '').toString(),
      deviceId: (row['device_id'] ?? '').toString(),
      cursor: _asInt(row['cursor']),
      lastBootstrapAt: _parseDt(row['last_bootstrap_at']),
      lastPullAt: _parseDt(row['last_pull_at']),
      lastPushAt: _parseDt(row['last_push_at']),
      lastError: row['last_error']?.toString(),
    );
  }

  Future<void> recordSyncError({
    required String posKey,
    required String message,
  }) async {
    final db = await _database;
    db.execute(
      'UPDATE sync_state SET last_error = ? WHERE pos_key = ?',
      [message, posKey],
    );
  }

  Future<int> nextLocalSaleNumber() async {
    final db = await _database;
    return _inTransaction<int>(db, () {
      final row = _firstRow(
        db.select(
          'SELECT value FROM local_counters WHERE name = ? LIMIT 1',
          ['sale_local_number'],
        ),
      );
      final next = _asInt(row?['value']) + 1;
      db.execute(
        '''
        INSERT INTO local_counters (name, value)
        VALUES (?, ?)
        ON CONFLICT(name) DO UPDATE SET value = excluded.value
        ''',
        ['sale_local_number', next],
      );
      return next;
    });
  }

  Future<void> replaceBootstrapData({
    required String posKey,
    required String deviceId,
    required int cursorBefore,
    required Map<String, dynamic> posInfo,
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> expenseTypes,
    required List<Map<String, dynamic>> customers,
  }) async {
    final db = await _database;
    final now = _nowIso();
    _inTransaction<void>(db, () {
      db.execute('DELETE FROM pos_info;');
      db.execute('DELETE FROM products;');
      db.execute('DELETE FROM accounts;');
      db.execute('DELETE FROM expense_types;');
      db.execute('DELETE FROM customers;');

      final posRow = _mapPosInfoRow(posInfo);
      if (posRow != null) {
        _upsertRow(db, 'pos_info', posRow);
      }

      for (final raw in products) {
        final row = _mapProductRow(raw, now);
        if (row != null) _upsertRow(db, 'products', row);
      }
      for (final raw in accounts) {
        final row = _mapAccountRow(raw, now);
        if (row != null) _upsertRow(db, 'accounts', row);
      }
      for (final raw in expenseTypes) {
        final row = _mapExpenseTypeRow(raw, now);
        if (row != null) _upsertRow(db, 'expense_types', row);
      }
      for (final raw in customers) {
        final row = _mapCustomerRow(raw, now);
        if (row != null) _upsertRow(db, 'customers', row);
      }

      db.execute(
        '''
        INSERT INTO sync_state (
          pos_key, device_id, cursor, last_bootstrap_at, last_pull_at, last_push_at, last_error
        ) VALUES (?, ?, ?, ?, NULL, NULL, NULL)
        ON CONFLICT(pos_key) DO UPDATE SET
          device_id = excluded.device_id,
          cursor = excluded.cursor,
          last_bootstrap_at = excluded.last_bootstrap_at,
          last_error = NULL
        ''',
        [posKey, deviceId, cursorBefore, now],
      );
    });
  }

  Future<void> applyPullBatch({
    required String posKey,
    required List<SyncPullChange> changes,
    required int nextCursor,
  }) async {
    final db = await _database;
    final now = _nowIso();
    _inTransaction<void>(db, () {
      for (final change in changes) {
        _applyPullChange(db, change, now);
      }
      db.execute(
        '''
        UPDATE sync_state
        SET cursor = ?, last_pull_at = ?, last_error = NULL
        WHERE pos_key = ?
        ''',
        [nextCursor, now, posKey],
      );
    });
  }

  Future<List<ProductModel>> loadProducts() async {
    final db = await _database;
    final rows = db.select('SELECT raw_json FROM products ORDER BY name COLLATE NOCASE;');
    return rows
        .map((row) => ProductModel.fromJson(decodeJsonMap((row['raw_json'] ?? '{}').toString())))
        .toList(growable: false);
  }

  Future<List<ProductModel>> loadFavoriteProducts() async {
    final db = await _database;
    final rows = db.select(
      '''
      SELECT raw_json
      FROM products
      WHERE is_favorite = 1
      ORDER BY name COLLATE NOCASE
      ''',
    );
    return rows
        .map((row) => ProductModel.fromJson(decodeJsonMap((row['raw_json'] ?? '{}').toString())))
        .toList(growable: false);
  }

  Future<List<LocalExpenseType>> loadExpenseTypes() async {
    final db = await _database;
    final rows = db.select('SELECT id, name, raw_json FROM expense_types ORDER BY name COLLATE NOCASE;');
    return rows
        .map(
          (row) => LocalExpenseType(
            id: (row['id'] ?? '').toString(),
            name: (row['name'] ?? '').toString(),
            rawJson: decodeJsonMap((row['raw_json'] ?? '{}').toString()),
          ),
        )
        .toList(growable: false);
  }

  Future<List<LocalCustomer>> loadCustomers() async {
    final db = await _database;
    final rows = db.select('SELECT id, name, phone, raw_json FROM customers ORDER BY name COLLATE NOCASE;');
    return rows
        .map(
          (row) => LocalCustomer(
            id: (row['id'] ?? '').toString(),
            name: (row['name'] ?? '').toString(),
            phone: (row['phone'] ?? '').toString(),
            rawJson: decodeJsonMap((row['raw_json'] ?? '{}').toString()),
          ),
        )
        .toList(growable: false);
  }

  Future<void> enqueueOperation({
    required String id,
    required OutboxOperationType type,
    required String clientId,
    required Map<String, dynamic> payload,
    String? relatedClientId,
  }) async {
    final db = await _database;
    final now = _nowIso();
    db.execute(
      '''
      INSERT INTO outbox_operations (
        id, type, client_id, related_client_id, payload_json, status,
        retry_count, last_error_code, last_error_message, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?, ?)
      ON CONFLICT(type, client_id) DO UPDATE SET
        related_client_id = excluded.related_client_id,
        payload_json = excluded.payload_json,
        status = CASE
          WHEN outbox_operations.status = ? THEN outbox_operations.status
          ELSE ?
        END,
        updated_at = excluded.updated_at
      ''',
      [
        id,
        type.value,
        clientId,
        relatedClientId,
        jsonEncode(payload),
        OutboxOperationStatus.pending.value,
        now,
        now,
        OutboxOperationStatus.acked.value,
        OutboxOperationStatus.pending.value,
      ],
    );
  }

  Future<OutboxOperationRecord?> claimSpecificPendingOperation({
    required OutboxOperationType type,
    required String clientId,
  }) async {
    final db = await _database;
    return _inTransaction<OutboxOperationRecord?>(db, () {
      final row = _firstRow(
        db.select(
          '''
          SELECT *
          FROM outbox_operations
          WHERE type = ? AND client_id = ? AND status = ?
          LIMIT 1
          ''',
          [type.value, clientId, OutboxOperationStatus.pending.value],
        ),
      );
      if (row == null) return null;
      final now = _nowIso();
      db.execute(
        '''
        UPDATE outbox_operations
        SET status = ?, updated_at = ?
        WHERE id = ?
        ''',
        [OutboxOperationStatus.sending.value, now, row['id']],
      );
      return _recordFromRow({...row, 'status': OutboxOperationStatus.sending.value, 'updated_at': now});
    });
  }

  Future<List<OutboxOperationRecord>> claimPendingOperations({int limit = 5}) async {
    final db = await _database;
    return _inTransaction<List<OutboxOperationRecord>>(db, () {
      final rows = db.select(
        '''
        SELECT *
        FROM outbox_operations
        WHERE status = ?
        ORDER BY created_at ASC
        LIMIT ?
        ''',
        [OutboxOperationStatus.pending.value, limit],
      );
      if (rows.isEmpty) return const [];

      final now = _nowIso();
      final result = <OutboxOperationRecord>[];
      for (final raw in rows) {
        final row = _rowMap(raw);
        db.execute(
          '''
          UPDATE outbox_operations
          SET status = ?, updated_at = ?
          WHERE id = ?
          ''',
          [OutboxOperationStatus.sending.value, now, row['id']],
        );
        result.add(
          _recordFromRow({
            ...row,
            'status': OutboxOperationStatus.sending.value,
            'updated_at': now,
          }),
        );
      }
      return result;
    });
  }

  Future<void> markOperationAcked(String operationId) async {
    final db = await _database;
    final now = _nowIso();
    db.execute(
      '''
      UPDATE outbox_operations
      SET status = ?, last_error_code = NULL, last_error_message = NULL, updated_at = ?
      WHERE id = ?
      ''',
      [OutboxOperationStatus.acked.value, now, operationId],
    );
  }

  Future<void> markOperationPending({
    required String operationId,
    String? errorCode,
    String? errorMessage,
  }) async {
    final db = await _database;
    final now = _nowIso();
    db.execute(
      '''
      UPDATE outbox_operations
      SET status = ?,
          retry_count = retry_count + 1,
          last_error_code = ?,
          last_error_message = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        OutboxOperationStatus.pending.value,
        errorCode,
        errorMessage,
        now,
        operationId,
      ],
    );
  }

  Future<void> markOperationManual({
    required String operationId,
    required String errorCode,
    required String errorMessage,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _database;
    final now = _nowIso();
    _inTransaction<void>(db, () {
      db.execute(
        '''
        UPDATE outbox_operations
        SET status = ?, last_error_code = ?, last_error_message = ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          OutboxOperationStatus.manual.value,
          errorCode,
          errorMessage,
          now,
          operationId,
        ],
      );
      db.execute(
        '''
        INSERT INTO sync_errors (
          id, operation_id, error_code, error_message, payload_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
        [
          '${operationId}_$now',
          operationId,
          errorCode,
          errorMessage,
          jsonEncode(payload),
          now,
        ],
      );
    });
  }

  Future<void> touchLastPush(String posKey) async {
    final db = await _database;
    db.execute(
      '''
      UPDATE sync_state
      SET last_push_at = ?, last_error = NULL
      WHERE pos_key = ?
      ''',
      [_nowIso(), posKey],
    );
  }

  Future<List<SaleModel>> loadPendingSales() async {
    final db = await _database;
    final rows = db.select(
      '''
      SELECT payload_json
      FROM outbox_operations
      WHERE type = ? AND status IN (?, ?)
      ORDER BY created_at ASC
      ''',
      [
        OutboxOperationType.sale.value,
        OutboxOperationStatus.pending.value,
        OutboxOperationStatus.sending.value,
      ],
    );
    return rows
        .map((row) => _saleFromPayload(decodeJsonMap((row['payload_json'] ?? '{}').toString())))
        .toList(growable: false);
  }

  Future<List<QueueListItem>> loadQueueItems() async {
    final db = await _database;
    final rows = db.select(
      '''
      SELECT *
      FROM outbox_operations
      WHERE status IN (?, ?, ?)
      ORDER BY created_at ASC
      ''',
      [
        OutboxOperationStatus.pending.value,
        OutboxOperationStatus.sending.value,
        OutboxOperationStatus.manual.value,
      ],
    );
    return rows.map((row) => _queueItemFromRow(_rowMap(row))).toList(growable: false);
  }

  void _applyPullChange(
    sqlite.Database db,
    SyncPullChange change,
    String now,
  ) {
    final entity = _normalizeEntity(change.entity);
    if (entity == null) return;

    final action = change.action.trim().toLowerCase();
    if (action == 'delete') {
      final targetId = (change.targetId ?? change.payload?['id'])?.toString() ?? '';
      if (targetId.isEmpty) return;
      db.execute('DELETE FROM ${entity.table} WHERE id = ?', [targetId]);
      return;
    }

    if (action != 'upsert' && action != 'insert' && action != 'update') {
      return;
    }

    final payload = change.payload;
    if (payload == null) return;

    final row = switch (entity) {
      _EntityKind.posInfo => _mapPosInfoRow(payload),
      _EntityKind.product => _mapProductRow(payload, now),
      _EntityKind.account => _mapAccountRow(payload, now),
      _EntityKind.expenseType => _mapExpenseTypeRow(payload, now),
      _EntityKind.customer => _mapCustomerRow(payload, now),
    };

    if (row == null) return;
    _upsertRow(db, entity.table, row);
  }

  void _upsertRow(
    sqlite.Database db,
    String table,
    Map<String, dynamic> row,
  ) {
    final columns = row.keys.toList(growable: false);
    final values = columns.map((column) => row[column]).toList(growable: false);
    final placeholders = List.filled(columns.length, '?').join(', ');
    final updates = columns
        .where((column) => column != 'id' && column != 'pos_key')
        .map((column) => '$column = excluded.$column')
        .join(', ');

    db.execute(
      '''
      INSERT INTO $table (${columns.join(', ')})
      VALUES ($placeholders)
      ON CONFLICT(${columns.contains('pos_key') ? 'pos_key' : 'id'})
      DO UPDATE SET $updates
      ''',
      values,
    );
  }

  T _inTransaction<T>(sqlite.Database db, T Function() action) {
    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final result = action();
      db.execute('COMMIT;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? _mapPosInfoRow(Map<String, dynamic> raw) {
    final id = _string(raw['id']);
    final key = _string(raw['key']);
    final storeId = _string(raw['store_id']);
    final organizationId = _string(raw['organization_id']);
    if (id.isEmpty || key.isEmpty || storeId.isEmpty || organizationId.isEmpty) {
      return null;
    }
    return {
      'id': id,
      'name': _string(raw['name'], fallback: 'POS'),
      'number': _string(raw['number'], fallback: key),
      'key': key,
      'device_id': _nullableString(raw['device_id']),
      'account_id': _nullableString(raw['account_id']),
      'store_id': storeId,
      'organization_id': organizationId,
      'raw_json': jsonEncode(raw),
    };
  }

  Map<String, dynamic>? _mapProductRow(Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return {
      'id': id,
      'name': _string(raw['name'], fallback: id),
      'barcode': _nullableString(raw['barcode']),
      'sku': _nullableString(raw['sku'] ?? raw['local_barcode']),
      'price': _asDouble(raw['selling_price'] ?? raw['price']),
      'quantity': _asDouble(raw['quantity']),
      'measurement_unit': _nullableString(raw['measurement_unit']),
      'cover_url': _nullableString(raw['cover_url']),
      'is_favorite': _asBoolInt(raw['is_favorite']),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  Map<String, dynamic>? _mapAccountRow(Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return {
      'id': id,
      'name': _string(raw['name'], fallback: id),
      'type': _nullableString(raw['type']),
      'value': raw['value'] == null ? null : _asDouble(raw['value']),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  Map<String, dynamic>? _mapExpenseTypeRow(Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return {
      'id': id,
      'name': _string(raw['name'], fallback: id),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  Map<String, dynamic>? _mapCustomerRow(Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return {
      'id': id,
      'name': _string(raw['name'], fallback: id),
      'phone': _nullableString(raw['phone']),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  QueueListItem _queueItemFromRow(Map<String, dynamic> row) {
    final type = OutboxOperationTypeX.fromValue((row['type'] ?? '').toString()) ??
        OutboxOperationType.sale;
    final payload = decodeJsonMap((row['payload_json'] ?? '{}').toString());
    final title = switch (type) {
      OutboxOperationType.sale =>
        'Чек №${payload['local_number'] ?? payload['client_sale_id'] ?? row['client_id']}',
      OutboxOperationType.payment => 'Платеж ${payload['amount'] ?? ''}'.trim(),
      OutboxOperationType.refund => 'Возврат ${payload['sale_id'] ?? row['client_id']}',
      OutboxOperationType.sessionOpen => 'Открытие смены',
      OutboxOperationType.sessionClose => 'Закрытие смены',
    };
    final subtitle = switch ((row['status'] ?? '').toString()) {
      'manual' => (row['last_error_message'] ?? 'Требуется ручная обработка').toString(),
      'sending' => 'Отправляется...',
      _ => 'Ждет отправки',
    };

    return QueueListItem(
      id: (row['id'] ?? '').toString(),
      type: type,
      clientId: (row['client_id'] ?? '').toString(),
      status: OutboxOperationStatusX.fromValue((row['status'] ?? '').toString()) ??
          OutboxOperationStatus.pending,
      createdAt: _parseDt(row['created_at']) ?? DateTime.now(),
      title: title,
      subtitle: subtitle,
      errorCode: row['last_error_code']?.toString(),
      errorMessage: row['last_error_message']?.toString(),
    );
  }

  OutboxOperationRecord _recordFromRow(Map<String, dynamic> row) {
    return OutboxOperationRecord(
      id: (row['id'] ?? '').toString(),
      type: OutboxOperationTypeX.fromValue((row['type'] ?? '').toString()) ??
          OutboxOperationType.sale,
      clientId: (row['client_id'] ?? '').toString(),
      relatedClientId: row['related_client_id']?.toString(),
      payload: decodeJsonMap((row['payload_json'] ?? '{}').toString()),
      status: OutboxOperationStatusX.fromValue((row['status'] ?? '').toString()) ??
          OutboxOperationStatus.pending,
      retryCount: _asInt(row['retry_count']),
      lastErrorCode: row['last_error_code']?.toString(),
      lastErrorMessage: row['last_error_message']?.toString(),
      createdAt: _parseDt(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDt(row['updated_at']) ?? DateTime.now(),
    );
  }

  SaleModel _saleFromPayload(Map<String, dynamic> payload) {
    final itemsRaw = payload['items'];
    final items = (itemsRaw is List)
        ? itemsRaw
            .whereType<Map>()
            .map((item) {
              final map = Map<String, dynamic>.from(item);
              return SaleItemModel(
                id: (map['sale_item_id'] ?? '').toString(),
                saleId: (payload['client_sale_id'] ?? '').toString(),
                productId: (map['product_id'] ?? '').toString(),
                quantity: _asInt(map['quantity']),
                price: _asInt(map['price']),
                totalPrice: _asInt(map['total_price']),
              );
            })
            .toList()
        : <SaleItemModel>[];

    return SaleModel(
      localId: (payload['client_sale_id'] ?? '').toString(),
      number: (payload['local_number'] ?? '').toString(),
      date: _parseDt(payload['date']) ?? DateTime.now(),
      totalAmount: _asInt(payload['total_amount']),
      paymentMethod: (payload['payment_method'] ?? 'cash').toString(),
      posId: (payload['pos_id'] ?? '').toString(),
      storeId: (payload['store_id'] ?? '').toString(),
      userId: (payload['user_id'] ?? '').toString(),
      accountId: (payload['account_id'] ?? '').toString(),
      customerId: payload['customer_id']?.toString(),
      items: items,
    );
  }

  /// Upsert a batch of sales into local history (from API or after ack).
  Future<void> upsertSalesHistory(List<SaleModel> sales) async {
    if (sales.isEmpty) return;
    final db = await _database;
    final now = _nowIso();
    _inTransaction(db, () {
      for (final sale in sales) {
        final id = sale.localId.trim();
        if (id.isEmpty) continue;
        db.execute(
          '''
          INSERT INTO sales_history (id, date, raw_json, updated_at_local)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            date = excluded.date,
            raw_json = excluded.raw_json,
            updated_at_local = excluded.updated_at_local
          ''',
          [id, sale.date.toIso8601String(), jsonEncode(sale.toJson()), now],
        );
      }
    });
  }

  /// Save a sale from outbox payload (called after ack).
  Future<void> upsertSaleFromOutboxPayload(Map<String, dynamic> payload) async {
    final sale = _saleFromPayload(payload);
    if (sale.localId.isEmpty) return;
    await upsertSalesHistory([sale]);
  }

  /// Returns paginated sales from local history, newest first.
  Future<({List<SaleModel> items, int total})> loadSalesHistoryPage({
    int page = 1,
    int perPage = 15,
  }) async {
    final db = await _database;
    final countRow = _firstRow(db.select('SELECT COUNT(*) AS c FROM sales_history'));
    final total = _asInt(countRow?['c']);

    final offset = (page - 1) * perPage;
    final rows = db.select(
      'SELECT raw_json FROM sales_history ORDER BY date DESC LIMIT ? OFFSET ?',
      [perPage, offset],
    );

    final items = rows.map((row) {
      try {
        return SaleModel.fromJson(decodeJsonMap((row['raw_json'] ?? '{}').toString()));
      } catch (_) {
        return null;
      }
    }).whereType<SaleModel>().toList(growable: false);

    return (items: items, total: total);
  }

  Map<String, dynamic>? _firstRow(sqlite.ResultSet result) {
    if (result.isEmpty) return null;
    return _rowMap(result.first);
  }

  Map<String, dynamic> _rowMap(sqlite.Row row) {
    final map = <String, dynamic>{};
    for (final column in row.keys) {
      map[column] = row[column];
    }
    return map;
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
  }

  int _asBoolInt(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value != 0 ? 1 : 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return 1;
    }
    return 0;
  }

  String _string(dynamic value, {String fallback = ''}) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  String? _nullableString(dynamic value) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? null : result;
  }

  DateTime? _parseDt(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw);
  }

  String _nowIso() => DateTime.now().toIso8601String();

  _EntityKind? _normalizeEntity(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'pos':
      case 'pos_info':
      case 'pos-info':
        return _EntityKind.posInfo;
      case 'product':
      case 'products':
        return _EntityKind.product;
      case 'account':
      case 'accounts':
        return _EntityKind.account;
      case 'expense_type':
      case 'expense-type':
      case 'expense_types':
      case 'expense-types':
        return _EntityKind.expenseType;
      case 'customer':
      case 'customers':
        return _EntityKind.customer;
    }
    return null;
  }
}

enum _EntityKind {
  posInfo('pos_info'),
  product('products'),
  account('accounts'),
  expenseType('expense_types'),
  customer('customers');

  const _EntityKind(this.table);
  final String table;
}
