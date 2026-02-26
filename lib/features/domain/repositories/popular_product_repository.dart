import 'package:leemon_app/core/models/product_response.dart';

abstract class ProductRepository {
  /// Возвращаем PaginatedProducts, но внутри будем работать уже
  /// со всеми товарами (одна логическая страница).
  Future<PaginatedProducts> getProducts({
    required String key,
    int page = 1,
    int perPage = 50,
    bool forceRefresh = false,
  });

  Future<void> clearProductsCache();
}
