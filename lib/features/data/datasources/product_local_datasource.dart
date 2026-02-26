import 'package:hive/hive.dart';

import 'package:leemon_app/core/models/product_response.dart';

class ProductLocalDataSource {
  static const _boxName = 'products_box';
  static const _keyAll = 'all_products';

  Future<List<ProductModel>> loadProducts() async {
    final box = await Hive.openBox(_boxName);

    final raw = box.get(_keyAll);
    if (raw is! List) {
      return [];
    }

    final List<ProductModel> result = [];

    for (final e in raw) {
      if (e is Map) {
        // приведение типов Map<dynamic, dynamic> -> Map<String, dynamic>
        final map = Map<String, dynamic>.from(e as Map);
        result.add(ProductModel.fromJson(map));
      }
    }

    return result;
  }

  Future<void> saveProducts(List<ProductModel> products) async {
    final box = await Hive.openBox(_boxName);

    final list = products.map((p) => p.toJson()).toList();

    await box.put(_keyAll, list);
  }

  Future<void> clear() async {
    final box = await Hive.openBox(_boxName);
    await box.clear();
    // можно убрать, если не нужен лог
    print('Товары в локальном хранилище очищены');
  }
}
