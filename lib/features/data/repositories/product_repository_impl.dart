import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/product_repository.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(
    Object _,
    Object __,
    Object ___,
    Object ____,
    this._syncService,
  );

  final PosSyncService _syncService;

  @override
  Future<PaginatedProducts> getProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    final items = await _syncService.loadProducts();
    onPageProgress?.call(1, 1);
    return PaginatedProducts(
      items: items,
      currentPage: 1,
      lastPage: 1,
      total: items.length,
      perPage: items.length,
    );
  }

  @override
  Future<PaginatedProducts> getPopularProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    final items = await _syncService.loadFavoriteProducts();
    onPageProgress?.call(1, 1);
    return PaginatedProducts(
      items: items,
      currentPage: 1,
      lastPage: 1,
      total: items.length,
      perPage: items.length,
    );
  }

  @override
  Future<void> clearProductsCache() => _syncService.clearAllLocalData();

  @override
  Future<void> clearPopularProductsCache() async {}
}
