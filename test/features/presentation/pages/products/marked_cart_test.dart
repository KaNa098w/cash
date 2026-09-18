import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/conversion_product_dialog.dart';

class EmptyRepository implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const product = Product(
      id: 'PRODUCT',
      name: 'Упаковка',
      price: 120,
      measurementUnit: 'шт.',
      requiresMarking: true,
      gtin: '04600266010469',
      conversionValue: 10,
      conversionUnit: 'уп.');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('package coverage clearly reports scanned and missing quantities', () {
    const empty = MarkingPackageCoverage(
      quantity: 15,
      packageQuantity: 10,
      packageCount: 0,
    );
    expect(empty.covered, 0);
    expect(empty.missing, 15);
    expect(empty.needsNewPackage, isTrue);

    const oneBox = MarkingPackageCoverage(
      quantity: 15,
      packageQuantity: 10,
      packageCount: 1,
    );
    expect(oneBox.covered, 10);
    expect(oneBox.missing, 5);
    expect(oneBox.needsNewPackage, isTrue);

    const twoBoxes = MarkingPackageCoverage(
      quantity: 15,
      packageQuantity: 10,
      packageCount: 2,
    );
    expect(twoBoxes.covered, 15);
    expect(twoBoxes.missing, 0);
    expect(twoBoxes.needsNewPackage, isFalse);

    const serverCheck = MarkingPackageCoverage(
      quantity: 15,
      packageQuantity: 10,
      packageCount: 0,
      alreadyCovered: 12,
    );
    expect(serverCheck.covered, 12);
    expect(serverCheck.missing, 3);
    expect(serverCheck.needsNewPackage, isTrue);
  });

  testWidgets('marking dialog shows only the essential package numbers',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMarkingPackageScanDialog(
              context,
              productName: 'Тестовый товар',
              quantity: 15,
              packageQuantity: 10,
              gtin: '04600266010469',
              initialCodes: const ['010460026601046921BOX-1'],
              usedCodes: const {},
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('Количество'), findsOneWidget);
    expect(find.text('Пробито'), findsOneWidget);
    expect(find.text('Не хватает'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Нужна новая коробка • 10 шт.'), findsOneWidget);
    expect(find.text('Сканируйте новую коробку'), findsOneWidget);
  });

  test('draft can change quantity freely without codes or network requests',
      () async {
    final cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(Duration.zero);
    cubit.addWithQty(product, 3);
    expect(cubit.state.items.single.markCodes, isEmpty);
    cubit.setQty(0, 12);
    expect(cubit.state.items.single.qty, 12);
    cubit.setQty(0, 1.5);
    expect(cubit.state.items.single.qty, 12);
    cubit.removeAt(0);
    expect(cubit.state.items, isEmpty);
    await cubit.close();
  });

  test(
      'confirmed checkout survives restart with UUID and prevents item editing',
      () async {
    var cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(Duration.zero);
    cubit.addWithQty(product, 3);
    cubit.setReceived(360);
    final id = cubit.ensureClientSaleId();
    await cubit.saveCheckout({
      'sale': {'client_sale_id': id},
      'payments': [
        {'amount': '360.00'}
      ]
    });
    cubit.setQty(0, 9);
    cubit.removeAt(0);
    expect(cubit.state.items.single.qty, 3);
    await cubit.close();
    cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cubit.ensureClientSaleId(), id);
    expect(cubit.state.received, 360);
    expect(cubit.state.activeTicket.checkout!['payments'], [
      {'amount': '360.00'}
    ]);
    cubit.clearAfterPayment();
    expect(cubit.state.items, isNotEmpty);
    cubit.clearAfterPayment(closeCompletedTicket: true);
    expect(cubit.state.activeTicket.checkout, isNull);
    expect(cubit.ensureClientSaleId(), isNot(id));
    await cubit.close();
  });

  test('rejected checkout unlocks the cart for deletion', () async {
    final cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(Duration.zero);
    cubit.addWithQty(product, 3);
    await cubit.saveCheckout({
      'sale': {'client_sale_id': cubit.ensureClientSaleId()},
      'payments': const [],
    });

    cubit.releaseCheckout();
    cubit.removeAt(0);

    expect(cubit.state.activeTicket.checkout, isNull);
    expect(cubit.state.items, isEmpty);
    await cubit.close();
  });
}
