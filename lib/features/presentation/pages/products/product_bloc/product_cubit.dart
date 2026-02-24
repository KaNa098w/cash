// product_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/models/product_response.dart'; // ✅ ProductModel
import 'package:pos_desktop_clean/features/domain/repositories/product_repository.dart';
import 'package:pos_desktop_clean/features/presentation/pages/products/product_bloc/product_state.dart';

class ProductsCubit extends Cubit<ProductsState> {
  final ProductRepository repo;

  ProductsCubit(this.repo) : super(const ProductsInitial());

  static const _perPage = 50;

  Future<List<ProductModel>> loadFirstPage({
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
          page: 1,
          hasMore: false,
        ),
      );

      return result.items;
    } catch (e) {
      emit(ProductsError(e.toString()));
      rethrow;
    }
  }

  Future<List<ProductModel>> loadPopularFirstPage({
    required String key,
    bool forceRefresh = false,
  }) async {
    try {
      emit(const ProductsLoading());

      final result = await repo.getPopularProducts(
        key: key,
        page: 1,
        perPage: _perPage,
        forceRefresh: forceRefresh,
      );

      emit(
        ProductsLoaded(
          products: result.items,
          page: 1,
          hasMore: false,
        ),
      );

      return result.items;
    } catch (e) {
      emit(ProductsError(e.toString()));
      rethrow;
    }
  }

  Future<void> loadNextPage() async {
    // no-op
  }
}
