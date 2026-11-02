import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_cubit.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/search/search_bar.dart'
    as pos;
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

class _PosRepository implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

class _ProductsRepository implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'focused search opens keyboard on tap and stays ready after close',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cubit = PosCubit(_PosRepository());
    final products = ProductsCubit(_ProductsRepository());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthTokenProvider(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider.value(value: products),
        ],
        child: const MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topCenter, child: pos.SearchBar())),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(find.byType(OnScreenKeyboardSheet), findsNothing);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byType(OnScreenKeyboardSheet), findsOneWidget);
    await tester.tap(find.text('й'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'й');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.byType(OnScreenKeyboardSheet), findsNothing);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    expect(find.byType(OnScreenKeyboardSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
    await products.close();
  });

  for (final size in [const Size(1024, 768), const Size(500, 600)]) {
    testWidgets('keyboard languages and editing fit $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var entered = false;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
        alignment: Alignment.bottomCenter,
        child: OnScreenKeyboardSheet(
            controllerGetter: () => controller,
            onEnter: () => entered = true,
            onClose: () {}),
      ))));
      await tester.tap(find.text('й'));
      await tester.tap(find.byTooltip('Переключить язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ә'));
      await tester.tap(find.byTooltip('Переключить язык'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('q'));
      expect(controller.text, 'йәq');
      await tester.tap(find.byTooltip('Удалить символ'));
      expect(controller.text, 'йә');
      await tester.tap(find.byTooltip('Ввод'));
      expect(entered, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
