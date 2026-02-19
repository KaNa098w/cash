import 'package:pos_desktop_clean/core/models/product_response.dart';
import 'package:pos_desktop_clean/features/data/datasources/product_local_datasource.dart';
import 'package:pos_desktop_clean/features/data/datasources/product_remote_datasource.dart';
import 'package:pos_desktop_clean/features/domain/repositories/product_repository.dart';

class ProductRepositoryImpl implements ProductRepository {
  final ProductRemoteDataSource remote;
  final ProductLocalDataSource local;

  ProductRepositoryImpl(this.remote, this.local);

  @override
  Future<PaginatedProducts> getProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await local.loadProducts();
      if (cached.isNotEmpty) {
        final total = cached.length;
        return PaginatedProducts(
          items: cached,
          currentPage: 1,
          lastPage: 1,
          total: total,
          perPage: total,
        );
      }
    }

    final allRemote = await remote.getAllProducts(
      key: key,
      perPage: perPage,
    );

    await local.saveProducts(allRemote);

    final total = allRemote.length;

    return PaginatedProducts(
      items: allRemote,
      currentPage: 1,
      lastPage: 1,
      total: total,
      perPage: total,
    );
  }

  @override
  Future<void> clearProductsCache() => local.clear();
}
