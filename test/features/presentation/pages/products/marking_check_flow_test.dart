import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/marking_check.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/conversion_product_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/marking_cart_observer.dart';
import 'marked_cart_test.dart' show EmptyRepository;

const product = Product(
    id: 'PRODUCT',
    name: 'Коробка',
    price: 15,
    measurementUnit: 'шт',
    requiresMarking: true);
const rawCode = ']d2010460026601046921MiXeD\x1D93AbC';

MarkingCheckResponse answer(
        {bool ready = true,
        String? error,
        int required = 0,
        double open = 2,
        double missing = 0,
        int provided = 0}) =>
    MarkingCheckResponse.fromJson({
      'data': {
        'ready': ready,
        'items': [
          {
            'product_id': 'PRODUCT',
            'requires_marking': true,
            'ready': ready,
            'scan_required': required > 0,
            'open_quantity': open,
            'package_quantity': 5.0,
            'provided_codes_count': provided.toDouble(),
            'required_codes_count': required.toDouble(),
            'missing_quantity': missing,
            'error_code': error,
          }
        ]
      }
    });

class FakeAuth extends AuthTokenProvider {
  @override
  String get posKey => 'KEY';
  @override
  String get storeId => 'STORE';
  @override
  String get deviceId => 'DEVICE';
}

