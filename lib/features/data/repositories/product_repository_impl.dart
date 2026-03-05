import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/datasources/popular_products_local.dart';
import 'package:leemon_app/features/data/datasources/popular_products_remote.dart';

import 'package:leemon_app/features/data/datasources/product_local_datasource.dart';
import 'package:leemon_app/features/data/datasources/product_remote_datasource.dart';

import 'package:leemon_app/features/domain/repositories/product_repository.dart';

class ProductRepositoryImpl implements ProductRepository {
  final ProductRemoteDataSource remote;
  final ProductLocalDataSource local;

  final PopularProductsRemoteDataSource popularRemote;
  final PopularProductsLocalDataSource popularLocal;

  ProductRepositoryImpl(
    this.remote,
    this.local,
    this.popularRemote,
    this.popularLocal,
  );

  @override
  Future<PaginatedProducts> getProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    if (!forceRefresh) {
      final cached = await local.loadProducts();
      if (cached.isNotEmpty) {
        final total = cached.length;
        onPageProgress?.call(1, 1);
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
      onPageProgress: onPageProgress,
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
  Future<PaginatedProducts> getPopularProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    if (!forceRefresh) {
      final cached = await popularLocal.loadPopularProducts();
      if (cached.isNotEmpty) {
        final total = cached.length;
        onPageProgress?.call(1, 1);
        return PaginatedProducts(
          items: cached,
          currentPage: 1,
          lastPage: 1,
          total: total,
          perPage: total,
        );
      }
    }

    final allRemote = await popularRemote.getAllPopularProducts(
      key: key,
      perPage: perPage,
      onPageProgress: onPageProgress,
    );

    await popularLocal.savePopularProducts(allRemote);

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

  @override
  Future<void> clearPopularProductsCache() => popularLocal.clear();
}
