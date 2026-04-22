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
  final bool isUniversal;

  /// Сколько штук в 1 единице измерения.
  /// null — если measurement_unit == штуки (конвертация не нужна).
  final double? conversionValue;

  // ── Скидки (из нового API) ──────────────────────────────────────────
  /// "automatic" | "fixed" | "forbidden" | null
  final String? discountType;
  final double discountPercent;
  final double discountAmount;

  /// Финальная цена за единицу с учётом скидки.
  /// Именно её POS ставит в строку продажи.
  final double priceAfterDiscount;

  /// Цена для корзины: priceAfterDiscount если > 0, иначе sellingPrice.
  double get effectivePrice =>
      priceAfterDiscount > 0 ? priceAfterDiscount : sellingPrice;

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
    this.isUniversal = false,
    this.conversionValue,
    this.discountType,
    this.discountPercent = 0.0,
    this.discountAmount = 0.0,
    this.priceAfterDiscount = 0.0,
  });

  static String normalizeMeasurementUnit(String measurementUnit) {
    return measurementUnit.toLowerCase().replaceAll('.', '').trim();
  }

  static bool isPiecesMeasurementUnit(String measurementUnit) {
    const piecesAliases = {
      'pieces',
      'piece',
      'pcs',
      'pc',
      'шт',
      'штука',
      'штук'
    };
    return piecesAliases.contains(normalizeMeasurementUnit(measurementUnit));
  }

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

  static double? _asConversionValue(dynamic v, String measurementUnit) {
    if (isPiecesMeasurementUnit(measurementUnit)) return null;
    if (v == null) return null;
    if (v is num) return v > 0 ? v.toDouble() : null;
    final n = double.tryParse(v.toString().replaceAll(',', '.'));
    return (n != null && n > 0) ? n : null;
  }

  static double _asQuantity(
    dynamic v, {
    required String measurementUnit,
    required double? conversionValue,
  }) {
    if (v == null) return 0.0;
    final rawQuantity = switch (v) {
      num() => v.toDouble(),
      _ => (() {
          final s = v.toString().trim();
          if (s.isEmpty) return 0.0;
          final n = num.tryParse(s.replaceAll(',', '.'));
          return n?.toDouble() ?? 0.0;
        })(),
    };

    if (rawQuantity <= 0) return 0.0;
    if (isPiecesMeasurementUnit(measurementUnit)) return rawQuantity;

    final cv = conversionValue;
    if (cv == null || cv <= 0) return rawQuantity;

    // Сервер хранит остаток в штуках, а POS работает в единице товара:
    // 36 шт / 12 шт. в упаковке = 3 уп.
    return rawQuantity / cv;
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final measurementUnit = (json['measurement_unit'] ?? '').toString();
    final conversionValue =
        _asConversionValue(json['conversion_value'], measurementUnit);

    return ProductModel(
      id: (json['id'] != null) ? _asString(json['id']) : null,
      name: (json['name'] ?? '').toString(),
      measurementUnit: measurementUnit,
      barcode: _asString(json['barcode']),
      localBarcode: _asString(json['local_barcode']),
      arrivalCost: _asDouble(json['arrival_cost']),
      sellingPrice: _asDouble(json['selling_price']),
      wholesalePrice: _asDouble(json['wholesale_price']),
      quantity: _asQuantity(
        json['quantity'],
        measurementUnit: measurementUnit,
        conversionValue: conversionValue,
      ),
      isFavorite: json['is_favorite'] == true ||
          json['is_favorite'] == 1 ||
          json['is_favorite']?.toString().trim() == '1',
      sku: _asString(json['sku']),
      coverUrl: _asString(json['cover_url']),
      categoryId: _asString(json['category_id']),
      globalProductId: _asString(json['global_product_id']),
      isUniversal: json['is_universal'] == true ||
          json['is_universal'] == 1 ||
          json['is_universal']?.toString().trim() == '1',
      conversionValue: conversionValue,
      discountType: _asString(json['discount_type']),
      discountPercent: _asDouble(json['discount_percent']),
      discountAmount: _asDouble(json['discount_amount']),
      priceAfterDiscount: _asDouble(json['price_after_discount']),
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
      'is_universal': isUniversal ? 1 : 0,
      'conversion_value': conversionValue,
      'discount_type': discountType,
      'discount_percent': discountPercent,
      'discount_amount': discountAmount,
      'price_after_discount': priceAfterDiscount,
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
