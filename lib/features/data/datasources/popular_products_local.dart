import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

class PopularProductsLocalDataSource {
  Future<List<ProductModel>> loadPopularProducts() {
    return sl<PosSyncService>().loadFavoriteProducts();
  }

  Future<void> savePopularProducts(List<ProductModel> products) async {}

  Future<void> clear() async {}
}
