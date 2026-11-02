import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';

void main() {
  test('5000 products decode without blocking the event loop or losing stock',
      () async {
    final db = sqlite3.openInMemory();
    final store = PosSyncLocalStore(database: db);
    addTearDown(store.close);
    final insert = db.prepare('''
      INSERT INTO products (id, name, raw_json, updated_at_local)
      VALUES (?, ?, ?, ?)
    ''');
    db.execute('BEGIN');
    for (var i = 0; i < 5000; i++) {
      final name = 'Product ${i.toString().padLeft(4, '0')}';
      insert.execute([
        '$i',
        name,
        jsonEncode({'id': '$i', 'name': name, 'price': 123, 'quantity': 8}),
        '2026-10-31',
      ]);
    }
    db.execute('COMMIT');
    insert.dispose();
    var eventLoopRan = false;
    Timer.run(() => eventLoopRan = true);
    final products = await store.loadProducts();
    expect(eventLoopRan, isTrue);
    expect(products, hasLength(5000));
    expect(products.first.name, 'Product 0000');
    expect(products.last.name, 'Product 4999');
    expect(products.fold<double>(0, (sum, p) => sum + p.quantity), 40000);
  });
}
