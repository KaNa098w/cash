import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/service/pos_diagnostics_service.dart';
import 'package:leemon_app/features/data/datasources/supplies_remote_datasource.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supplies_controller.dart';
import 'package:leemon_app/features/presentation/pages/supplies/supply_products.dart';

Map<String, dynamic> document({bool completed = false}) => {
      'id': 'S1',
      'number': '0001',
      'date': '2026-10-27',
      'completed': completed,
      'supplier_id': 'V1',
      'warehouse_id': 'W1',
      'total_amount': 100,
      'items': [
        {
          'product_id': 'P1',
          'name': 'Молоко',
          'quantity': 2,
          'arrival_price': 50,
          'price': 80
        }
      ],
      'payments': [],
      'payments_total': 0,
      'document_unpaid_amount': 100,
    };

DioException apiError(int code, {Map<String, dynamic>? data}) {
  final r = RequestOptions(path: '/supplies');
  return DioException(
      requestOptions: r,
      response: Response(requestOptions: r, statusCode: code, data: data));
}

class FakeSuppliesApi extends SuppliesRemoteDataSource {
  FakeSuppliesApi({String? directorUserId})
      : super(Dio(), directorUserId: directorUserId);
  SupplyDocument current = SupplyDocument(document());
  Object? readError;
  int reads = 0;
  bool deleted = false;
  @override
  Future<SupplyReferences> references(String key, String device) async =>
      const SupplyReferences(
          suppliers: [SupplyReference('V1', 'Поставщик')],
          warehouses: [SupplyReference('W1', 'Основной')],
          accounts: [SupplyReference('A1', 'Наличные')]);
  @override
  Future<SupplyPage> list(String key, String device,
          {int page = 1, Map<String, dynamic> filters = const {}}) async =>
      SupplyPage(items: deleted ? [] : [current]);
  @override
  Future<SupplyDocument> get(String key, String device, String id) async {
    reads++;
    if (readError != null) throw readError!;
    if (deleted) throw apiError(404);
    return current;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'director writes use active user identity without a manager key for every operation',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
        requests.add(o);
        handler.resolve(Response(
            requestOptions: o,
            statusCode: o.method == 'DELETE' ? 204 : 200,
            data: {'data': document()}));
      }));
    final api = SuppliesRemoteDataSource(dio).forDirector('DIRECTOR');
    await api.save('K', 'D', '', {'date': '2026-10-27'});
    await api.save('K', 'D', '', {'date': '2026-10-27'}, id: 'S1');
    await api.status('K', 'D', '', 'S1', true);
    await api.delete('K', 'D', '', 'S1');
    await api.supplier('K', 'D', '', {'name': 'Поставщик'});
    await api.payment('K', 'D', '', 'S1', {'amount': 100});
    await api.payment('K', 'D', '', 'S1', {'amount': 90}, paymentId: 'PAY');
    await api.deletePayment('K', 'D', '', 'S1', 'PAY');
    expect(requests.length, 8);
    for (final request in requests) {
      expect(request.data['user_id'], 'DIRECTOR');
      expect(request.data['device_id'], 'D');
      expect(request.headers['X-Return-Access-Key'], isNull);
    }
    final c = SuppliesController(
        api: FakeSuppliesApi(directorUserId: 'DIRECTOR'),
        posKey: 'K',
        deviceId: 'D');
    addTearDown(c.dispose);
    expect(c.hasManagerKey, isFalse);
    expect(c.canWrite, isTrue);
    expect(
        await c.mutate('Сохранить', (manager) async {
          expect(manager, '');
          return 'S1';
        }),
        isTrue);
  });

  test(
      'all supplies endpoints use device placement and manager header only on writes',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, handler) {
      requests.add(o);
      final response = o.path.endsWith('/references')
          ? {
              'data': {'suppliers': [], 'warehouses': [], 'accounts': []}
            }
          : o.method == 'GET' && o.path.endsWith('/supplies')
              ? {
                  'data': [],
                  'meta': {'current_page': 2, 'last_page': 3},
                  'summary': {'count': 4}
                }
              : {'data': document()};
      handler.resolve(Response(
          requestOptions: o,
          statusCode: o.method == 'DELETE' ? 204 : 200,
          data: o.method == 'DELETE' ? null : response));
    }));
    final api = SuppliesRemoteDataSource(dio);
    await api.references('KEY', 'DEV');
    final page = await api.list('KEY', 'DEV', page: 2, filters: {
      'supplier_id': 'V1',
      'from': '2026-10-01',
      'completed': false,
      'payment_status': 'unpaid'
    });
    expect(page.page, 2);
    expect(page.lastPage, 3);
    expect(page.summary['count'], 4);
    await api.get('KEY', 'DEV', 'S1');
    final body = {
      'date': '2026-10-27',
      'supplier_id': 'V1',
      'warehouse_id': 'W1',
      'completed': false,
      'items': [
        SupplyLine(productId: 'P1', name: 'Товар', arrivalPrice: 40, price: 60)
            .toRequest()
      ]
    };
    expect(await api.save('KEY', 'DEV', ' MANAGER ', body), 'S1');
    await api.save('KEY', 'DEV', 'MANAGER', body, id: 'S1');
    await api.status('KEY', 'DEV', 'MANAGER', 'S1', true);
    await api.delete('KEY', 'DEV', 'MANAGER', 'S1');
    await api.supplier('KEY', 'DEV', 'MANAGER', {'name': 'Поставщик'});
    await api.payment('KEY', 'DEV', 'MANAGER', 'S1',
        {'account_id': 'A1', 'amount': 100, 'date': '2026-10-27'});
    await api.payment('KEY', 'DEV', 'MANAGER', 'S1',
        {'account_id': 'A1', 'amount': 90, 'date': '2026-10-27'},
        paymentId: 'PAY1');
    await api.deletePayment('KEY', 'DEV', 'MANAGER', 'S1', 'PAY1');
    expect(requests.map((r) => '${r.method} ${r.path}'), [
      'GET /organizations/pos/KEY/supplies/references',
      'GET /organizations/pos/KEY/supplies',
      'GET /organizations/pos/KEY/supplies/S1',
      'POST /organizations/pos/KEY/supplies',
      'PUT /organizations/pos/KEY/supplies/S1',
      'PATCH /organizations/pos/KEY/supplies/S1/status',
      'DELETE /organizations/pos/KEY/supplies/S1',
      'POST /organizations/pos/KEY/supplies/suppliers',
      'POST /organizations/pos/KEY/supplies/S1/payments',
      'PUT /organizations/pos/KEY/supplies/S1/payments/PAY1',
      'DELETE /organizations/pos/KEY/supplies/S1/payments/PAY1'
    ]);
    for (final r in requests) {
      if (r.method == 'GET') {
        expect(r.queryParameters['device_id'], 'DEV');
        expect(r.headers['X-Return-Access-Key'], isNull);
      } else {
        expect(r.headers['X-Return-Access-Key'], 'MANAGER');
        expect(r.data['device_id'], 'DEV');
        expect(r.data.containsKey('organization_id'), isFalse);
        expect(r.data.containsKey('store_id'), isFalse);
      }
    }
    expect(requests[5].data['completed'], isTrue);
    expect(dio.options.headers['X-Return-Access-Key'], isNull);
    await expectLater(
        api.status('KEY', 'DEV', '', 'S1', true), throwsStateError);
    expect(requests.length, 11);
  });

  test(
      'supply models retain payment totals, warehouse, quantities and server pagination',
      () {
    final d = SupplyDocument({
      ...document(),
      'payments_total': '40.25',
      'document_unpaid_amount': '59.75',
      'payments': [
        {
          'id': 'PAY',
          'account_id': 'A',
          'amount': '40.25',
          'date': '2026-10-27',
          'comment': 'Часть'
        }
      ]
    });
    expect(d.items.single.quantity, 2);
    expect(d.items.single.total, 100);
    expect(d.paid, 40.25);
    expect(d.unpaid, 59.75);
    expect(d.payments.single.comment, 'Часть');
    final l = SupplyLine(
        productId: 'p',
        name: 'Мука',
        quantity: 1.25,
        arrivalPrice: 12.34,
        price: 20);
    expect(l.total, 15.43);
    expect(l.valid, isTrue);
    l.quantity = double.nan;
    expect(l.valid, isFalse);
    expect(SupplyLine.fromJson({...l.toDraft(), 'quantity': 1.25}).unit, 'шт.');
    expect(
        SupplyPage.fromJson({
          'data': [document()],
          'current_page': 2,
          'last_page': 4
        }).lastPage,
        4);
  });

  test('scanner accepts only exact barcodes/local codes and exposes ambiguity',
      () {
    ProductModel product(String id, String barcode) => ProductModel(
        id: id,
        name: 'Товар $barcode',
        barcode: barcode,
        measurementUnit: 'шт.',
        arrivalCost: 10,
        sellingPrice: 20,
        wholesalePrice: 0);
    final p = product('P', '123456789');
    expect(supplyBarcodeMatches([p], '123456'), isEmpty);
    expect(supplyBarcodeMatches([p, p], '123456789').length, 1);
    expect(
        supplyBarcodeMatches([p, product('OTHER', '123456789')], '123456789')
            .length,
        2);
  });

  test('401, 404 and 422 expose useful field errors', () {
    expect(supplyError(apiError(401)), contains('ключ'));
    expect(supplyError(apiError(404)), contains('недоступен'));
    expect(
        supplyError(apiError(422, data: {
          'errors': {
            'items.0.quantity': ['Количество больше нуля'],
            'supplier_id': ['Не найден']
          }
        })),
        allOf(contains('items.0.quantity'), contains('Количество больше нуля'),
            contains('supplier_id')));
  });

  test('manager access keys are excluded from diagnostic reports', () {
    final diagnostics = PosDiagnosticsService();
    diagnostics.recordRequest(RequestOptions(path: '/supplies', headers: {
      'X-Return-Access-Key': 'secret-manager',
      'Authorization': 'secret-pos',
      'device_id': 'D'
    }));
    final report = jsonEncode(diagnostics.buildReport());
    expect(report, isNot(contains('secret-manager')));
    expect(report, isNot(contains('secret-pos')));
    expect(report, contains('<redacted>'));
  });

  test(
      'writes require a manager key; rejection keeps document status and draft',
      () async {
    final api = FakeSuppliesApi();
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    var calls = 0;
    expect(
        await c.mutate('Тест', (_) async {
          calls++;
          return null;
        }),
        isFalse);
    expect(calls, 0);
    c.selected = SupplyDocument(document(completed: true));
    await c.saveDraft({'note': 'Сохранить'});
    c.setManagerKey('m');
    expect(
        await c.mutate(
            'В черновик',
            (_) async => throw apiError(422,
                data: {'message': 'Есть последующие операции'}),
            documentId: 'S1'),
        isFalse);
    expect(c.selected!.completed, isTrue);
    expect(c.pending, isNull);
    expect(c.error, contains('последующие'));
    expect((await c.loadDraft())!['note'], 'Сохранить');
    await c.mutate('Запись', (_) async => throw apiError(401));
    expect(c.hasManagerKey, isFalse);
  });

  test('lost write response survives restart and never retries without review',
      () async {
    final api = FakeSuppliesApi();
    var writes = 0;
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    c.setManagerKey('manager-secret');
    await c.mutate('Оплата', (_) async {
      writes++;
      throw TimeoutException('lost');
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(c.pendingKey), isNot(contains('manager-secret')));
    final restarted = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(restarted.dispose);
    c.dispose();
    await restarted.initialize();
    restarted.setManagerKey('new');
    expect(restarted.pending, isNotNull);
    expect(
        await restarted.mutate('Оплата', (_) async {
          writes++;
          return null;
        }),
        isFalse);
    expect(writes, 1);
    await restarted.acknowledgeReviewedOperation();
    expect(restarted.pending, isNull);
  });

  test(
      'accepted write with failed detail read reconciles via GET only on restart',
      () async {
    final api = FakeSuppliesApi()..readError = TimeoutException('read lost');
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    c.setManagerKey('m');
    var writes = 0;
    expect(
        await c.mutate('Сохранить', (_) async {
          writes++;
          return 'S1';
        }),
        isFalse);
    expect(c.pending!['confirmed'], isTrue);
    api.readError = null;
    final restarted = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(restarted.dispose);
    c.dispose();
    await restarted.initialize();
    expect(restarted.pending, isNull);
    expect(restarted.selected!.id, 'S1');
    expect(writes, 1);
  });

  test('server ID reaches the durable draft before the write marker is cleared',
      () async {
    final c =
        SuppliesController(api: FakeSuppliesApi(), posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    c.setManagerKey('m');
    await c.saveDraft({'id': null, 'items': [], 'note': 'Не создавать дважды'});
    expect(
        await c.mutate('Сохранение', (_) async => 'S1',
            attachDraftIdentity: true),
        isTrue);
    expect((await c.loadDraft())!['id'], 'S1');
    expect(c.pending, isNull);
  });

  test('deletion accepts 404 only as confirmation of an acknowledged delete',
      () async {
    final api = FakeSuppliesApi()..deleted = true;
    final c = SuppliesController(api: api, posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    c.setManagerKey('m');
    expect(
        await c.mutate('Удалить', (_) async => 'S1',
            documentId: 'S1', deleting: true),
        isTrue);
    expect(c.pending, isNull);
    expect(c.selected, isNull);
    expect(await c.mutate('Создать', (_) async => 'S1'), isFalse);
    expect(c.pending!['confirmed'], isTrue);
  });

  test('parallel writes are blocked and local drafts are scoped to POS/device',
      () async {
    final c =
        SuppliesController(api: FakeSuppliesApi(), posKey: 'K', deviceId: 'D');
    addTearDown(c.dispose);
    c.setManagerKey('m');
    final wait = Completer<String?>();
    var calls = 0;
    final first = c.mutate('Первый', (_) {
      calls++;
      return wait.future;
    });
    expect(
        await c.mutate('Второй', (_) async {
          calls++;
          return null;
        }),
        isFalse);
    wait.complete('S1');
    await first;
    expect(calls, 1);
    await c
        .saveDraft({'date': '2026-10-27', 'items': [], 'note': 'Восстановить'});
    final other = SuppliesController(
        api: FakeSuppliesApi(), posKey: 'K', deviceId: 'OTHER');
    addTearDown(other.dispose);
    expect(await other.loadDraft(), isNull);
    expect((await c.loadDraft())!['note'], 'Восстановить');
  });
}
