class ProductModel {
  final String? id;
  final String name;
  final String measurementUnit;

  // лучше хранить как String? (штрихкоды бывают длинные)
  final String? barcode;
  final String? localBarcode;

  final double arrivalCost;
  final double sellingPrice;
  final double wholesalePrice;
  final double quantity;
  final bool isFavorite;
  final String? sku;
  final String? coverUrl;

  final String? categoryId;
  final String? globalProductId;

  ProductModel({
    required this.id,
    required this.name,
    required this.measurementUnit,
    required this.arrivalCost,
    required this.sellingPrice,
    required this.wholesalePrice,
    this.quantity = 0.0,
    this.isFavorite = false,
    this.barcode,
    this.localBarcode,
    this.sku,
    this.coverUrl,
    this.categoryId,
    this.globalProductId,
  });

  static String? _asString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static double _asQuantity(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;
    final n = num.tryParse(s.replaceAll(',', '.'));
    return n?.toDouble() ?? 0.0;
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: (json['id'] != null) ? _asString(json['id']) : null,
      name: (json['name'] ?? '').toString(),
      measurementUnit: (json['measurement_unit'] ?? '').toString(),
      barcode: _asString(json['barcode']),
      localBarcode: _asString(json['local_barcode']),
      arrivalCost: _asDouble(json['arrival_cost']),
      sellingPrice: _asDouble(json['selling_price']),
      wholesalePrice: _asDouble(json['wholesale_price']),
      quantity: _asQuantity(json['quantity']),
      isFavorite: json['is_favorite'] == true ||
          json['is_favorite'] == 1 ||
          json['is_favorite']?.toString().trim() == '1',
      sku: _asString(json['sku']),
      coverUrl: _asString(json['cover_url']),
      categoryId: _asString(json['category_id']),
      globalProductId: _asString(json['global_product_id']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'measurement_unit': measurementUnit,
      'barcode': barcode,
      'local_barcode': localBarcode,
      'arrival_cost': arrivalCost,
      'selling_price': sellingPrice,
      'wholesale_price': wholesalePrice,
      'quantity': quantity,
      'is_favorite': isFavorite ? 1 : 0,
      'sku': sku,
      'cover_url': coverUrl,
      'category_id': categoryId,
      'global_product_id': globalProductId,
    };
  }
}

/// Внутри репозитория мы будем возвращать
/// одну «логическую» страницу, где items = все продукты.
class PaginatedProducts {
  final List<ProductModel> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  bool get hasNextPage => currentPage < lastPage;

  PaginatedProducts({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });
}