class FakeChecks extends SaleRemoteDataSource {
  FakeChecks() : super(Dio());
  final requests = <List<Map<String, dynamic>>>[];
  late Future<MarkingCheckResponse> Function(List<Map<String, dynamic>>)
      respond;
  @override
  Future<MarkingCheckResponse> checkMarking(
      {required String key,
      required String storeId,
      required String deviceId,
      required List<Map<String, dynamic>> items}) async {
    expect([key, storeId, deviceId], ['KEY', 'STORE', 'DEVICE']);
    requests.add(items);
    return respond(items);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PosCubit cubit;
  late FakeChecks api;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(Duration.zero);
    api = FakeChecks();
    sl.registerSingleton<SaleRemoteDataSource>(api);
  });
  tearDown(() async {
    await cubit.close();
    await sl.reset();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthTokenProvider>(
        create: (_) => FakeAuth(),
        child: BlocProvider.value(
            value: cubit,
            child: MaterialApp(
                home: Scaffold(
                    body: Builder(
                        builder: (context) => ElevatedButton(
                            onPressed: () => ensureCartMarkingReady(context),
                            child: const Text('Проверить корзину'))))))));
    await tester.tap(find.text('Проверить корзину'));
    await tester.pumpAndSettle();
  }

  testWidgets('ordinary cart skips the marking endpoint entirely',
      (tester) async {
    cubit.addWithQty(
        const Product(id: 'ORDINARY', name: 'Обычный товар', price: 15), 2);
    await mount(tester);
    expect(api.requests, isEmpty);
    expect(cubit.markingCheckPassed, isTrue);
    expect(cubit.requiresOnlinePayment, isFalse);
    cubit.setQty(0, 3);
    expect(cubit.markingCheckPassed, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
  });

  test('marked goods require online even without a newly scanned code', () {
    cubit.addWithQty(product, 2);
    expect(cubit.requiresOnlinePayment, isTrue);
    expect(cubit.markingCheckPassed, isFalse);
    cubit.applyMarkingCheck(cubit.markingSnapshot, answer());
    expect(cubit.markingCheckPassed, isTrue);
    expect(cubit.requiresOnlinePayment, isTrue);
  });

  test('codes require online even if product flag is absent', () {
    cubit.addWithQty(const Product(id: 'PRODUCT', name: 'Товар', price: 15), 2,
        markCodes: [rawCode]);
    expect(cubit.requiresOnlinePayment, isTrue);
    expect(cubit.markingCheckPassed, isFalse);
  });

  test(
      'restored payment preserves background mode but legacy requests reconcile online',
      () async {
    cubit.addWithQty(
        const Product(id: 'ORDINARY', name: 'Обычный товар', price: 15), 2);
    await cubit.saveCheckout({'sale': {}, 'requires_online': false});
    final restored = PosState.fromJson(cubit.state.toJson());
    expect(restored.activeTicket.checkout!['requires_online'], isFalse);
    expect(cubit.requiresOnlinePayment, isFalse);
    cubit.releaseCheckout();
    await cubit.saveCheckout({'sale': {}});
    expect(cubit.requiresOnlinePayment, isTrue);
  });

  test('numeric JSON accepts int/double and errors never allow payment', () {
    final result = answer(ready: false, error: 'EXTRA_MARK_CODE');
    expect(result.canPay, isFalse);
    expect(result.items.single.scanRequired, isFalse);
    expect(result.items.single.packageQuantity, 5.0);
    expect(result.items.single.requiredCodesCount, 0);
  });

  test('raw marking survives cart, draft restore and quantity changes', () {
    cubit.addWithQty(product, 4, markCodes: [rawCode]);
    expect(cubit.state.items.single.markCodes, [rawCode]);
    cubit.applyMarkingCheck(cubit.markingSnapshot, answer());
    expect(cubit.markingCheckPassed, isTrue);
    final restored = PosState.fromJson(cubit.state.toJson());
    expect(restored.items.single.markCodes, [rawCode]);
    expect(restored.items.single.markingCheck, isNull);
    final previous = cubit.markingSnapshot;
    cubit.setQty(0, 5);
    expect(cubit.markingCheckPassed, isFalse);
    cubit.applyMarkingCheck(previous, answer());
    expect(cubit.markingCheckPassed, isFalse);
    cubit.applyMarkingCheck(cubit.markingSnapshot, answer());
    cubit.markingScope = 'OTHER_STORE';
    expect(cubit.markingCheckPassed, isFalse);
    cubit.removeAt(0);
    expect(cubit.state.items, isEmpty);
  });

  testWidgets('open package covers sale without asking for DataMatrix',
      (tester) async {
    cubit.addWithQty(product, 2);
    api.respond = (_) async => answer();
    await mount(tester);
    expect(cubit.markingCheckPassed, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.requests.single.single['mark_codes'], isEmpty);
  });

  testWidgets('deficit requests one box and rechecks unmodified pasted code',
      (tester) async {
    cubit.addWithQty(product, 4);
    api.respond = (items) async => (items.single['mark_codes'] as List).isEmpty
        ? answer(ready: false, required: 1, missing: 2)
        : answer(provided: 1);
    await mount(tester);
    expect(cubit.markingCheckPassed, isFalse);
    expect(find.text('Не хватает'), findsOneWidget);
    await tester.enterText(find.byType(TextField), rawCode);
    await tester.tap(find.byTooltip('Проверить код'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(api.requests, hasLength(2));
    expect(api.requests.last.single['mark_codes'], [rawCode]);
    expect(cubit.markingCheckPassed, isTrue);
  });

  testWidgets('extra code is removed and whole cart rechecked', (tester) async {
    cubit.addWithQty(product, 2, markCodes: [rawCode]);
    api.respond = (items) async =>
        (items.single['mark_codes'] as List).isNotEmpty
            ? answer(ready: false, error: 'EXTRA_MARK_CODE', provided: 1)
            : answer();
    await mount(tester);
    expect(api.requests, hasLength(2));
    expect(cubit.state.items.single.markCodes, isEmpty);
    expect(cubit.markingCheckPassed, isTrue);
  });

  testWidgets('stale result cannot authorize changed quantity', (tester) async {
    cubit.addWithQty(product, 2);
    final pending = Completer<MarkingCheckResponse>();
    api.respond = (_) => api.requests.length == 1
        ? pending.future
        : Future.value(answer(ready: false, required: 1, missing: 2));
    await mount(tester);
    cubit.setQty(0, 4);
    pending.complete(answer());
    await tester.pumpAndSettle();
    expect(api.requests.last.single['quantity'], 4);
    expect(cubit.markingCheckPassed, isFalse);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });

  test('HTTP check sends full cart and raw codes to read-only endpoint',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/organizations/pos/KEY/sales/marking-check');
      expect(options.data['store_id'], 'STORE');
      expect(options.data['items'], hasLength(2));
      expect(options.data['items'][0]['mark_codes'], [rawCode]);
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'data': {'ready': true, 'items': []}
      }));
    }));
    await SaleRemoteDataSource(dio)
        .checkMarking(key: 'KEY', storeId: 'STORE', deviceId: 'DEVICE', items: [
      {
        'product_id': 'A',
        'quantity': 4,
        'mark_codes': [rawCode]
      },
      {'product_id': 'B', 'quantity': 1, 'mark_codes': []}
    ]);
  });

  for (final error in ['MARK_CODE_CONFLICT', 'VALIDATION_FAILED']) {
    testWidgets('$error removes invalid code and requests replacement',
        (tester) async {
      cubit.addWithQty(product, 4, markCodes: ['bad-code']);
      api.respond = (items) async {
        final codes = items.single['mark_codes'] as List;
        if (codes.contains('bad-code')) {
          if (error == 'MARK_CODE_CONFLICT') {
            return answer(ready: false, error: error);
          }
          final options = RequestOptions(path: '/sales/marking-check');
          throw DioException(
              requestOptions: options,
              response:
                  Response(requestOptions: options, statusCode: 422, data: {
                'error_code': error,
                'errors': {
                  'items.0.mark_codes.0': ['Неверный формат']
                }
              }));
        }
        return codes.isEmpty
            ? answer(ready: false, required: 1, missing: 2)
            : answer();
      };
      await mount(tester);
      expect(cubit.state.items.single.markCodes, isEmpty);
      expect(cubit.markingCheckPassed, isFalse);
      await tester.enterText(find.byType(TextField), rawCode);
      await tester.tap(find.byTooltip('Проверить код'));
      await tester.pumpAndSettle();
      expect(api.requests, hasLength(3));
      expect(cubit.markingCheckPassed, isTrue);
    });
  }

  testWidgets('network failure revokes previous permission', (tester) async {
    cubit.addWithQty(product, 2);
    cubit.markingScope = 'KEY/STORE/DEVICE';
    cubit.applyMarkingCheck(cubit.markingSnapshot, answer());
    expect(cubit.markingCheckPassed, isTrue);
    api.respond = (_) async => throw DioException(
        requestOptions: RequestOptions(path: '/check'),
        type: DioExceptionType.connectionTimeout);
    await mount(tester);
    expect(cubit.markingCheckPassed, isFalse);
  });

  test('confirmed marking correction never unlocks quantity or payments',
      () async {
    cubit.addWithQty(product, 4);
    final id = cubit.ensureClientSaleId();
    await cubit.saveCheckout({
      'needs_marking_check': true,
      'sale': {'client_sale_id': id},
      'payments': [
        {'amount': 60}
      ]
    });
    cubit.setMarkCodes(0, [rawCode], correctingCheckoutMarking: true);
    cubit.setQty(0, 20);
    cubit.removeAt(0);
    expect(cubit.state.items.single.qty, 4);
    expect(cubit.state.items.single.markCodes, [rawCode]);
    expect(cubit.state.activeTicket.checkout!['payments'], [
      {'amount': 60}
    ]);
    expect(cubit.ensureClientSaleId(), id);
    await cubit.saveCheckout({'needs_marking_check': false});
    cubit.setMarkCodes(0, ['changed'], correctingCheckoutMarking: true);
    expect(cubit.state.items.single.markCodes, [rawCode]);
  });

  testWidgets('quantity and removal automatically check the whole cart',
      (tester) async {
    api.respond = (items) async => MarkingCheckResponse(
        ready: true,
        items: items
            .map((item) => MarkingCheckItem.fromJson(
                {'product_id': item['product_id'], 'ready': true}))
            .toList());
    await tester.pumpWidget(ChangeNotifierProvider<AuthTokenProvider>(
        create: (_) => FakeAuth(),
        child: BlocProvider.value(
            value: cubit,
            child: const MaterialApp(
                home:
                    Scaffold(body: MarkingCartObserver(child: SizedBox()))))));
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
    cubit.addWithQty(product, 2);
    cubit.addWithQty(
        const Product(
            id: 'OTHER', name: 'Другой', price: 1, measurementUnit: 'шт'),
        1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(api.requests.last, hasLength(2));
    cubit.setQty(0, 4);
    expect(cubit.markingCheckPassed, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(api.requests.last.first['quantity'], 4);
    cubit.removeAt(1);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(api.requests.last, hasLength(1));
    expect(cubit.markingCheckPassed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
