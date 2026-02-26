import 'package:hive/hive.dart';
import 'package:leemon_app/core/models/product_response.dart';

class PopularProductsLocalDataSource {
  static const _boxName = 'popular_products_box';
  static const _keyAll = 'all_popular_products';

  Future<List<ProductModel>> loadPopularProducts() async {
    final box = await Hive.openBox(_boxName);

    final raw = box.get(_keyAll);
    if (raw is! List) return [];

    final List<ProductModel> result = [];

    for (final e in raw) {
      if (e is Map) {
        final map = Map<String, dynamic>.from(e as Map);
        result.add(ProductModel.fromJson(map));
      }
    }

    return result;
  }

  Future<void> savePopularProducts(List<ProductModel> products) async {
    final box = await Hive.openBox(_boxName);
    final list = products.map((p) => p.toJson()).toList();
    await box.put(_keyAll, list);
  }

  Future<void> clear() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
    // ignore: avoid_print
    print('Popular-products в локальном хранилище очищены');
  }
}
