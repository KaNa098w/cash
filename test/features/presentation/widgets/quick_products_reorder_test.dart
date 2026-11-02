import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/pos_category.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/widgets/quit_products_screen.dart';

class _Sync extends PosSyncService {
  _Sync()
      : super(PosSyncLocalStore(database: sqlite3.openInMemory()),
            PosSyncRemoteDataSource(Dio()));
  @override
  Future<List<ProductModel>> loadFavoriteProducts() async => [
        for (var i = 1; i <= 3; i++)
          ProductModel(
              id: '$i',
              name: 'Product $i',
              measurementUnit: 'шт',
              arrivalCost: 100,
              sellingPrice: 200,
              wholesalePrice: 150,
              isFavorite: true),
      ];
  @override
  Future<List<PosCategory>> loadCategories() async => [];
}

void main() {
  testWidgets('holding swaps favorites, persists order and keeps tap selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sync = _Sync();
    sl.registerSingleton<PosSyncService>(sync);
    addTearDown(() async {
      sl.unregister<PosSyncService>();
      await sync.dispose();
    });
    ProductModel? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () async {
            selected = await showQuickProductsDialog(context,
                key: 'reorder-test', deviceId: '');
          },
          child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('quick-product-1'));
    final second = find.byKey(const ValueKey('quick-product-2'));
    final originalFirst = tester.getTopLeft(first);
    final originalSecond = tester.getTopLeft(second);
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveTo(tester.getCenter(second));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first), originalSecond);
    expect(tester.getTopLeft(second), originalFirst);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('quickProducts.order.reorder-test'),
        ['2', '1', '3']);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first), originalSecond);
    expect(tester.getTopLeft(second), originalFirst);
    await tester.tap(find.text('Product 1'));
    await tester.pumpAndSettle();
    expect(selected?.id, '1');
    expect(tester.takeException(), isNull);
  });
}
