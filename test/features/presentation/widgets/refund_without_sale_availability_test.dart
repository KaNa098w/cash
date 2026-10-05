import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_local_store.dart';
import 'package:leemon_app/features/data/sync/pos_sync_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/refund_without_sale/refund_without_sale_page.dart';

void main() {
  testWidgets('no-sale refund page is blocked when store does not permit it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PosSyncLocalStore(database: sqlite3.openInMemory());
    final sync = PosSyncService(store, PosSyncRemoteDataSource(Dio()));
    GetIt.I.registerSingleton<PosSyncService>(sync);
    addTearDown(() async {
      await GetIt.I.unregister<PosSyncService>();
      sync.dispose();
      await store.close();
    });
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthTokenProvider(),
      child: const MaterialApp(home: RefundWithoutSalePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Возврат без чека запрещён'), findsOneWidget);
    expect(find.text('Оформить возврат'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
