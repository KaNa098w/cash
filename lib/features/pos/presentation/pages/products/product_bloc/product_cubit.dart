// product_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/features/pos/domain/repositories/product_repository.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/products/product_bloc/product_state.dart';

class ProductsCubit extends Cubit<ProductsState> {
  final ProductRepository repo;

  ProductsCubit(this.repo) : super(const ProductsInitial());

  static const _perPage = 50;

  Future<void> loadFirstPage({
    required String key,
    bool forceRefresh = false,
  }) async {
    try {
      emit(const ProductsLoading());

      final result = await repo.getProducts(
        key: key,
        page: 1,
        perPage: _perPage,
        forceRefresh: forceRefresh,
      );

      emit(
        ProductsLoaded(
          products: result.items,
          page: 1, // логическая страница
          hasMore: false, // так как мы всегда грузим всё сразу
        ),
      );
    } catch (e) {
      emit(ProductsError(e.toString()));
    }
  }

  /// Пагинация больше не нужна — оставляем метод, но он ничего не делает.
  Future<void> loadNextPage() async {
    // intentionally no-op
    // потому что репозиторий возвращает одну логическую страницу со всеми товарами
  }
}
