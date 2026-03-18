import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

class ProductLocalDataSource {
  Future<List<ProductModel>> loadProducts() {
    return sl<PosSyncService>().loadProducts();
  }

  Future<void> saveProducts(List<ProductModel> products) async {}

  Future<void> clear() {
    return sl<PosSyncService>().clearAllLocalData();
  }
}
