// product_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/product_response.dart'; // ✅ ProductModel
import 'package:leemon_app/features/domain/repositories/product_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/product_bloc/product_state.dart';

class ProductsCubit extends Cubit<ProductsState> {
  final ProductRepository repo;

  ProductsCubit(this.repo) : super(const ProductsInitial());

  static const _perPage = 50;

  Future<List<ProductModel>> loadFirstPage({
    required String key,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    try {
      emit(const ProductsLoading());

      final result = await repo.getProducts(
        key: key,
        page: 1,
        perPage: _perPage,
        forceRefresh: forceRefresh,
        onPageProgress: onPageProgress,
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
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    try {
      final currentProducts =
          state is ProductsLoaded ? (state as ProductsLoaded).products : <ProductModel>[];
      emit(const ProductsLoading());

      final result = await repo.getPopularProducts(
        key: key,
        page: 1,
        perPage: _perPage,
        forceRefresh: forceRefresh,
        onPageProgress: onPageProgress,
      );

      final merged = <ProductModel>[];
      final seen = <String>{};

      String dedupeKey(ProductModel p) {
        final id = (p.id ?? '').trim();
        if (id.isNotEmpty) return 'id:$id';
        final barcode = (p.barcode ?? '').trim();
        final localBarcode = (p.localBarcode ?? '').trim();
        final name = p.name.trim().toLowerCase();
        return 'alt:$barcode|$localBarcode|$name';
      }

      for (final p in [...currentProducts, ...result.items]) {
        final key = dedupeKey(p);
        if (seen.add(key)) merged.add(p);
      }

      emit(
        ProductsLoaded(
          products: merged,
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
