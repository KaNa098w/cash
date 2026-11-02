import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/models/product_creation_form.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/datasources/product_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supply_product_form.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supply_widgets.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supplies_controller.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supply_editor.dart';
import 'supplies_widgets_test.dart' show EditorApi, preview;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final family in ['NotoSans', 'Roboto']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  test(
      'full product payload retains leading zeroes, API units, pricing and packaging',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
        requests.add(o);
        handler.resolve(Response(requestOptions: o, statusCode: 201, data: {
          'data': {'id': 'P1', ...o.data}
        }));
      }));
    final api = ProductRemoteDataSource(dio);
    const form = ProductCreationForm(
        name: 'Кефир',
        barcode: '0012345678901',
        localBarcode: '00001',
        sku: 'SKU-1',
        categoryId: 'CAT',
        arrivalCost: 50,
        sellingPrice: 80,
        wholesalePrice: 70,
        measurementUnit: MeasurementUnit.kilogram,
        conversionValue: 12,
        conversionUnit: 'кор.');
    final product = await api.createFullProduct(
        key: 'K', deviceId: 'D', userId: 'DIR', form: form);
    expect(product.barcode, '0012345678901');
    expect(product.measurementUnit, 'кг.');
    expect(requests.single.data, containsPair('arrival_cost', 50));
    expect(requests.single.data, containsPair('wholesale_price', 70));
    expect(requests.single.data, containsPair('local_barcode', '00001'));
    expect(requests.single.data, containsPair('category_id', 'CAT'));
    expect(requests.single.data, containsPair('conversion_unit', 'кор.'));
    expect(requests.single.data['quantity'], isNull);
    expect(requests.single.headers['X-Return-Access-Key'], isNull);
    await api.createFullProduct(
        key: 'K',
        deviceId: 'D',
        userId: 'CASHIER',
        form: form,
        managerAccessKey: 'MANAGER');
    expect(requests.last.headers['X-Return-Access-Key'], 'MANAGER');
    expect(
        () => const ProductCreationForm(
                name: 'X', barcode: '12345678901234', sellingPrice: 1)
            .validate(),
        throwsStateError);
    expect(
        () => const ProductCreationForm(
                name: '', barcode: '0012345678901', sellingPrice: 1)
            .validate(),
        throwsStateError);
  });

  for (final size in [const Size(800, 600), const Size(1024, 768)]) {
    testWidgets(
        'touch barcode preserves zeros and full product form fits ${size.width}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SupplyCreatedProduct? result;
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
          requests.add(o);
          handler.resolve(Response(requestOptions: o, statusCode: 201, data: {
            'data': {'id': 'P1', ...o.data}
          }));
        }));
      await tester.pumpWidget(RepaintBoundary(
          key: const Key('supply-preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'NotoSans'),
              home: Builder(
                  builder: (context) => Scaffold(
                      body: FilledButton(
                          onPressed: () async {
                            result = await showDialog<SupplyCreatedProduct>(
                                context: context,
                                builder: (_) => SupplyProductForm(
                                    api: ProductRemoteDataSource(dio),
                                    posKey: 'K',
                                    deviceId: 'D',
                                    userId: 'DIR'));
                          },
                          child: const Text('Open')))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await preview(tester, 'product-full-${size.width.toInt()}');
      final name = find.byWidgetPredicate((w) =>
          w is TextField && w.decoration?.labelText == 'Название товара *');
      await tester.enterText(name, 'Кефир');
      final barcodeKeyboard = find.byTooltip('Ввести: Штрихкод *');
      await tester.ensureVisible(barcodeKeyboard);
      await tester.pumpAndSettle();
      await tester.tap(barcodeKeyboard);
      await tester.pumpAndSettle();
      await preview(tester, 'barcode-entry-${size.width.toInt()}');
      for (final digit in '0012345678901'.split('')) {
        await tester.ensureVisible(find.byKey(ValueKey('supply-code-$digit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('supply-code-$digit')));
        await tester.pump();
      }
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('supply-touch-input')))
              .controller!
              .text,
          '0012345678901');
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      final purchasePrice = find.text('Закупочная цена');
      await tester.ensureVisible(purchasePrice);
      await tester.pumpAndSettle();
      await tester.tap(purchasePrice);
      await tester.pumpAndSettle();
      await preview(tester, 'price-entry-${size.width.toInt()}');
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.ensureVisible(find.text('0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0'));
      await tester.pump();
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать и добавить'));
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      expect(result!.product.barcode, '0012345678901');
      expect(result!.arrivalPrice, 50);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'director can post a supply without opening manager access prompt',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = EditorApi(directorUserId: 'DIR');
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    await c.initialize();
    await tester.pumpWidget(MaterialApp(
        home: SupplyEditor(
            controller: c,
            document: api.current,
            loadProducts: () async => [])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Провести приёмку'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(find.text('Ключ управляющего магазина'), findsNothing);
    expect(c.hasManagerKey, isFalse);
    expect(c.selected!.completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch note changes use the common dialog and persist the draft',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = SuppliesController(api: EditorApi(), posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    await c.initialize();
    await tester.pumpWidget(MaterialApp(
        home: SupplyEditor(controller: c, loadProducts: () async => [])));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ввести: Комментарий к приёмке'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('supply-touch-input')), 'Поставка утром');
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect((await c.loadDraft())!['note'], 'Поставка утром');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'barcode dialog supports physical keyboard, selection replacement and backspace',
      (tester) async {
    String? value;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      value = await supplyTextDialog(context,
                          title: 'Штрихкод', numeric: true, initial: '00123');
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('supply-touch-input'));
    await tester.enterText(field, '0000123456789');
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection =
        const TextSelection(baseOffset: 12, extentOffset: 13);
    await tester.tap(find.byKey(const ValueKey('supply-code-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('supply-code-⌫')));
    await tester.pump();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(value, '000012345678');
    expect(tester.takeException(), isNull);
  });
}
