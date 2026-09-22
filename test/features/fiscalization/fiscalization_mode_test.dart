import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/models/fiscalization_mode.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/presentation/widgets/fiscalization_toggle.dart';
import '../data/sync/marked_sale_sync_test.dart' show sale;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('ordinary sales default to skip; marked goods cannot opt out', () {
    for (final enabled in [false, true]) {
      for (final onlyMarked in [false, true]) {
        for (final marked in [false, true]) {
          final value = resolveFiscalizationMode(
              enabled: enabled,
              markedProductsOnly: onlyMarked,
              cartHasMarkedProducts: marked);
          expect(value == FiscalizationMode.fiscal, enabled && marked);
        }
      }
    }
    expect(
        resolveFiscalizationMode(
            enabled: true,
            markedProductsOnly: false,
            cartHasMarkedProducts: true,
            selected: FiscalizationMode.skip),
        FiscalizationMode.fiscal);
    expect(
        resolveFiscalizationMode(
            enabled: true,
            markedProductsOnly: false,
            cartHasMarkedProducts: false,
            selected: FiscalizationMode.skip),
        FiscalizationMode.skip);
  });
  test('POS marked-only setting survives application restart', () async {
    final config = PosFiscalizationConfig.fromJson({
      'enabled': true,
      'provider': 'webkassa',
      'marked_products_only': true,
      'fiscal_receipt_poll_interval_seconds': 2
    });
    expect(config.markedProductsOnly, isTrue);
    final auth = AuthTokenProvider();
    await auth.setProvisioned(PosProvisionResponse(
        id: 'P',
        name: 'Касса',
        key: 'KEY',
        accountId: 'A',
        storeId: 'S',
        storeName: 'Магазин',
        organizationId: 'O',
        users: [],
        fiscalization: config));
    final restored = AuthTokenProvider();
    await restored.init();
    expect(restored.fiscalizationEnabled, isTrue);
    expect(restored.fiscalizationMarkedProductsOnly, isTrue);
    expect(restored.fiscalizationPollSeconds, 2);
    await restored.clearProvisioned();
    expect(restored.fiscalizationMarkedProductsOnly, isFalse);
    auth.dispose();
    restored.dispose();
  });
  test(
      'sale mode survives cache, API and copyWith; legacy cache stays unspecified',
      () {
    for (final mode in FiscalizationMode.values) {
      final value = sale().copyWith(fiscalizationMode: mode);
      expect(value.toApiJson()['fiscalization_mode'], mode.name);
      expect(SaleModel.fromJson(value.toJson()).fiscalizationMode, mode);
      expect(
          SaleModel.fromApiJson({'id': 'SALE', ...value.toApiJson()})
              .fiscalizationMode,
          mode);
      expect(value.copyWith(comment: 'New comment').fiscalizationMode, mode);
    }
    final legacy = sale().toJson()..remove('fiscalizationMode');
    expect(SaleModel.fromJson(legacy).fiscalizationMode, isNull);
  });
  testWidgets(
      'toggle hides when disabled, locks for marking and accepts ordinary choice',
      (tester) async {
    FiscalizationMode? choice;
    Future<void> mount(
            {bool enabled = true, bool marked = false, bool locked = false}) =>
        tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: FiscalizationToggle(
                    enabled: enabled,
                    hasMarkedProducts: marked,
                    mode: FiscalizationMode.fiscal,
                    locked: locked,
                    onChanged: (v) => choice = v))));
    await mount(enabled: false);
    expect(find.byType(Switch), findsNothing);
    await mount(marked: true);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await mount(locked: true);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await mount();
    await tester.tap(find.byType(Switch));
    expect(choice, FiscalizationMode.skip);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
