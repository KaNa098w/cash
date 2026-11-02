import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supplies_controller.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supplies_page.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supply_editor.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supply_widgets.dart';
import 'supplies_contract_test.dart' show FakeSuppliesApi, document, apiError;

ProductModel product(String id, String name, String code) => ProductModel(
    id: id,
    name: name,
    barcode: code,
    measurementUnit: 'шт.',
    arrivalCost: 50,
    sellingPrice: 80,
    wholesalePrice: 0);

class EditorApi extends FakeSuppliesApi {
  EditorApi({super.directorUserId});
  int saves = 0, paymentWrites = 0;
  bool rejectStatus = false;
  @override
  Future<String> save(
      String key, String device, String manager, Map<String, dynamic> payload,
      {String? id}) async {
    saves++;
    current = SupplyDocument({...document(), ...payload, 'id': id ?? 'S1'});
    return current.id;
  }

  @override
  Future<void> status(String key, String device, String manager, String id,
      bool completed) async {
    if (rejectStatus) {
      throw apiError(422,
          data: {'message': 'Есть последующие операции с товаром'});
    }
    current = SupplyDocument({...current.json, 'completed': completed});
  }

  @override
  Future<void> payment(String key, String device, String manager, String id,
      Map<String, dynamic> payload,
      {String? paymentId}) async {
    paymentWrites++;
    current = SupplyDocument({
      ...current.json,
      'payments': [
        {
          'id': 'PAY1',
          ...payload,
          'account': {'name': 'Наличные'}
        }
      ],
      'payments_total': payload['amount'],
      'document_unpaid_amount': current.total - (payload['amount'] as num)
    });
  }
}

Future<void> mount(WidgetTester tester, Widget widget, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: const Key('supply-preview'),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSans'),
          home: widget)));
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('SUPPLIES_PREVIEWS')) return;
  final path = '${Directory.current.path}/build/supplies_previews';
  Directory(path).createSync(recursive: true);
  await expectLater(find.byKey(const Key('supply-preview')),
      matchesGoldenFile(Uri.file('$path/$name.png')));
}

Finder scanField() => find.byWidgetPredicate((w) =>
    w is TextField && w.decoration?.labelText == 'Сканируйте штрихкод товара');
Finder dropdown(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is SupplySelect && w.label == label),
    matching: find.byType(DropdownButton<String>));
Future<void> scan(WidgetTester tester, String barcode) async {
  await tester.ensureVisible(scanField());
  await tester.enterText(scanField(), barcode);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
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

  for (final size in [
    const Size(800, 600),
    const Size(1024, 768),
    const Size(1366, 768)
  ]) {
    testWidgets('supplies list and editor fit ${size.width}x${size.height}',
        (tester) async {
      final c =
          SuppliesController(api: EditorApi(), posKey: 'KEY', deviceId: 'D');
      addTearDown(c.dispose);
      await mount(tester, SuppliesPage(controller: c), size);
      expect(find.text('Приёмка № 0001'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await preview(tester, 'list-${size.width.toInt()}');
      await mount(
          tester,
          SupplyEditor(
              controller: c,
              document: SupplyDocument(document()),
              loadProducts: () async => []),
          size);
      expect(find.text('Сохранить черновик'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await preview(tester, 'editor-${size.width.toInt()}');
    });
  }

  testWidgets(
      'scanning merges exact matches, new product adds a line and saving retains server ID',
      (tester) async {
    final api = EditorApi();
    final c = SuppliesController(api: api, posKey: 'KEY', deviceId: 'D');
    addTearDown(c.dispose);
    await c.initialize();
    c.setManagerKey('manager');
    final milk = product('P1', 'Молоко', '1234567890123');
    await mount(
        tester,
        SupplyEditor(
            controller: c,
            draft: const {
              'supplier_id': 'V1',
              'warehouse_id': 'W1',
              'items': []
            },
            loadProducts: () async => [milk],
            createProduct: (_) async => product('P2', 'Хлеб', '9876543210123')),
        const Size(1024, 768));
    await scan(tester, '1234567890123');
    await scan(tester, '1234567890123');
    expect((await c.loadDraft())!['items'].length, 1);
    expect((await c.loadDraft())!['items'][0]['quantity'], 2);
    await tester.tap(find.text('Создать товар'));
    await tester.pumpAndSettle();
    expect((await c.loadDraft())!['items'].length, 2);
    await tester.tap(find.text('Сохранить черновик'));
    await tester.pumpAndSettle();
    expect(api.saves, 1);
    expect(find.text('Приёмка № 0001'), findsOneWidget);
    expect(await c.loadDraft(), isNull);
    await tester.tap(find.text('Сохранить черновик'));
    await tester.pumpAndSettle();
    expect(api.current.id, 'S1');
    expect(api.saves, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog selection adds a product without mutating a sale cart',
      (tester) async {
    final c = SuppliesController(api: EditorApi(), posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    await c.initialize();
    await mount(
        tester,
        SupplyEditor(
            controller: c,
            loadProducts: () async => [product('P1', 'Молоко', '123')]),
        const Size(1024, 768));
    await tester.tap(find.text('Выбрать товар'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Молоко'));
    await tester.pumpAndSettle();
    expect((await c.loadDraft())!['items'][0]['product_id'], 'P1');
    expect(find.text('Молоко'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server rejection preserves completed status and locked goods',
      (tester) async {
    final api = EditorApi()
      ..current = SupplyDocument(document(completed: true))
      ..rejectStatus = true;
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    await c.initialize();
    c.setManagerKey('m');
    await mount(
        tester,
        SupplyEditor(
            controller: c, document: api.current, loadProducts: () async => []),
        const Size(1024, 768));
    await tester.tap(find.text('В черновик'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(find.text('Проведена'), findsOneWidget);
    expect(find.textContaining('Есть последующие операции'), findsOneWidget);
    expect(c.pending, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a payment rereads document totals and list from server',
      (tester) async {
    final api = EditorApi();
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    await c.initialize();
    c.setManagerKey('m');
    await mount(
        tester,
        SupplyEditor(
            controller: c, document: api.current, loadProducts: () async => []),
        const Size(1024, 768));
    await tester.ensureVisible(find.text('Добавить оплату'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить оплату'));
    await tester.pumpAndSettle();
    await tester.tap(dropdown('Счёт списания'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Наличные').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить оплату'));
    await tester.pumpAndSettle();
    expect(api.paymentWrites, 1);
    expect(c.selected!.paid, 100);
    expect(c.selected!.unpaid, 0);
    expect(api.reads, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
