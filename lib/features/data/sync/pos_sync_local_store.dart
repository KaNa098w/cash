import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/sale_model.dart'
    show SaleItemModel, SaleModel;
import 'package:leemon_app/core/models/sale_model.dart' as sale_models
    show ProductModel, SalePaymentModel;

import 'pos_sync_models.dart';

class _SalePaymentAmounts {
  const _SalePaymentAmounts({
    this.cash = 0,
    this.card = 0,
    this.transfer = 0,
    this.credit = 0,
  });

  final num cash;
  final num card;
  final num transfer;
  final num credit;

  num get total => cash + card + transfer + credit;

  _SalePaymentAmounts copyWith({
    num? cash,
    num? card,
    num? transfer,
    num? credit,
  }) {
    return _SalePaymentAmounts(
      cash: cash ?? this.cash,
      card: card ?? this.card,
      transfer: transfer ?? this.transfer,
      credit: credit ?? this.credit,
    );
  }
}

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
    // FULL asks the OS to flush committed WAL transactions to durable storage.
    // This is intentionally preferred for a POS where sudden power loss is
    // more costly than the small write-performance difference from NORMAL.
    db.execute('PRAGMA synchronous = FULL;');
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA foreign_keys = ON;');
    _createSchema(db);
    _migrateSchema(db);
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
        logo_url TEXT NULL,
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
      CREATE TABLE IF NOT EXISTS product_id_mappings (
        local_id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        created_at TEXT NOT NULL
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

    db.execute('''
      CREATE TABLE IF NOT EXISTS return_access_keys (
        id               TEXT PRIMARY KEY,
        key              TEXT NOT NULL,
        user_id          TEXT,
        store_id         TEXT,
        expires_at       TEXT,
        is_active        INTEGER NOT NULL DEFAULT 1,
        raw_json         TEXT NOT NULL,
        updated_at_local TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id                   TEXT PRIMARY KEY,
        client_session_id    TEXT UNIQUE NOT NULL,
        server_session_id    TEXT,
        user_id              TEXT NOT NULL,
        device_id            TEXT NOT NULL,
        opening_cash_amount  REAL NOT NULL DEFAULT 0,
        closing_cash_amount  REAL,
        opened_at            TEXT NOT NULL,
        closed_at            TEXT,
        is_opened            INTEGER NOT NULL DEFAULT 1,
        synced               INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id              TEXT PRIMARY KEY,
        client_sale_id  TEXT UNIQUE NOT NULL,
        pos_session_id  TEXT,
        local_number    INTEGER NOT NULL,
        number          TEXT,
        date            TEXT NOT NULL,
        total_amount    REAL NOT NULL,
        payment_method  TEXT NOT NULL,
        cash_amount     REAL NOT NULL DEFAULT 0,
        card_amount     REAL NOT NULL DEFAULT 0,
        transfer_amount REAL NOT NULL DEFAULT 0,
        credit_amount   REAL NOT NULL DEFAULT 0,
        pos_id          TEXT,
        store_id        TEXT,
        account_id      TEXT,
        customer_id     TEXT,
        created_by_id   TEXT,
        completed       INTEGER NOT NULL DEFAULT 1,
        synced          INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id          TEXT PRIMARY KEY,
        sale_id     TEXT NOT NULL,
        product_id  TEXT NOT NULL,
        product_name TEXT,
        quantity    REAL NOT NULL,
        price       REAL NOT NULL,
        total_price REAL NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx
      ON sale_items (sale_id);
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS payments (
        id                TEXT PRIMARY KEY,
        client_payment_id TEXT UNIQUE NOT NULL,
        pos_session_id    TEXT,
        is_expense        INTEGER NOT NULL,
        amount            REAL NOT NULL,
        date              TEXT NOT NULL,
        account_id        TEXT,
        expense_type_id   TEXT,
        created_by_id     TEXT,
        synced            INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS refunds (
        id               TEXT PRIMARY KEY,
        client_refund_id TEXT UNIQUE NOT NULL,
        pos_session_id   TEXT,
        client_sale_id   TEXT,
        sale_id          TEXT,
        date             TEXT NOT NULL,
        total_amount     REAL NOT NULL,
        pos_id           TEXT,
        store_id         TEXT,
        account_id       TEXT,
        reason           TEXT,
        reason_code      TEXT,
        note             TEXT,
        return_key_used  TEXT,
        synced           INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS refund_items (
        id         TEXT PRIMARY KEY,
        refund_id  TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity   REAL NOT NULL,
        price      REAL NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS refund_items_refund_id_idx
      ON refund_items (refund_id);
    ''');
  }

  void _migrateSchema(sqlite.Database db) {
    // products: add columns added in spec v2
    for (final stmt in [
      'ALTER TABLE sales ADD COLUMN pos_id TEXT NULL',
      'ALTER TABLE sessions ADD COLUMN server_session_id TEXT NULL',
      'ALTER TABLE sales ADD COLUMN pos_session_id TEXT NULL',
      'ALTER TABLE sales ADD COLUMN store_id TEXT NULL',
      'ALTER TABLE sales ADD COLUMN completed INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE sales ADD COLUMN cash_amount REAL NOT NULL DEFAULT 0',
      'ALTER TABLE sales ADD COLUMN card_amount REAL NOT NULL DEFAULT 0',
      'ALTER TABLE sales ADD COLUMN transfer_amount REAL NOT NULL DEFAULT 0',
      'ALTER TABLE sales ADD COLUMN credit_amount REAL NOT NULL DEFAULT 0',
      'ALTER TABLE sale_items ADD COLUMN product_name TEXT NULL',
      'ALTER TABLE payments ADD COLUMN pos_session_id TEXT NULL',
      'ALTER TABLE refunds ADD COLUMN pos_session_id TEXT NULL',
      'ALTER TABLE refunds ADD COLUMN pos_id TEXT NULL',
      'ALTER TABLE refunds ADD COLUMN store_id TEXT NULL',
      'ALTER TABLE refunds ADD COLUMN account_id TEXT NULL',
      'ALTER TABLE refunds ADD COLUMN note TEXT NULL',
      'ALTER TABLE refunds ADD COLUMN reason_code TEXT NULL',
      'ALTER TABLE products ADD COLUMN local_barcode TEXT NULL',
      'ALTER TABLE products ADD COLUMN category_id TEXT NULL',
      'ALTER TABLE products ADD COLUMN category_name TEXT NULL',
      'ALTER TABLE products ADD COLUMN arrival_cost REAL NULL',
      'ALTER TABLE products ADD COLUMN wholesale_price REAL NULL',
      'ALTER TABLE products ADD COLUMN conversion_value REAL NULL',
    ]) {
      try {
        db.execute(stmt);
      } catch (_) {}
    }
    // accounts
    for (final stmt in [
      'ALTER TABLE accounts ADD COLUMN allow_negative INTEGER DEFAULT 0',
      'ALTER TABLE accounts ADD COLUMN visible_to_pos INTEGER DEFAULT 1',
      'ALTER TABLE accounts ADD COLUMN organization_id TEXT NULL',
      'ALTER TABLE accounts ADD COLUMN logo_url TEXT NULL',
    ]) {
      try {
        db.execute(stmt);
      } catch (_) {}
    }
    // expense_types
    for (final stmt in [
      'ALTER TABLE expense_types ADD COLUMN is_active INTEGER DEFAULT 1',
      'ALTER TABLE expense_types ADD COLUMN organization_id TEXT NULL',
    ]) {
      try {
        db.execute(stmt);
      } catch (_) {}
    }
    // customers
    for (final stmt in [
      'ALTER TABLE customers ADD COLUMN note TEXT NULL',
      'ALTER TABLE customers ADD COLUMN store_id TEXT NULL',
      'ALTER TABLE customers ADD COLUMN organization_id TEXT NULL',
    ]) {
      try {
        db.execute(stmt);
      } catch (_) {}
    }
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
        'sales_history',
        'return_access_keys',
        'sessions',
        'sales',
        'sale_items',
        'payments',
        'refunds',
        'refund_items',
      ]) {
        db.execute('DELETE FROM $table;');
      }
      db.execute(
          "UPDATE local_counters SET value = 0 WHERE name = 'sale_local_number';");
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
    await normalizeLegacySessionReferences();
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

  /// Returns what the NEXT receipt number will be (current + 1), without incrementing.
  Future<int> peekNextLocalSaleNumber() async {
    final db = await _database;
    return _readSaleLocalCounter(db) + 1;
  }

  Future<int> nextLocalSaleNumber() async {
    final db = await _database;
    return _inTransaction<int>(db, () {
      _syncSaleLocalCounter(db);
      final next = _readSaleLocalCounter(db) + 1;
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

  int _readSaleLocalCounter(sqlite.Database db) {
    final row = _firstRow(
      db.select(
        'SELECT value FROM local_counters WHERE name = ? LIMIT 1',
        ['sale_local_number'],
      ),
    );
    return _asInt(row?['value']);
  }

  int _parseLocalSaleNumber(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return 0;

    final matches = RegExp(r'\d+').allMatches(value).toList(growable: false);
    if (matches.isEmpty) return 0;

    final lastDigits = matches.last.group(0) ?? '';
    return int.tryParse(lastDigits) ?? 0;
  }

  int _resolveMaxKnownSaleNumber(sqlite.Database db) {
    final salesRow = _firstRow(
      db.select(
        '''
        SELECT
          MAX(local_number) AS max_local_number
        FROM sales
        ''',
      ),
    );

    var maxKnown = _asInt(salesRow?['max_local_number']);

    final saleNumberRows = db.select('SELECT number FROM sales');
    for (final row in saleNumberRows) {
      final parsed = _parseLocalSaleNumber(row['number']);
      if (parsed > maxKnown) {
        maxKnown = parsed;
      }
    }

    final historyRows = db.select('SELECT raw_json FROM sales_history');
    for (final row in historyRows) {
      final raw = (row['raw_json'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final json = decodeJsonMap(raw);
        final parsed = _parseLocalSaleNumber(json['number']);
        if (parsed > maxKnown) {
          maxKnown = parsed;
        }
      } catch (_) {
        // Ignore malformed cached rows and keep the best known number.
      }
    }

    return maxKnown;
  }

  void _syncSaleLocalCounter(sqlite.Database db) {
    final current = _readSaleLocalCounter(db);
    final maxKnown = _resolveMaxKnownSaleNumber(db);
    if (maxKnown <= current) return;

    db.execute(
      '''
      INSERT INTO local_counters (name, value)
      VALUES (?, ?)
      ON CONFLICT(name) DO UPDATE SET value = excluded.value
      ''',
      ['sale_local_number', maxKnown],
    );
  }

  Future<void> syncSaleLocalCounter() async {
    final db = await _database;
    _inTransaction<void>(db, () {
      _syncSaleLocalCounter(db);
    });
  }

  Future<void> replaceBootstrapData({
    required String posKey,
    required String deviceId,
    required int cursorBefore,
    required Map<String, dynamic> posInfo,
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> refunds,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> expenseTypes,
    required List<Map<String, dynamic>> customers,
  }) async {
    final db = await _database;
    final now = _nowIso();
    var maxBootstrapSaleNumber = 0;
    _inTransaction<void>(db, () {
      db.execute('DELETE FROM pos_info;');
      db.execute('DELETE FROM products;');
      db.execute('DELETE FROM accounts;');
      db.execute('DELETE FROM expense_types;');
      db.execute('DELETE FROM customers;');
      db.execute('DELETE FROM return_access_keys;');
      db.execute('DELETE FROM sales_history;');
      db.execute('DELETE FROM refunds;');
      db.execute('DELETE FROM refund_items;');

      final posRow = _mapPosInfoRow(posInfo);
      if (posRow != null) {
        _upsertRow(db, 'pos_info', posRow);
      }
      _upsertReturnAccessKeysFromPosInfo(db, posInfo, now);

      for (final raw in products) {
        final row = _mapProductRow(raw, now);
        if (row != null) _upsertRow(db, 'products', row);
      }
      for (final raw in sales) {
        try {
          final sale = SaleModel.fromApiJson(raw);
          final saleId = sale.localId.trim();
          if (saleId.isEmpty) continue;
          final saleNumber = _parseLocalSaleNumber(sale.number);
          if (saleNumber > maxBootstrapSaleNumber) {
            maxBootstrapSaleNumber = saleNumber;
          }
          db.execute(
            '''
            INSERT INTO sales_history (id, date, raw_json, updated_at_local)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              date = excluded.date,
              raw_json = excluded.raw_json,
              updated_at_local = excluded.updated_at_local
            ''',
            [
              saleId,
              sale.date.toIso8601String(),
              jsonEncode(sale.toJson()),
              now
            ],
          );
        } catch (_) {
          // Ignore malformed snapshot records and keep bootstrapping.
        }
      }
      for (final raw in refunds) {
        try {
          _upsertRefundPullRecord(db, raw, now);
        } catch (_) {
          // Ignore malformed snapshot records and keep bootstrapping.
        }
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

      if (maxBootstrapSaleNumber > 0) {
        final currentCounter = _readSaleLocalCounter(db);
        if (maxBootstrapSaleNumber > currentCounter) {
          db.execute(
            '''
            INSERT INTO local_counters (name, value)
            VALUES (?, ?)
            ON CONFLICT(name) DO UPDATE SET value = excluded.value
            ''',
            ['sale_local_number', maxBootstrapSaleNumber],
          );
        }
      }
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
      _syncSaleLocalCounter(db);
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

  Future<void> upsertPosInfo(Map<String, dynamic> posInfo) async {
    final db = await _database;
    final now = _nowIso();
    _inTransaction<void>(db, () {
      final row = _mapPosInfoRow(posInfo);
      if (row != null) {
        _upsertRow(db, 'pos_info', row);
      }
      _upsertReturnAccessKeysFromPosInfo(db, posInfo, now);
    });
  }

  Future<List<LocalAccount>> loadAccounts() async {
    final db = await _database;
    final rows = db.select(
      'SELECT id, name, type, logo_url, raw_json, COALESCE(visible_to_pos, 1) AS visible_to_pos FROM accounts ORDER BY name COLLATE NOCASE;',
    );
    return rows.map((row) {
      final rawJson = decodeJsonMap((row['raw_json'] ?? '{}').toString());
      return LocalAccount(
        id: row['id'].toString(),
        name: row['name'].toString(),
        type: row['type']?.toString(),
        logoUrl: _nullableString(row['logo_url']) ??
            _nullableString(rawJson['logo_url'] ?? rawJson['logoUrl']),
        visibleToPos: (row['visible_to_pos'] as int? ?? 1) == 1,
      );
    }).toList(growable: false);
  }

  Future<List<ProductModel>> loadProducts() async {
    final db = await _database;
    final rows = db
        .select('SELECT raw_json FROM products ORDER BY name COLLATE NOCASE;');
    return rows
        .map((row) => ProductModel.fromJson(
            decodeJsonMap((row['raw_json'] ?? '{}').toString())))
        .toList(growable: false);
  }

  Future<void> upsertLocalProduct(Map<String, dynamic> product) async {
    final db = await _database;
    final row = _mapProductRow(product, _nowIso());
    if (row != null) _upsertRow(db, 'products', row);
  }

  Future<void> replaceLocalProduct({
    required String localId,
    required Map<String, dynamic> serverProduct,
  }) async {
    final db = await _database;
    final serverId = (serverProduct['id'] ?? '').toString().trim();
    if (serverId.isEmpty) {
      throw const FormatException('Product response does not contain id');
    }
    final row = _mapProductRow(serverProduct, _nowIso());
    if (row == null) {
      throw const FormatException('Invalid product response');
    }
    _inTransaction<void>(db, () {
      db.execute(
        '''
        INSERT INTO product_id_mappings (local_id, server_id, created_at)
        VALUES (?, ?, ?)
        ON CONFLICT(local_id) DO UPDATE SET server_id = excluded.server_id
        ''',
        [localId, serverId, _nowIso()],
      );
      db.execute('DELETE FROM products WHERE id = ?', [localId]);
      _upsertRow(db, 'products', row);
    });
  }

  Future<String?> findServerProductId(String localId) async {
    final db = await _database;
    final row = _firstRow(db.select(
      'SELECT server_id FROM product_id_mappings WHERE local_id = ? LIMIT 1',
      [localId],
    ));
    final value = (row?['server_id'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  Future<List<Map<String, dynamic>>> loadProductsRaw() async {
    final db = await _database;
    final rows = db
        .select('SELECT raw_json FROM products ORDER BY name COLLATE NOCASE;');
    return rows
        .map((row) => decodeJsonMap((row['raw_json'] ?? '{}').toString()))
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
        .map((row) => ProductModel.fromJson(
            decodeJsonMap((row['raw_json'] ?? '{}').toString())))
        .toList(growable: false);
  }

  Future<List<LocalExpenseType>> loadExpenseTypes() async {
    final db = await _database;
    final rows = db.select(
        'SELECT id, name, raw_json FROM expense_types ORDER BY name COLLATE NOCASE;');
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
    final rows = db.select(
        'SELECT id, name, phone, raw_json FROM customers ORDER BY name COLLATE NOCASE;');
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

  Future<void> upsertCustomersRaw(List<Map<String, dynamic>> customers) async {
    if (customers.isEmpty) return;
    final db = await _database;
    final now = _nowIso();
    _inTransaction<void>(db, () {
      for (final raw in customers) {
        final row = _mapCustomerRow(raw, now);
        if (row != null) _upsertRow(db, 'customers', row);
      }
    });
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
      return _recordFromRow({
        ...row,
        'status': OutboxOperationStatus.sending.value,
        'updated_at': now
      });
    });
  }

  Future<OutboxOperationRecord?> claimOperationById(String operationId) async {
    final db = await _database;
    return _inTransaction<OutboxOperationRecord?>(db, () {
      final row = _firstRow(
        db.select(
          '''
          SELECT *
          FROM outbox_operations
          WHERE id = ? AND status IN (?, ?)
          LIMIT 1
          ''',
          [
            operationId,
            OutboxOperationStatus.pending.value,
            OutboxOperationStatus.manual.value,
          ],
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
        [OutboxOperationStatus.sending.value, now, operationId],
      );
      return _recordFromRow({
        ...row,
        'status': OutboxOperationStatus.sending.value,
        'updated_at': now,
      });
    });
  }

  Future<List<OutboxOperationRecord>> claimPendingOperations(
      {int limit = 5}) async {
    final db = await _database;
    return _inTransaction<List<OutboxOperationRecord>>(db, () {
      final rows = db.select(
        '''
        SELECT *
        FROM outbox_operations
        WHERE status = ?
        ORDER BY
          CASE type
            WHEN 'session_open'  THEN 0
            WHEN 'product_create' THEN 1
            WHEN 'sale'          THEN 2
            WHEN 'payment'       THEN 3
            WHEN 'refund'        THEN 4
            WHEN 'session_close' THEN 5
            ELSE 6
          END ASC,
          created_at ASC
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
    Map<String, dynamic>? payload,
    Map<String, dynamic>? errorDetails,
  }) async {
    final db = await _database;
    final now = _nowIso();
    _inTransaction<void>(db, () {
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
      if ((errorCode ?? '').trim().isEmpty &&
          (errorMessage ?? '').trim().isEmpty) {
        return;
      }
      db.execute(
        '''
        INSERT INTO sync_errors (
          id, operation_id, error_code, error_message, payload_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ''',
        [
          '${operationId}_$now',
          operationId,
          (errorCode ?? 'UNKNOWN_ERROR').trim(),
          (errorMessage ?? 'Unknown error').trim(),
          jsonEncode(_buildStoredErrorPayload(
            payload: payload,
            errorDetails: errorDetails,
          )),
          now,
        ],
      );
    });
  }

  Future<void> deferOperation({
    required String operationId,
    String? message,
  }) async {
    final db = await _database;
    final now = _nowIso();
    db.execute(
      '''
      UPDATE outbox_operations
      SET status = ?, last_error_code = NULL, last_error_message = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        OutboxOperationStatus.pending.value,
        _nullableString(message),
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
    Map<String, dynamic>? errorDetails,
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
          jsonEncode(_buildStoredErrorPayload(
            payload: payload,
            errorDetails: errorDetails,
          )),
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
        .map((row) => _saleFromPayload(
            decodeJsonMap((row['payload_json'] ?? '{}').toString())))
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
    return rows
        .map((row) => _queueItemFromRow(_rowMap(row)))
        .toList(growable: false);
  }

  Future<QueueItemDetails?> loadQueueItemDetails(String operationId) async {
    final db = await _database;
    final operationRow = _firstRow(
      db.select(
        '''
        SELECT *
        FROM outbox_operations
        WHERE id = ?
        LIMIT 1
        ''',
        [operationId],
      ),
    );
    if (operationRow == null) return null;

    final latestErrorRow = _firstRow(
      db.select(
        '''
        SELECT *
        FROM sync_errors
        WHERE operation_id = ?
        ORDER BY created_at DESC
        LIMIT 1
        ''',
        [operationId],
      ),
    );

    final queueItem = _queueItemFromRow(operationRow);
    final payload =
        decodeJsonMap((operationRow['payload_json'] ?? '{}').toString());

    Map<String, dynamic>? lastErrorDetails;
    final rawErrorPayload =
        latestErrorRow?['payload_json']?.toString().trim() ?? '';
    if (rawErrorPayload.isNotEmpty) {
      try {
        lastErrorDetails = decodeJsonMap(rawErrorPayload);
      } catch (_) {
        lastErrorDetails = null;
      }
    }

    return QueueItemDetails(
      id: queueItem.id,
      type: queueItem.type,
      clientId: queueItem.clientId,
      status: queueItem.status,
      createdAt: _parseDt(operationRow['created_at']) ?? DateTime.now(),
      updatedAt: _parseDt(operationRow['updated_at']) ?? DateTime.now(),
      payload: payload,
      title: queueItem.title,
      subtitle: queueItem.subtitle,
      errorCode:
          latestErrorRow?['error_code']?.toString() ?? queueItem.errorCode,
      errorMessage: latestErrorRow?['error_message']?.toString() ??
          queueItem.errorMessage,
      lastErrorDetails: lastErrorDetails,
    );
  }

  Future<void> updateQueueOperationPayload({
    required String operationId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _database;
    final normalizedPayload = Map<String, dynamic>.from(payload);
    final now = _nowIso();
    _inTransaction<void>(db, () {
      final row = _firstRow(
        db.select(
          '''
          SELECT id, type, client_id
          FROM outbox_operations
          WHERE id = ?
          LIMIT 1
          ''',
          [operationId],
        ),
      );
      if (row == null) return;

      final type = OutboxOperationTypeX.fromValue(_string(row['type'])) ??
          OutboxOperationType.sale;
      final clientId = _string(row['client_id']);

      db.execute(
        '''
        UPDATE outbox_operations
        SET payload_json = ?, updated_at = ?
        WHERE id = ?
        ''',
        [jsonEncode(normalizedPayload), now, operationId],
      );

      switch (type) {
        case OutboxOperationType.productCreate:
          final localProduct = <String, dynamic>{
            ...normalizedPayload,
            'id': clientId,
            'name': _string(
              normalizedPayload['name'],
              fallback: _string(normalizedPayload['barcode']),
            ),
            'quantity': 0,
          };
          final productRow = _mapProductRow(localProduct, now);
          if (productRow != null) _upsertRow(db, 'products', productRow);
        case OutboxOperationType.sale:
          final localNumber = _asInt(normalizedPayload['local_number']);
          final receiptNumber = _string(
            normalizedPayload['local_number'],
            fallback: _string(normalizedPayload['number']),
          );
          db.execute(
            '''
            UPDATE sales
            SET
              local_number = CASE WHEN ? > 0 THEN ? ELSE local_number END,
              number = CASE WHEN ? != '' THEN ? ELSE number END,
              pos_session_id = COALESCE(?, pos_session_id),
              pos_id = COALESCE(?, pos_id),
              store_id = COALESCE(?, store_id),
              account_id = COALESCE(?, account_id),
              customer_id = COALESCE(?, customer_id),
              created_by_id = COALESCE(?, created_by_id)
            WHERE client_sale_id = ?
            ''',
            [
              localNumber,
              localNumber,
              receiptNumber,
              receiptNumber,
              _nullableString(normalizedPayload['pos_session_id']),
              _nullableString(normalizedPayload['pos_id']),
              _nullableString(normalizedPayload['store_id']),
              _nullableString(normalizedPayload['account_id']),
              _nullableString(normalizedPayload['customer_id']),
              _nullableString(normalizedPayload['user_id']),
              clientId,
            ],
          );
        case OutboxOperationType.payment:
          db.execute(
            '''
            UPDATE payments
            SET
              pos_session_id = COALESCE(?, pos_session_id),
              account_id = COALESCE(?, account_id),
              expense_type_id = COALESCE(?, expense_type_id),
              created_by_id = COALESCE(?, created_by_id)
            WHERE client_payment_id = ?
            ''',
            [
              _nullableString(normalizedPayload['pos_session_id']),
              _nullableString(normalizedPayload['account_id']),
              _nullableString(normalizedPayload['expense_type_id']),
              _nullableString(normalizedPayload['created_by_id']),
              clientId,
            ],
          );
        case OutboxOperationType.refund:
          db.execute(
            '''
            UPDATE refunds
            SET
              pos_session_id = COALESCE(?, pos_session_id),
              client_sale_id = COALESCE(?, client_sale_id),
              sale_id = COALESCE(?, sale_id),
              pos_id = COALESCE(?, pos_id),
              store_id = COALESCE(?, store_id),
              account_id = COALESCE(?, account_id),
              note = COALESCE(?, note)
            WHERE client_refund_id = ?
            ''',
            [
              _nullableString(normalizedPayload['pos_session_id']),
              _nullableString(normalizedPayload['client_sale_id']),
              _nullableString(normalizedPayload['sale_id']),
              _nullableString(normalizedPayload['pos_id']),
              _nullableString(normalizedPayload['store_id']),
              _nullableString(normalizedPayload['account_id']),
              _nullableString(normalizedPayload['note']),
              clientId,
            ],
          );
        case OutboxOperationType.sessionOpen:
        case OutboxOperationType.sessionClose:
          break;
      }
    });
  }

  Future<void> deleteQueueOperation(String operationId) async {
    final db = await _database;
    _inTransaction<void>(db, () {
      final row = _firstRow(
        db.select(
          '''
          SELECT id, type, client_id
          FROM outbox_operations
          WHERE id = ?
          LIMIT 1
          ''',
          [operationId],
        ),
      );
      if (row == null) return;

      final type = OutboxOperationTypeX.fromValue(_string(row['type'])) ??
          OutboxOperationType.sale;
      final clientId = _string(row['client_id']);

      db.execute(
        'DELETE FROM sync_errors WHERE operation_id = ?',
        [operationId],
      );
      db.execute(
        'DELETE FROM outbox_operations WHERE id = ?',
        [operationId],
      );

      switch (type) {
        case OutboxOperationType.productCreate:
          db.execute('DELETE FROM products WHERE id = ?', [clientId]);
        case OutboxOperationType.sale:
          db.execute(
            'DELETE FROM sale_items WHERE sale_id = ?',
            [clientId],
          );
          db.execute(
            'DELETE FROM sales WHERE client_sale_id = ? AND synced = 0',
            [clientId],
          );
        case OutboxOperationType.payment:
          db.execute(
            'DELETE FROM payments WHERE client_payment_id = ? AND synced = 0',
            [clientId],
          );
        case OutboxOperationType.refund:
          db.execute(
            'DELETE FROM refund_items WHERE refund_id = ?',
            [clientId],
          );
          db.execute(
            'DELETE FROM refunds WHERE client_refund_id = ? AND synced = 0',
            [clientId],
          );
        case OutboxOperationType.sessionOpen:
        case OutboxOperationType.sessionClose:
          break;
      }
    });
  }

  void _applyPullChange(
    sqlite.Database db,
    SyncPullChange change,
    String now,
  ) {
    final entity = _normalizeEntity(change.entity);
    if (entity == null) return;

    final action = change.action.trim().toLowerCase();
    if (entity == _EntityKind.sale) {
      if (action == 'delete') {
        _deleteSalePullRecord(
            db, change.targetId ?? change.payload?['id']?.toString() ?? '');
        return;
      }
      if (action == 'upsert' || action == 'insert' || action == 'update') {
        final payload = change.payload;
        if (payload == null) {
          _deleteSalePullRecord(db, change.targetId ?? '');
          return;
        }
        _upsertSalePullRecord(db, payload, now);
      }
      return;
    }
    if (entity == _EntityKind.refund) {
      if (action == 'delete') {
        _deleteRefundPullRecord(
            db, change.targetId ?? change.payload?['id']?.toString() ?? '');
        return;
      }
      if (action == 'upsert' || action == 'insert' || action == 'update') {
        final payload = change.payload;
        if (payload == null) {
          _deleteRefundPullRecord(db, change.targetId ?? '');
          return;
        }
        _upsertRefundPullRecord(db, payload, now);
      }
      return;
    }

    if (action == 'delete') {
      final targetId =
          (change.targetId ?? change.payload?['id'])?.toString() ?? '';
      if (targetId.isEmpty) return;
      db.execute('DELETE FROM ${entity.table} WHERE id = ?', [targetId]);
      return;
    }

    if (action != 'upsert' && action != 'insert' && action != 'update') {
      return;
    }

    final payload = change.payload;
    if (payload == null) {
      // upsert with no record = server-side delete
      // (entity is not visible to this POS, e.g. product with zero stock)
      final targetId = (change.targetId ?? '').toString();
      if (targetId.isEmpty) return;
      db.execute('DELETE FROM ${entity.table} WHERE id = ?', [targetId]);
      return;
    }

    if (entity == _EntityKind.posInfo) {
      final row = _mapPosInfoRow(payload);
      if (row != null) _upsertRow(db, entity.table, row);
      _upsertReturnAccessKeysFromPosInfo(db, payload, now);
      return;
    }

    final row = switch (entity) {
      _EntityKind.product => _mapProductRow(payload, now),
      _EntityKind.account => _mapAccountRow(payload, now),
      _EntityKind.expenseType => _mapExpenseTypeRow(payload, now),
      _EntityKind.customer => _mapCustomerRow(payload, now),
      _EntityKind.returnAccessKey => _mapReturnAccessKeyRow(payload, now),
      _EntityKind.posInfo || _EntityKind.sale || _EntityKind.refund => null,
    };

    if (row == null) return;
    _upsertRow(db, entity.table, row);
  }

  void _upsertSalePullRecord(
    sqlite.Database db,
    Map<String, dynamic> payload,
    String now,
  ) {
    final saleId = _string(payload['id']);
    if (saleId.isEmpty) return;

    final clientSaleId = _string(payload['client_sale_id'], fallback: saleId);
    final existing = _firstRow(
      db.select(
        'SELECT id, local_number FROM sales WHERE id = ? OR client_sale_id = ? LIMIT 1',
        [saleId, clientSaleId],
      ),
    );
    final previousId = _string(existing?['id']);
    var localNumber = _asInt(existing?['local_number']);
    final pulledNumber = _parseLocalSaleNumber(payload['number']);
    if (pulledNumber > localNumber) {
      localNumber = pulledNumber;
    }
    final shouldRefreshHistoryCache = _hasCachedSaleHistoryRecord(
      db,
      saleId: saleId,
      clientSaleId: clientSaleId,
      previousId: previousId,
    );

    if (previousId.isNotEmpty && previousId != saleId) {
      db.execute('UPDATE sale_items SET sale_id = ? WHERE sale_id = ?',
          [saleId, previousId]);
      db.execute('DELETE FROM sales WHERE id = ?', [previousId]);
      db.execute('DELETE FROM sales_history WHERE id = ?', [previousId]);
    }

    final paymentBreakdown = _salePaymentBreakdown(db, payload);

    db.execute(
      '''
      INSERT INTO sales (
        id, client_sale_id, local_number, number, date, total_amount,
        pos_session_id, payment_method, cash_amount, card_amount,
        transfer_amount, credit_amount, pos_id, store_id, account_id, customer_id,
        created_by_id, completed, synced
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(id) DO UPDATE SET
        client_sale_id = excluded.client_sale_id,
        local_number = excluded.local_number,
        number = excluded.number,
        date = excluded.date,
        total_amount = excluded.total_amount,
        pos_session_id = excluded.pos_session_id,
        payment_method = excluded.payment_method,
        cash_amount = excluded.cash_amount,
        card_amount = excluded.card_amount,
        transfer_amount = excluded.transfer_amount,
        credit_amount = excluded.credit_amount,
        pos_id = excluded.pos_id,
        store_id = excluded.store_id,
        account_id = excluded.account_id,
        customer_id = excluded.customer_id,
        created_by_id = excluded.created_by_id,
        completed = excluded.completed,
        synced = 1
      ''',
      [
        saleId,
        clientSaleId,
        localNumber,
        _nullableString(payload['number']),
        _string(payload['date']),
        _asDouble(payload['total_amount']),
        _nullableString(payload['pos_session_id']),
        _string(payload['payment_method'], fallback: 'cash'),
        paymentBreakdown.cash,
        paymentBreakdown.card,
        paymentBreakdown.transfer,
        paymentBreakdown.credit,
        _nullableString(payload['pos_id']),
        _nullableString(payload['store_id']),
        _nullableString(payload['account_id']),
        _nullableString(payload['customer_id']),
        _nullableString(payload['user_id']),
        payload['completed'] == null ? 1 : _asBoolInt(payload['completed']),
      ],
    );

    db.execute('DELETE FROM sale_items WHERE sale_id = ?', [saleId]);
    final items = payload['items'];
    if (items is List) {
      var idx = 0;
      for (final item in items.whereType<Map>()) {
        final itemMap = Map<String, dynamic>.from(item);
        final itemId = _string(itemMap['id'], fallback: '${saleId}_$idx');
        db.execute(
          '''
          INSERT INTO sale_items (id, sale_id, product_id, product_name, quantity, price, total_price)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            sale_id = excluded.sale_id,
            product_id = excluded.product_id,
            product_name = excluded.product_name,
            quantity = excluded.quantity,
            price = excluded.price,
            total_price = excluded.total_price
          ''',
          [
            itemId,
            saleId,
            _string(itemMap['product_id']),
            _nullableString(itemMap['product_name'] ?? itemMap['name']),
            _asDouble(itemMap['quantity']),
            _asDouble(itemMap['price']),
            _asDouble(itemMap['total_price']),
          ],
        );
        idx++;
      }
    }

    if (shouldRefreshHistoryCache) {
      final refundPayload = _loadRefundPayloadForSale(
        db,
        saleId: saleId,
        clientSaleId: clientSaleId,
        filterByCurrentPos: true,
      );
      _upsertSaleHistoryRecord(
        db: db,
        salePayload: payload,
        refundPayload: refundPayload,
        now: now,
        previousIdToReplace:
            previousId.isNotEmpty && previousId != saleId ? previousId : null,
      );
    }
  }

  void _deleteSalePullRecord(sqlite.Database db, String saleId) {
    final targetId = saleId.trim();
    if (targetId.isEmpty) return;

    final existing = _firstRow(
      db.select(
          'SELECT client_sale_id FROM sales WHERE id = ? LIMIT 1', [targetId]),
    );
    final clientSaleId = _string(existing?['client_sale_id']);

    db.execute('DELETE FROM sale_items WHERE sale_id = ?', [targetId]);
    db.execute('DELETE FROM sales WHERE id = ?', [targetId]);
    db.execute('DELETE FROM sales_history WHERE id = ?', [targetId]);
    if (clientSaleId.isNotEmpty && clientSaleId != targetId) {
      db.execute('DELETE FROM sales_history WHERE id = ?', [clientSaleId]);
    }
  }

  void _upsertRefundPullRecord(
    sqlite.Database db,
    Map<String, dynamic> payload,
    String now,
  ) {
    final refundId = _string(payload['id']);
    if (refundId.isEmpty) return;

    final clientRefundId =
        _string(payload['client_refund_id'], fallback: refundId);
    final existing = _firstRow(
      db.select(
        'SELECT id FROM refunds WHERE id = ? OR client_refund_id = ? LIMIT 1',
        [refundId, clientRefundId],
      ),
    );
    final previousId = _string(existing?['id']);

    if (previousId.isNotEmpty && previousId != refundId) {
      db.execute('UPDATE refund_items SET refund_id = ? WHERE refund_id = ?',
          [refundId, previousId]);
      db.execute('DELETE FROM refunds WHERE id = ?', [previousId]);
    }

    db.execute(
      '''
      INSERT INTO refunds (
        id, client_refund_id, client_sale_id, sale_id, date, total_amount,
        pos_id, store_id, account_id, reason, reason_code, note, return_key_used, synced
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(id) DO UPDATE SET
        client_refund_id = excluded.client_refund_id,
        client_sale_id = excluded.client_sale_id,
        sale_id = excluded.sale_id,
        date = excluded.date,
        total_amount = excluded.total_amount,
        pos_id = excluded.pos_id,
        store_id = excluded.store_id,
        account_id = excluded.account_id,
        reason = excluded.reason,
        reason_code = excluded.reason_code,
        note = excluded.note,
        return_key_used = excluded.return_key_used,
        synced = 1
      ''',
      [
        refundId,
        clientRefundId,
        _nullableString(payload['client_sale_id']),
        _nullableString(payload['sale_id']),
        _string(payload['date']),
        _asDouble(payload['total_amount']),
        _nullableString(payload['pos_id']),
        _nullableString(payload['store_id']),
        _nullableString(payload['account_id']),
        _nullableString(payload['reason']),
        _nullableString(payload['reason_code']),
        _nullableString(payload['note']),
        _nullableString(payload['return_access_key']),
      ],
    );

    db.execute('DELETE FROM refund_items WHERE refund_id = ?', [refundId]);
    final items = payload['items'];
    if (items is List) {
      var idx = 0;
      for (final item in items.whereType<Map>()) {
        final itemMap = Map<String, dynamic>.from(item);
        final itemId = _string(itemMap['id'], fallback: '${refundId}_$idx');
        db.execute(
          '''
          INSERT INTO refund_items (id, refund_id, product_id, quantity, price)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            refund_id = excluded.refund_id,
            product_id = excluded.product_id,
            quantity = excluded.quantity,
            price = excluded.price
          ''',
          [
            itemId,
            refundId,
            _string(itemMap['product_id']),
            _asDouble(itemMap['quantity']),
            _asDouble(itemMap['price']),
          ],
        );
        idx++;
      }
    }

    _applyRefundToSalesHistory(db, payload, now);
  }

  void _deleteRefundPullRecord(sqlite.Database db, String refundId) {
    final targetId = refundId.trim();
    if (targetId.isEmpty) return;

    final existing = _firstRow(
      db.select(
        'SELECT sale_id, client_sale_id, pos_id FROM refunds WHERE id = ? LIMIT 1',
        [targetId],
      ),
    );
    final saleId = _string(existing?['sale_id']);
    final clientSaleId = _string(existing?['client_sale_id']);
    final refundPosId = _string(existing?['pos_id']);

    db.execute('DELETE FROM refund_items WHERE refund_id = ?', [targetId]);
    db.execute('DELETE FROM refunds WHERE id = ?', [targetId]);

    final currentPosId = _currentPosId(db);
    if (refundPosId.isEmpty ||
        currentPosId.isEmpty ||
        refundPosId == currentPosId) {
      _clearRefundFromSaleHistory(db,
          saleId: saleId, clientSaleId: clientSaleId, now: _nowIso());
    }
  }

  void _upsertSaleHistoryRecord({
    required sqlite.Database db,
    required Map<String, dynamic> salePayload,
    required String now,
    Map<String, dynamic>? refundPayload,
    String? previousIdToReplace,
  }) {
    final enriched = Map<String, dynamic>.from(salePayload);
    if (refundPayload != null) {
      enriched['refund'] = refundPayload;
    }
    final sale = SaleModel.fromApiJson(enriched);
    final saleId = sale.localId.trim();
    if (saleId.isEmpty) return;

    if ((previousIdToReplace ?? '').trim().isNotEmpty &&
        previousIdToReplace!.trim() != saleId) {
      db.execute('DELETE FROM sales_history WHERE id = ?',
          [previousIdToReplace.trim()]);
    }

    final clientSaleId = _string(salePayload['client_sale_id']);
    if (clientSaleId.isNotEmpty && clientSaleId != saleId) {
      db.execute('DELETE FROM sales_history WHERE id = ?', [clientSaleId]);
    }

    db.execute(
      '''
      INSERT INTO sales_history (id, date, raw_json, updated_at_local)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        date = excluded.date,
        raw_json = excluded.raw_json,
        updated_at_local = excluded.updated_at_local
      ''',
      [saleId, sale.date.toIso8601String(), jsonEncode(sale.toJson()), now],
    );
  }

  bool _hasCachedSaleHistoryRecord(
    sqlite.Database db, {
    required String saleId,
    required String clientSaleId,
    String? previousId,
  }) {
    final candidateIds = <String>{
      saleId.trim(),
      clientSaleId.trim(),
      (previousId ?? '').trim(),
    }..removeWhere((id) => id.isEmpty);

    if (candidateIds.isEmpty) return false;

    final placeholders = List.filled(candidateIds.length, '?').join(', ');
    final row = _firstRow(
      db.select(
        'SELECT id FROM sales_history WHERE id IN ($placeholders) LIMIT 1',
        candidateIds.toList(growable: false),
      ),
    );
    return row != null;
  }

  Map<String, dynamic>? _loadRefundPayloadForSale(
    sqlite.Database db, {
    required String saleId,
    required String clientSaleId,
    required bool filterByCurrentPos,
  }) {
    final rows = db.select(
      '''
      SELECT *
      FROM refunds
      WHERE sale_id = ? OR (? <> '' AND client_sale_id = ?)
      ORDER BY date DESC
      LIMIT 1
      ''',
      [saleId, clientSaleId, clientSaleId],
    );
    if (rows.isEmpty) return null;

    final refundRow = _rowMap(rows.first);
    if (filterByCurrentPos) {
      final currentPosId = _currentPosId(db);
      final refundPosId = _string(refundRow['pos_id']);
      if (refundPosId.isNotEmpty &&
          currentPosId.isNotEmpty &&
          refundPosId != currentPosId) {
        return null;
      }
    }

    final refundId = _string(refundRow['id']);
    final itemRows = db.select(
      'SELECT * FROM refund_items WHERE refund_id = ? ORDER BY id',
      [refundId],
    );
    final items = itemRows.map((row) {
      final map = _rowMap(row);
      return {
        'id': _string(map['id']),
        'refund_id': refundId,
        'sale_item_id': '',
        'product_id': _string(map['product_id']),
        'quantity': _asInt(map['quantity']),
        'price': _asInt(map['price']),
        'max_quantity': 0,
      };
    }).toList(growable: false);

    return {
      'id': refundId,
      'number': null,
      'date': _string(refundRow['date']),
      'total_amount': _asInt(refundRow['total_amount']),
      'reason': refundRow['reason'],
      'reason_code': refundRow['reason_code'],
      'note': refundRow['note'],
      'sale_id': _nullableString(refundRow['sale_id']),
      'pos_id': _nullableString(refundRow['pos_id']),
      'store_id': _nullableString(refundRow['store_id']),
      'account_id': _nullableString(refundRow['account_id']),
      'items': items,
    };
  }

  void _applyRefundToSalesHistory(
    sqlite.Database db,
    Map<String, dynamic> refundPayload,
    String now,
  ) {
    final currentPosId = _currentPosId(db);
    final refundPosId = _string(refundPayload['pos_id']);
    if (refundPosId.isNotEmpty &&
        currentPosId.isNotEmpty &&
        refundPosId != currentPosId) {
      return;
    }

    final saleId = _string(refundPayload['sale_id']);
    final clientSaleId = _string(refundPayload['client_sale_id']);
    final saleRow = _firstRow(
      db.select(
        '''
        SELECT id, raw_json
        FROM sales_history
        WHERE id = ? OR (? <> '' AND id = ?)
        LIMIT 1
        ''',
        [saleId, clientSaleId, clientSaleId],
      ),
    );
    if (saleRow == null) return;

    final rawSale = decodeJsonMap((saleRow['raw_json'] ?? '{}').toString());
    rawSale['refund'] = RefundModel.fromJson(refundPayload).toJson();

    final updated = SaleModel.fromJson(rawSale);
    final historyId = _string(saleRow['id'], fallback: saleId);
    db.execute(
      '''
      INSERT INTO sales_history (id, date, raw_json, updated_at_local)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        date = excluded.date,
        raw_json = excluded.raw_json,
        updated_at_local = excluded.updated_at_local
      ''',
      [
        historyId,
        updated.date.toIso8601String(),
        jsonEncode(updated.toJson()),
        now
      ],
    );
  }

  void _clearRefundFromSaleHistory(
    sqlite.Database db, {
    required String saleId,
    required String clientSaleId,
    required String now,
  }) {
    final saleRow = _firstRow(
      db.select(
        '''
        SELECT id, raw_json
        FROM sales_history
        WHERE id = ? OR (? <> '' AND id = ?)
        LIMIT 1
        ''',
        [saleId, clientSaleId, clientSaleId],
      ),
    );
    if (saleRow == null) return;

    final rawSale = decodeJsonMap((saleRow['raw_json'] ?? '{}').toString());
    rawSale['refund'] = null;

    final updated = SaleModel.fromJson(rawSale);
    final historyId = _string(saleRow['id'], fallback: saleId);
    db.execute(
      '''
      INSERT INTO sales_history (id, date, raw_json, updated_at_local)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        date = excluded.date,
        raw_json = excluded.raw_json,
        updated_at_local = excluded.updated_at_local
      ''',
      [
        historyId,
        updated.date.toIso8601String(),
        jsonEncode(updated.toJson()),
        now
      ],
    );
  }

  String _currentPosId(sqlite.Database db) {
    final row = _firstRow(db.select('SELECT id FROM pos_info LIMIT 1'));
    return _string(row?['id']);
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
    if (id.isEmpty ||
        key.isEmpty ||
        storeId.isEmpty ||
        organizationId.isEmpty) {
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

  void _upsertReturnAccessKeysFromPosInfo(
    sqlite.Database db,
    Map<String, dynamic> posInfo,
    String now,
  ) {
    final rawKeys = posInfo['return_access_keys'];
    if (rawKeys is! List) return;

    db.execute('DELETE FROM return_access_keys;');

    for (final raw in rawKeys) {
      if (raw is! Map) continue;
      final keyRow = _mapReturnAccessKeyRow(
        Map<String, dynamic>.from(raw),
        now,
      );
      if (keyRow == null) continue;
      _upsertRow(db, 'return_access_keys', keyRow);
    }
  }

  Map<String, dynamic>? _mapProductRow(Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    final category = raw['category'];
    final categoryName = category is Map
        ? _nullableString(category['name'])
        : _nullableString(raw['category_name']);
    return {
      'id': id,
      'name': _string(raw['name'], fallback: id),
      'barcode': _nullableString(raw['barcode']),
      'local_barcode': _nullableString(raw['local_barcode']),
      'sku': _nullableString(raw['sku']),
      'category_id': _nullableString(raw['category_id']),
      'category_name': categoryName,
      'price': _asDouble(
          raw['price_after_discount'] ?? raw['selling_price'] ?? raw['price']),
      'arrival_cost': _asDouble(raw['arrival_cost']),
      'wholesale_price': _asDouble(raw['wholesale_price']),
      'quantity': _asDouble(raw['quantity']),
      'measurement_unit': _nullableString(raw['measurement_unit']),
      'conversion_value': raw['conversion_value'] == null
          ? null
          : _asDouble(raw['conversion_value']),
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
      'logo_url': _nullableString(raw['logo_url'] ?? raw['logoUrl']),
      'allow_negative': _asBoolInt(raw['allow_negative']),
      'visible_to_pos':
          raw['visible_to_pos'] == null ? 1 : _asBoolInt(raw['visible_to_pos']),
      'organization_id': _nullableString(raw['organization_id']),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  Map<String, dynamic>? _mapExpenseTypeRow(
      Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    if (id.isEmpty) return null;
    return {
      'id': id,
      'name': _string(raw['name'], fallback: id),
      'is_active': raw['is_active'] == null ? 1 : _asBoolInt(raw['is_active']),
      'organization_id': _nullableString(raw['organization_id']),
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
      'note': _nullableString(raw['note']),
      'store_id': _nullableString(raw['store_id']),
      'organization_id': _nullableString(raw['organization_id']),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  Map<String, dynamic>? _mapReturnAccessKeyRow(
      Map<String, dynamic> raw, String now) {
    final id = _string(raw['id']);
    final key = _string(raw['key']);
    if (id.isEmpty || key.isEmpty) return null;
    return {
      'id': id,
      'key': key,
      'user_id': _nullableString(raw['user_id']),
      'store_id': _nullableString(raw['store_id']),
      'expires_at': _nullableString(raw['expires_at']),
      'is_active': _asBoolInt(raw['is_active'] ?? true),
      'raw_json': jsonEncode(raw),
      'updated_at_local': now,
    };
  }

  /// Check if a return access key is active and not expired locally.
  Future<bool> checkReturnAccessKey(
    String key, {
    String? storeId,
  }) async {
    final db = await _database;
    final normalizedStoreId = (storeId ?? '').trim();
    final rows = db.select(
      normalizedStoreId.isEmpty
          ? 'SELECT * FROM return_access_keys WHERE key = ? AND is_active = 1 LIMIT 1'
          : 'SELECT * FROM return_access_keys WHERE key = ? AND is_active = 1 AND (store_id IS NULL OR store_id = ?) LIMIT 1',
      normalizedStoreId.isEmpty
          ? [key.trim()]
          : [key.trim(), normalizedStoreId],
    );
    if (rows.isEmpty) return false;
    final row = _rowMap(rows.first);
    final expiresAt = row['expires_at']?.toString().trim() ?? '';
    if (expiresAt.isEmpty) return true;
    final expiryDt = _parseDt(expiresAt);
    // Invalid server dates must never make a key valid.
    if (expiryDt == null) return false;
    return expiryDt.isAfter(DateTime.now());
  }

  /// Get all active return access keys (for debugging).
  Future<List<String>> getAllActiveReturnAccessKeys() async {
    final db = await _database;
    final rows = db.select(
      'SELECT key FROM return_access_keys WHERE is_active = 1 ORDER BY updated_at_local DESC',
    );
    return rows
        .map((row) => _rowMap(row)['key']?.toString() ?? '')
        .where((k) => k.isNotEmpty)
        .toList();
  }

  /// Insert a new session into the local sessions table.
  Future<void> upsertSession({
    required String sessionId,
    required String userId,
    required String deviceId,
    String? serverSessionId,
    double? openingCashAmount,
    required DateTime openedAt,
  }) async {
    final db = await _database;
    final resolvedOpeningCashAmount =
        openingCashAmount ?? await _resolveOpeningCashAmount(db, deviceId);
    db.execute(
      '''
      INSERT INTO sessions (
        client_session_id, server_session_id, user_id, device_id, opening_cash_amount, opened_at, is_opened, synced
      ) VALUES (?, ?, ?, ?, ?, ?, 1, 0)
      ON CONFLICT(client_session_id) DO NOTHING
      ''',
      [
        sessionId,
        _nullableString(serverSessionId),
        userId,
        deviceId,
        resolvedOpeningCashAmount,
        openedAt.toIso8601String(),
      ],
    );
    await normalizeLegacySessionReferences();
  }

  Future<void> bindServerSessionId({
    required String clientSessionId,
    required String serverSessionId,
  }) async {
    final cleanClientSessionId = clientSessionId.trim();
    final cleanServerSessionId = serverSessionId.trim();
    if (cleanClientSessionId.isEmpty || cleanServerSessionId.isEmpty) return;

    final db = await _database;
    db.execute(
      '''
      UPDATE sessions
      SET server_session_id = ?
      WHERE client_session_id = ? OR server_session_id = ?
      ''',
      [cleanServerSessionId, cleanClientSessionId, cleanClientSessionId],
    );
    await normalizeLegacySessionReferences();
  }

  Future<void> normalizeLegacySessionReferences() async {
    final db = await _database;
    _inTransaction<void>(db, () {
      final rows = db.select(
        '''
        SELECT client_session_id, server_session_id
        FROM sessions
        WHERE COALESCE(TRIM(server_session_id), '') <> ''
          AND TRIM(client_session_id) <> TRIM(server_session_id)
        ''',
      );

      for (final row in rows) {
        final map = _rowMap(row);
        final legacySessionId =
            _nullableString(map['client_session_id'])?.trim() ?? '';
        final serverSessionId =
            _nullableString(map['server_session_id'])?.trim() ?? '';

        if (legacySessionId.isEmpty || serverSessionId.isEmpty) {
          continue;
        }

        db.execute(
          'UPDATE sales SET pos_session_id = ? WHERE pos_session_id = ?',
          [serverSessionId, legacySessionId],
        );
        db.execute(
          'UPDATE payments SET pos_session_id = ? WHERE pos_session_id = ?',
          [serverSessionId, legacySessionId],
        );
        db.execute(
          'UPDATE refunds SET pos_session_id = ? WHERE pos_session_id = ?',
          [serverSessionId, legacySessionId],
        );

        final opRows = db.select(
          '''
          SELECT id, payload_json
          FROM outbox_operations
          WHERE status IN (?, ?, ?)
          ''',
          [
            OutboxOperationStatus.pending.value,
            OutboxOperationStatus.sending.value,
            OutboxOperationStatus.manual.value,
          ],
        );

        for (final opRow in opRows) {
          final opMap = _rowMap(opRow);
          final rawPayload =
              _nullableString(opMap['payload_json'])?.trim() ?? '';
          if (rawPayload.isEmpty) continue;

          final payload = decodeJsonMap(rawPayload);
          var changed = false;

          if ((payload['pos_session_id'] ?? '').toString().trim() ==
              legacySessionId) {
            payload['pos_session_id'] = serverSessionId;
            changed = true;
          }

          if ((payload['session_id'] ?? '').toString().trim() ==
              legacySessionId) {
            payload['session_id'] = serverSessionId;
            changed = true;
          }

          if ((payload['client_session_id'] ?? '').toString().trim() ==
              legacySessionId) {
            payload['client_session_id'] = serverSessionId;
            changed = true;
          }

          if (!changed) continue;

          db.execute(
            '''
            UPDATE outbox_operations
            SET payload_json = ?, updated_at = ?
            WHERE id = ?
            ''',
            [jsonEncode(payload), _nowIso(), _string(opMap['id'])],
          );
        }
      }
    });
  }

  Future<void> rebindQueuedOperationsToCurrentContext({
    required String deviceId,
    String? posId,
    String? storeId,
    String? accountId,
    String? userId,
    String? sessionId,
  }) async {
    final db = await _database;
    final cleanDeviceId = deviceId.trim();
    final cleanPosId = _nullableString(posId);
    final cleanStoreId = _nullableString(storeId);
    final cleanAccountId = _nullableString(accountId);
    final cleanUserId = _nullableString(userId);
    final cleanSessionId = _nullableString(sessionId);

    _inTransaction<void>(db, () {
      final opRows = db.select(
        '''
        SELECT id, type, payload_json
        FROM outbox_operations
        WHERE status IN (?, ?, ?)
        ''',
        [
          OutboxOperationStatus.pending.value,
          OutboxOperationStatus.sending.value,
          OutboxOperationStatus.manual.value,
        ],
      );

      for (final opRow in opRows) {
        final row = _rowMap(opRow);
        final type = OutboxOperationTypeX.fromValue(_string(row['type'])) ??
            OutboxOperationType.sale;
        final payload =
            decodeJsonMap(_string(row['payload_json'], fallback: '{}'));
        var changed = false;

        if (cleanDeviceId.isNotEmpty &&
            _string(payload['device_id']) != cleanDeviceId) {
          payload['device_id'] = cleanDeviceId;
          changed = true;
        }

        switch (type) {
          case OutboxOperationType.productCreate:
            break;
          case OutboxOperationType.sale:
            changed = _applyPayloadValue(
                  payload,
                  'pos_id',
                  cleanPosId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'store_id',
                  cleanStoreId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'account_id',
                  cleanAccountId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'user_id',
                  cleanUserId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'pos_session_id',
                  cleanSessionId,
                ) ||
                changed;
            break;
          case OutboxOperationType.payment:
            changed = _applyPayloadValue(
                  payload,
                  'account_id',
                  cleanAccountId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'created_by_id',
                  cleanUserId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'pos_session_id',
                  cleanSessionId,
                ) ||
                changed;
            break;
          case OutboxOperationType.refund:
            changed = _applyPayloadValue(
                  payload,
                  'pos_session_id',
                  cleanSessionId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'pos_id',
                  cleanPosId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'store_id',
                  cleanStoreId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'account_id',
                  cleanAccountId,
                ) ||
                changed;
            break;
          case OutboxOperationType.sessionClose:
            changed = _applyPayloadValue(
                  payload,
                  'user_id',
                  cleanUserId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'client_session_id',
                  cleanSessionId,
                ) ||
                changed;
            changed = _applyPayloadValue(
                  payload,
                  'session_id',
                  cleanSessionId,
                ) ||
                changed;
            break;
          case OutboxOperationType.sessionOpen:
            break;
        }

        if (!changed) continue;

        db.execute(
          '''
          UPDATE outbox_operations
          SET payload_json = ?, updated_at = ?
          WHERE id = ?
          ''',
          [jsonEncode(payload), _nowIso(), _string(row['id'])],
        );
      }

      if (cleanSessionId != null) {
        db.execute(
          'UPDATE sales SET pos_session_id = ? WHERE synced = 0',
          [cleanSessionId],
        );
        db.execute(
          'UPDATE payments SET pos_session_id = ? WHERE synced = 0',
          [cleanSessionId],
        );
        db.execute(
          'UPDATE refunds SET pos_session_id = ? WHERE synced = 0',
          [cleanSessionId],
        );
      }

      if (cleanPosId != null ||
          cleanStoreId != null ||
          cleanAccountId != null ||
          cleanUserId != null) {
        db.execute(
          '''
          UPDATE sales
          SET
            pos_id = COALESCE(?, pos_id),
            store_id = COALESCE(?, store_id),
            account_id = COALESCE(?, account_id),
            created_by_id = COALESCE(?, created_by_id)
          WHERE synced = 0
          ''',
          [cleanPosId, cleanStoreId, cleanAccountId, cleanUserId],
        );
      }

      if (cleanAccountId != null || cleanUserId != null) {
        db.execute(
          '''
          UPDATE payments
          SET
            account_id = COALESCE(?, account_id),
            created_by_id = COALESCE(?, created_by_id)
          WHERE synced = 0
          ''',
          [cleanAccountId, cleanUserId],
        );
      }

      if (cleanPosId != null ||
          cleanStoreId != null ||
          cleanAccountId != null) {
        db.execute(
          '''
          UPDATE refunds
          SET
            pos_id = COALESCE(?, pos_id),
            store_id = COALESCE(?, store_id),
            account_id = COALESCE(?, account_id)
          WHERE synced = 0
          ''',
          [cleanPosId, cleanStoreId, cleanAccountId],
        );
      }
    });
  }

  Future<double> _resolveOpeningCashAmount(
      sqlite.Database db, String deviceId) async {
    final rows = db.select(
      '''
      SELECT closing_cash_amount
      FROM sessions
      WHERE device_id = ? AND is_opened = 0 AND closed_at IS NOT NULL
      ORDER BY datetime(closed_at) DESC
      LIMIT 1
      ''',
      [deviceId],
    );
    if (rows.isEmpty) return 0;
    return _asDouble(_rowMap(rows.first)['closing_cash_amount']);
  }

  /// Mark a session as closed in the local sessions table.
  Future<void> closeSessionLocal({
    required String sessionId,
    required double closingCashAmount,
    required DateTime closedAt,
  }) async {
    final db = await _database;
    db.execute(
      '''
      UPDATE sessions
      SET closing_cash_amount = ?, closed_at = ?, is_opened = 0
      WHERE client_session_id = ? OR server_session_id = ?
      ''',
      [closingCashAmount, closedAt.toIso8601String(), sessionId, sessionId],
    );
  }

  Future<String> resolveServerSessionId(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) return normalized;

    final serverSessionId = await findServerSessionId(sessionId);
    return serverSessionId ?? normalized;
  }

  Future<String?> findServerSessionId(String sessionId) async {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) return null;

    final db = await _database;
    final sessionRow = _firstRow(
      db.select(
        '''
        SELECT server_session_id
        FROM sessions
        WHERE client_session_id = ? OR server_session_id = ?
        LIMIT 1
        ''',
        [normalized, normalized],
      ),
    );

    final serverSessionId =
        _nullableString(sessionRow?['server_session_id'])?.trim() ?? '';
    if (serverSessionId.isEmpty || serverSessionId.startsWith('session_')) {
      return null;
    }
    return serverSessionId;
  }

  /// Insert sale + items into dedicated local tables (separate from outbox).
  Future<void> insertSaleLocal({
    required String clientSaleId,
    required int localNumber,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _database;
    _inTransaction<void>(db, () {
      final paymentBreakdown = _salePaymentBreakdown(db, payload);
      db.execute(
        '''
        INSERT OR IGNORE INTO sales (
          id, client_sale_id, local_number, number, date, total_amount,
          pos_session_id, payment_method, cash_amount, card_amount,
          transfer_amount, credit_amount, pos_id, store_id, account_id, customer_id,
          created_by_id, completed, synced
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0)
        ''',
        [
          clientSaleId,
          clientSaleId,
          localNumber,
          _nullableString(payload['local_number']),
          _string(payload['date']),
          _asDouble(payload['total_amount']),
          _nullableString(payload['pos_session_id']),
          _string(payload['payment_method'], fallback: 'cash'),
          paymentBreakdown.cash,
          paymentBreakdown.card,
          paymentBreakdown.transfer,
          paymentBreakdown.credit,
          _nullableString(payload['pos_id']),
          _nullableString(payload['store_id']),
          _nullableString(payload['account_id']),
          _nullableString(payload['customer_id']),
          _nullableString(payload['user_id']),
        ],
      );
      final items = payload['items'];
      if (items is List) {
        var idx = 0;
        for (final item in items.whereType<Map>()) {
          final itemMap = Map<String, dynamic>.from(item);
          db.execute(
            '''
            INSERT OR IGNORE INTO sale_items (id, sale_id, product_id, product_name, quantity, price, total_price)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              '${clientSaleId}_$idx',
              clientSaleId,
              _string(itemMap['product_id']),
              _nullableString(itemMap['product_name'] ?? itemMap['name']),
              _asDouble(itemMap['quantity']),
              _asDouble(itemMap['price']),
              _asDouble(itemMap['total_price']),
            ],
          );
          idx++;
        }
      }
    });
  }

  /// Insert a payment into the local payments table.
  Future<void> insertPaymentLocal(Map<String, dynamic> payload) async {
    final db = await _database;
    final clientPaymentId = _string(payload['client_payment_id']);
    if (clientPaymentId.isEmpty) return;
    db.execute(
      '''
      INSERT OR IGNORE INTO payments (
        id, client_payment_id, pos_session_id, is_expense, amount, date,
        account_id, expense_type_id, created_by_id, synced
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
      ''',
      [
        clientPaymentId,
        clientPaymentId,
        _nullableString(payload['pos_session_id']),
        _asBoolInt(payload['is_expense']),
        _asDouble(payload['amount']),
        _string(payload['date']),
        _nullableString(payload['account_id']),
        _nullableString(payload['expense_type_id']),
        _nullableString(payload['created_by_id']),
      ],
    );
  }

  /// Insert refund + items into dedicated local tables.
  Future<void> insertRefundLocal(Map<String, dynamic> payload) async {
    final db = await _database;
    final clientRefundId = _string(payload['client_refund_id']);
    if (clientRefundId.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    _inTransaction<void>(db, () {
      db.execute(
        '''
      INSERT OR IGNORE INTO refunds (
          id, client_refund_id, pos_session_id, client_sale_id, sale_id, date, total_amount,
          pos_id, store_id, account_id, reason, reason_code, note, return_key_used, synced
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
        ''',
        [
          clientRefundId,
          clientRefundId,
          _nullableString(payload['pos_session_id']),
          _nullableString(payload['client_sale_id']),
          _nullableString(payload['sale_id']),
          _string(payload['date']),
          _asDouble(payload['total_amount']),
          _nullableString(payload['pos_id']),
          _nullableString(payload['store_id']),
          _nullableString(payload['account_id']),
          _nullableString(payload['reason']),
          _nullableString(payload['reason_code']),
          _nullableString(payload['note']),
          _nullableString(payload['return_access_key']),
        ],
      );
      final items = payload['items'];
      if (items is List) {
        var idx = 0;
        for (final item in items.whereType<Map>()) {
          final itemMap = Map<String, dynamic>.from(item);
          db.execute(
            '''
            INSERT OR IGNORE INTO refund_items (id, refund_id, product_id, quantity, price)
            VALUES (?, ?, ?, ?, ?)
            ''',
            [
              '${clientRefundId}_$idx',
              clientRefundId,
              _string(itemMap['product_id']),
              _asDouble(itemMap['quantity']),
              _asDouble(itemMap['price']),
            ],
          );
          idx++;
        }
      }

      // Update sales_history raw_json so refund_quantity is reflected immediately
      final historyPayload = Map<String, dynamic>.from(payload)
        ..['id'] = clientRefundId;
      _applyRefundToSalesHistory(db, historyPayload, now);
    });
  }

  Future<void> markSaleSynced(String clientSaleId) async {
    final db = await _database;
    db.execute(
        'UPDATE sales SET synced = 1 WHERE client_sale_id = ?', [clientSaleId]);
  }

  Future<void> markSessionSynced(String sessionId) async {
    final db = await _database;
    db.execute(
      'UPDATE sessions SET synced = 1 WHERE client_session_id = ? OR server_session_id = ?',
      [sessionId, sessionId],
    );
  }

  Future<void> markPaymentSynced(String clientPaymentId) async {
    final db = await _database;
    db.execute('UPDATE payments SET synced = 1 WHERE client_payment_id = ?',
        [clientPaymentId]);
  }

  Future<void> markRefundSynced(String clientRefundId) async {
    final db = await _database;
    db.execute('UPDATE refunds SET synced = 1 WHERE client_refund_id = ?',
        [clientRefundId]);
  }

  Future<ShiftReportData?> loadShiftReport(String sessionId) async {
    final db = await _database;
    final sessionRow = _firstRow(
      db.select(
        'SELECT * FROM sessions WHERE client_session_id = ? OR server_session_id = ? LIMIT 1',
        [sessionId, sessionId],
      ),
    );
    if (sessionRow == null) return null;
    final sessionIds = _sessionQueryIds(sessionRow, sessionId);
    final sessionWhere = _sessionIdWhereClause(sessionIds.length);

    final salesRows = db.select(
      '''
      SELECT id, client_sale_id, payment_method, total_amount, cash_amount,
             card_amount, transfer_amount, credit_amount
      FROM sales
      WHERE completed = 1 AND pos_session_id $sessionWhere
      ''',
      sessionIds,
    );

    num cashTotal = 0;
    num cardTotal = 0;
    num transferTotal = 0;
    num creditTotal = 0;

    for (final row in salesRows) {
      final map = _rowMap(row);
      final amounts = _saleAmountsFromRow(db, map);
      cashTotal += amounts.cash;
      cardTotal += amounts.card;
      transferTotal += amounts.transfer;
      creditTotal += amounts.credit;
    }

    final itemRows = db.select(
      '''
      SELECT
        COALESCE(
          NULLIF(TRIM(si.product_name), ''),
          NULLIF(TRIM(p.name), ''),
          si.product_id
        ) AS product_name,
        SUM(si.quantity) AS total_qty,
        SUM(si.total_price) AS total_sum
      FROM sale_items si
      LEFT JOIN products p ON p.id = si.product_id
      WHERE sale_id IN (
        SELECT id FROM sales WHERE completed = 1 AND pos_session_id $sessionWhere
      )
      GROUP BY
        si.product_id,
        COALESCE(
          NULLIF(TRIM(si.product_name), ''),
          NULLIF(TRIM(p.name), ''),
          si.product_id
        )
      ORDER BY product_name COLLATE NOCASE
      ''',
      sessionIds,
    );

    final refundsRow = _firstRow(
      db.select(
        'SELECT COALESCE(SUM(total_amount), 0) AS total FROM refunds WHERE pos_session_id $sessionWhere',
        sessionIds,
      ),
    );
    final paymentsRow = _firstRow(
      db.select(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN is_expense = 0 THEN amount ELSE 0 END), 0) AS income_total,
          COALESCE(SUM(CASE WHEN is_expense = 1 THEN amount ELSE 0 END), 0) AS expense_total
        FROM payments
        WHERE pos_session_id $sessionWhere
        ''',
        sessionIds,
      ),
    );

    final items = itemRows.map((row) {
      final map = _rowMap(row);
      return ShiftReportItem(
        name: _string(map['product_name'], fallback: 'Товар'),
        quantity: _asDouble(map['total_qty']),
        totalSum: _asDouble(map['total_sum']),
      );
    }).toList(growable: false);

    final refundsTotal =
        refundsRow == null ? 0 : _asDouble(refundsRow['total']);
    final incomeTotal =
        paymentsRow == null ? 0 : _asDouble(paymentsRow['income_total']);
    final expenseTotal =
        paymentsRow == null ? 0 : _asDouble(paymentsRow['expense_total']);
    final openingCashAmount = _asDouble(sessionRow['opening_cash_amount']);

    return ShiftReportData(
      sessionId: sessionId,
      openedAt: _parseDt(sessionRow['opened_at']),
      closedAt: _parseDt(sessionRow['closed_at']),
      openingCashAmount: openingCashAmount,
      closingCashAmount: _asDouble(sessionRow['closing_cash_amount']),
      salesCount: salesRows.length,
      cashTotal: cashTotal,
      cardTotal: cardTotal,
      transferTotal: transferTotal,
      creditTotal: creditTotal,
      grandTotal: cashTotal + cardTotal + transferTotal + creditTotal,
      refundsTotal: refundsTotal,
      incomeTotal: incomeTotal,
      expenseTotal: expenseTotal,
      expectedCashAmount: openingCashAmount +
          cashTotal -
          refundsTotal +
          incomeTotal -
          expenseTotal,
      items: items,
    );
  }

  Future<ShiftClosureSummaryData?> loadShiftClosureSummary(
      String sessionId) async {
    final db = await _database;
    final sessionRow = _firstRow(
      db.select(
        'SELECT * FROM sessions WHERE client_session_id = ? OR server_session_id = ? LIMIT 1',
        [sessionId, sessionId],
      ),
    );
    if (sessionRow == null) return null;
    final sessionIds = _sessionQueryIds(sessionRow, sessionId);
    final sessionWhere = _sessionIdWhereClause(sessionIds.length);

    num cashSalesTotal = 0;
    num cardSalesTotal = 0;
    num transferSalesTotal = 0;
    num creditSalesTotal = 0;

    final salesRows = db.select(
      '''
      SELECT client_sale_id, payment_method, total_amount, cash_amount,
             card_amount, transfer_amount, credit_amount
      FROM sales
      WHERE completed = 1 AND pos_session_id $sessionWhere
      ''',
      sessionIds,
    );
    for (final row in salesRows) {
      final map = _rowMap(row);
      final amounts = _saleAmountsFromRow(db, map);
      cashSalesTotal += amounts.cash;
      cardSalesTotal += amounts.card;
      transferSalesTotal += amounts.transfer;
      creditSalesTotal += amounts.credit;
    }

    final refundsRow = _firstRow(
      db.select(
        'SELECT COALESCE(SUM(total_amount), 0) AS total FROM refunds WHERE pos_session_id $sessionWhere',
        sessionIds,
      ),
    );
    final paymentsRow = _firstRow(
      db.select(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN is_expense = 0 THEN amount ELSE 0 END), 0) AS income_total,
          COALESCE(SUM(CASE WHEN is_expense = 1 THEN amount ELSE 0 END), 0) AS expense_total
        FROM payments
        WHERE pos_session_id $sessionWhere
        ''',
        sessionIds,
      ),
    );

    final openingCashAmount = _asDouble(sessionRow['opening_cash_amount']);
    final refundsTotal =
        refundsRow == null ? 0 : _asDouble(refundsRow['total']);
    final incomeTotal =
        paymentsRow == null ? 0 : _asDouble(paymentsRow['income_total']);
    final expenseTotal =
        paymentsRow == null ? 0 : _asDouble(paymentsRow['expense_total']);
    final totalSalesAmount =
        cashSalesTotal + cardSalesTotal + transferSalesTotal + creditSalesTotal;
    final expectedCashAmount = openingCashAmount +
        cashSalesTotal -
        refundsTotal +
        incomeTotal -
        expenseTotal;

    return ShiftClosureSummaryData(
      sessionId: sessionId,
      openedAt: _parseDt(sessionRow['opened_at']),
      openingCashAmount: openingCashAmount,
      cashSalesTotal: cashSalesTotal,
      cardSalesTotal: cardSalesTotal,
      transferSalesTotal: transferSalesTotal,
      creditSalesTotal: creditSalesTotal,
      refundsTotal: refundsTotal,
      incomeTotal: incomeTotal,
      expenseTotal: expenseTotal,
      expectedCashAmount: expectedCashAmount,
      totalSalesAmount: totalSalesAmount,
    );
  }

  Future<List<LocalSession>> loadSessions() async {
    final db = await _database;
    final rows = db.select(
      '''
      SELECT client_session_id, server_session_id, user_id, device_id,
             opening_cash_amount, closing_cash_amount, opened_at, closed_at,
             is_opened
      FROM sessions
      ORDER BY datetime(opened_at) DESC
      ''',
    );

    return rows.map((row) {
      final map = _rowMap(row);
      return LocalSession(
        clientSessionId: (map['client_session_id'] ?? '').toString(),
        serverSessionId: _nullableString(map['server_session_id']),
        userId: (map['user_id'] ?? '').toString(),
        deviceId: (map['device_id'] ?? '').toString(),
        openingCashAmount: _asDouble(map['opening_cash_amount']),
        closingCashAmount: map['closing_cash_amount'] == null
            ? null
            : _asDouble(map['closing_cash_amount']),
        openedAt: _parseDt(map['opened_at']) ?? DateTime.now(),
        closedAt: _parseDt(map['closed_at']),
        isOpened: _asInt(map['is_opened']) == 1,
      );
    }).toList(growable: false);
  }

  _SalePaymentAmounts _salePaymentBreakdown(
    sqlite.Database db,
    Map<String, dynamic> payload,
  ) {
    final totalAmount = _asDouble(payload['total_amount']);
    final paymentMethod =
        _string(payload['payment_method'], fallback: 'cash').toLowerCase();
    final payments = payload['payments'];

    if (payments is List && payments.isNotEmpty) {
      var result = const _SalePaymentAmounts();
      for (final rawPayment in payments.whereType<Map>()) {
        final payment = Map<String, dynamic>.from(rawPayment);
        final amount = _asDouble(payment['amount']);
        if (amount <= 0) continue;

        final accountId = _string(payment['account_id']);
        final accountType = accountId.isEmpty
            ? ''
            : _string(
                _firstRow(
                  db.select(
                    'SELECT type FROM accounts WHERE id = ? LIMIT 1',
                    [accountId],
                  ),
                )?['type'],
              ).toLowerCase();
        final clientPaymentId =
            _string(payment['client_payment_id']).toLowerCase();

        if (accountType == 'cash' || clientPaymentId.endsWith('-cash')) {
          result = result.copyWith(cash: result.cash + amount);
        } else if (accountType.contains('transfer') ||
            clientPaymentId.endsWith('-transfer')) {
          result = result.copyWith(transfer: result.transfer + amount);
        } else {
          result = result.copyWith(card: result.card + amount);
        }
      }
      if (result.total > 0) return result;
    }

    return switch (paymentMethod) {
      'cash' => _SalePaymentAmounts(cash: totalAmount),
      'card' => _SalePaymentAmounts(card: totalAmount),
      'transfer' => _SalePaymentAmounts(transfer: totalAmount),
      'credit' ||
      'debt' ||
      'partial_debt' =>
        _SalePaymentAmounts(credit: totalAmount),
      _ => const _SalePaymentAmounts(),
    };
  }

  _SalePaymentAmounts _saleAmountsFromRow(
    sqlite.Database db,
    Map<String, dynamic> row,
  ) {
    final amounts = _SalePaymentAmounts(
      cash: _asDouble(row['cash_amount']),
      card: _asDouble(row['card_amount']),
      transfer: _asDouble(row['transfer_amount']),
      credit: _asDouble(row['credit_amount']),
    );
    if (amounts.total > 0) return amounts;

    if (_string(row['payment_method']).toLowerCase() == 'mixed') {
      final clientSaleId = _string(row['client_sale_id']);
      if (clientSaleId.isNotEmpty) {
        final outboxRow = _firstRow(
          db.select(
            '''
            SELECT payload_json
            FROM outbox_operations
            WHERE type = ? AND client_id = ?
            ORDER BY datetime(created_at) DESC
            LIMIT 1
            ''',
            [OutboxOperationType.sale.value, clientSaleId],
          ),
        );
        if (outboxRow != null) {
          final payload = decodeJsonMap(_string(outboxRow['payload_json']));
          final fromPayload = _salePaymentBreakdown(db, payload);
          if (fromPayload.total > 0) return fromPayload;
        }
      }
    }

    final amount = _asDouble(row['total_amount']);
    return switch (_string(row['payment_method']).toLowerCase()) {
      'cash' => _SalePaymentAmounts(cash: amount),
      'card' => _SalePaymentAmounts(card: amount),
      'transfer' => _SalePaymentAmounts(transfer: amount),
      'credit' ||
      'debt' ||
      'partial_debt' =>
        _SalePaymentAmounts(credit: amount),
      _ => const _SalePaymentAmounts(),
    };
  }

  List<Object?> _sessionQueryIds(
    Map<String, dynamic> sessionRow,
    String sessionId,
  ) {
    final ids = <String>{};
    final clientId = sessionId.trim();
    if (clientId.isNotEmpty) {
      ids.add(clientId);
    }
    final serverId =
        _nullableString(sessionRow['server_session_id'])?.trim() ?? '';
    if (serverId.isNotEmpty) {
      ids.add(serverId);
    }
    return ids.toList(growable: false);
  }

  String _sessionIdWhereClause(int count) {
    if (count <= 1) return '= ?';
    return 'IN (${List.filled(count, '?').join(', ')})';
  }

  bool _applyPayloadValue(
    Map<String, dynamic> payload,
    String key,
    String? value,
  ) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return false;
    if ((payload[key] ?? '').toString().trim() == normalized) return false;
    payload[key] = normalized;
    return true;
  }

  QueueListItem _queueItemFromRow(Map<String, dynamic> row) {
    final type =
        OutboxOperationTypeX.fromValue((row['type'] ?? '').toString()) ??
            OutboxOperationType.sale;
    final payload = decodeJsonMap((row['payload_json'] ?? '{}').toString());
    final title = switch (type) {
      OutboxOperationType.productCreate =>
        'Товар ${payload['name'] ?? payload['barcode'] ?? row['client_id']}',
      OutboxOperationType.sale =>
        'Чек №${payload['local_number'] ?? payload['client_sale_id'] ?? row['client_id']}',
      OutboxOperationType.payment => 'Платеж ${payload['amount'] ?? ''}'.trim(),
      OutboxOperationType.refund =>
        'Возврат ${payload['sale_id'] ?? row['client_id']}',
      OutboxOperationType.sessionOpen => 'Открытие смены',
      OutboxOperationType.sessionClose => 'Закрытие смены',
    };
    final subtitle = switch ((row['status'] ?? '').toString()) {
      'manual' =>
        (row['last_error_message'] ?? 'Требуется ручная обработка').toString(),
      'sending' => 'Отправляется...',
      _ => 'Ждет отправки',
    };

    return QueueListItem(
      id: (row['id'] ?? '').toString(),
      type: type,
      clientId: (row['client_id'] ?? '').toString(),
      status:
          OutboxOperationStatusX.fromValue((row['status'] ?? '').toString()) ??
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
      status:
          OutboxOperationStatusX.fromValue((row['status'] ?? '').toString()) ??
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
        ? itemsRaw.whereType<Map>().map((item) {
            final map = Map<String, dynamic>.from(item);
            final productId = (map['product_id'] ?? '').toString();
            final productName = (map['product_name'] ?? '').toString().trim();
            return SaleItemModel(
              id: (map['sale_item_id'] ?? '').toString(),
              saleId: (payload['client_sale_id'] ?? '').toString(),
              productId: productId,
              quantity: _asDouble(map['quantity']),
              price: _asDouble(map['price']),
              totalPrice: _asDouble(map['total_price']),
              product: productName.isEmpty
                  ? null
                  : sale_models.ProductModel(
                      id: productId,
                      name: productName,
                      measurementUnit: '',
                      arrivalCost: 0,
                      sellingPrice: _asDouble(map['price']),
                      wholesalePrice: 0,
                    ),
            );
          }).toList()
        : <SaleItemModel>[];
    final paymentsRaw = payload['payments'];
    final salePayments = (paymentsRaw is List)
        ? paymentsRaw
            .whereType<Map>()
            .map(
              (payment) => sale_models.SalePaymentModel.fromJson(
                Map<String, dynamic>.from(payment),
              ),
            )
            .toList(growable: false)
        : const <sale_models.SalePaymentModel>[];

    return SaleModel(
      localId: (payload['client_sale_id'] ?? '').toString(),
      number: (payload['local_number'] ?? '').toString(),
      date: _parseDt(payload['date']) ?? DateTime.now(),
      totalAmount: _asInt(payload['total_amount']),
      paymentMethod: (payload['payment_method'] ?? 'cash').toString(),
      paymentType: payload['payment_type']?.toString(),
      paidAmount: _asInt(payload['paid_amount']),
      debtAmount: _asInt(payload['debt_amount']),
      paidPaymentMethod: payload['paid_payment_method']?.toString(),
      dueDate: _parseDt(payload['due_date']),
      comment: payload['comment']?.toString(),
      idempotencyKey: payload['idempotency_key']?.toString(),
      posId: (payload['pos_id'] ?? '').toString(),
      storeId: (payload['store_id'] ?? '').toString(),
      userId: (payload['user_id'] ?? '').toString(),
      accountId: (payload['account_id'] ?? '').toString(),
      posSessionId: payload['pos_session_id']?.toString(),
      customerId: payload['customer_id']?.toString(),
      items: items,
      payments: salePayments,
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
    final countRow =
        _firstRow(db.select('SELECT COUNT(*) AS c FROM sales_history'));
    final total = _asInt(countRow?['c']);

    final offset = (page - 1) * perPage;
    final rows = db.select(
      'SELECT raw_json FROM sales_history ORDER BY date DESC LIMIT ? OFFSET ?',
      [perPage, offset],
    );

    final items = rows
        .map((row) {
          try {
            return SaleModel.fromJson(
                decodeJsonMap((row['raw_json'] ?? '{}').toString()));
          } catch (_) {
            return null;
          }
        })
        .whereType<SaleModel>()
        .toList(growable: false);

    return (items: items, total: total);
  }

  Future<List<SaleModel>> loadAllSalesHistory() async {
    final db = await _database;
    final rows = db.select(
      'SELECT raw_json FROM sales_history ORDER BY date DESC',
    );

    return rows
        .map((row) {
          try {
            return SaleModel.fromJson(
              decodeJsonMap((row['raw_json'] ?? '{}').toString()),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SaleModel>()
        .toList(growable: false);
  }

  Future<List<RefundModel>> loadAllRefundsHistory() async {
    final db = await _database;
    final rows = db.select('SELECT * FROM refunds ORDER BY date DESC');

    return rows.map((row) {
      final map = _rowMap(row);
      final refundId = _string(map['id']);
      final itemRows = db.select(
        'SELECT * FROM refund_items WHERE refund_id = ? ORDER BY id',
        [refundId],
      );
      final items = itemRows.map((itemRow) {
        final item = _rowMap(itemRow);
        return RefundItemModel(
          id: _string(item['id']),
          refundId: refundId,
          saleItemId: '',
          productId: _string(item['product_id']),
          quantity: _asInt(item['quantity']),
          price: _asInt(item['price']),
          maxQuantity: 0,
        );
      }).toList(growable: false);

      return RefundModel(
        id: refundId,
        number: _nullableString(map['number']),
        date: _parseDt(_string(map['date'])),
        totalAmount: _asInt(map['total_amount']),
        reason: _nullableString(map['reason']),
        reasonCode: _nullableString(map['reason_code']),
        note: _nullableString(map['note']),
        saleId: _nullableString(map['sale_id']),
        posId: _nullableString(map['pos_id']),
        storeId: _nullableString(map['store_id']),
        accountId: _nullableString(map['account_id']),
        items: items,
      );
    }).toList(growable: false);
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
    return DateTime.tryParse(
        raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw);
  }

  String _nowIso() => DateTime.now().toIso8601String();

  Map<String, dynamic> _buildStoredErrorPayload({
    Map<String, dynamic>? payload,
    Map<String, dynamic>? errorDetails,
  }) {
    return <String, dynamic>{
      'request_payload': payload ?? const <String, dynamic>{},
      if (errorDetails != null) 'error_details': errorDetails,
    };
  }

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
      case 'agent':
      case 'agents':
        return _EntityKind.customer;
      case 'return_access_key':
      case 'return_access_keys':
      case 'return-access-key':
      case 'return-access-keys':
        return _EntityKind.returnAccessKey;
      case 'sale':
      case 'sales':
        return _EntityKind.sale;
      case 'refund':
      case 'refunds':
        return _EntityKind.refund;
    }
    return null;
  }
}

enum _EntityKind {
  posInfo('pos_info'),
  product('products'),
  account('accounts'),
  expenseType('expense_types'),
  customer('customers'),
  returnAccessKey('return_access_keys'),
  sale('sales'),
  refund('refunds');

  const _EntityKind(this.table);
  final String table;
}
