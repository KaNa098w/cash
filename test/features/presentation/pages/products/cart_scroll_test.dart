import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/cart_list/cart_list.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

class _Repository implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('basket scrolls by dragging a product with $kind',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cubit = PosCubit(_Repository());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 30; i++) {
        cubit.add(Product(id: '$i', name: 'Product $i', price: 100));
      }
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: CartList()),
        ),
      ));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final before = scrollable.position.pixels;
      final product = find.textContaining('Product 3 (');
      expect(product, findsOneWidget);
      await tester.drag(product, const Offset(0, -250), kind: kind);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(before + 100));
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(cubit.close);
    });
  }
}
