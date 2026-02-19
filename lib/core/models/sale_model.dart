// lib/core/models/sale_model.dart

import 'package:intl/intl.dart';
import 'refund_model.dart';

class SaleModel {
  final String localId; // id продажи
  final String number; // номер чека
  final DateTime date;

  final int totalAmount;
  final String paymentMethod;

  final String posId;
  final String storeId;

  final String userId;
  final String accountId;

  final String? customerId;

  final List<SaleItemModel> items;

  /// ✅ Возврат по этому чеку (если был)
  final RefundModel? refund;

  SaleModel({
    required this.localId,
    required this.number,
    required this.date,
    required this.totalAmount,
    required this.paymentMethod,
    required this.posId,
    required this.storeId,
    required this.userId,
    required this.accountId,
    required this.items,
    this.customerId,
    this.refund,
  });

  SaleModel copyWith({
    String? localId,
    String? number,
    DateTime? date,
    int? totalAmount,
    String? paymentMethod,
    String? posId,
    String? storeId,
    String? userId,
    String? accountId,
    String? customerId,
    List<SaleItemModel>? items,
    RefundModel? refund,
  }) {
    return SaleModel(
      localId: localId ?? this.localId,
      number: number ?? this.number,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      posId: posId ?? this.posId,
      storeId: storeId ?? this.storeId,
      userId: userId ?? this.userId,
      accountId: accountId ?? this.accountId,
      customerId: customerId ?? this.customerId,
      items: items ?? this.items,
      refund: refund ?? this.refund,
    );
  }

  // ---------------- API (POST) ----------------
  Map<String, dynamic> toApiJson() {
    return {
      "date": _formatDate(date),
      "total_amount": totalAmount,
      "payment_method": paymentMethod,
      "user_id": userId,
      "pos_id": posId,
      if (customerId != null && customerId!.isNotEmpty) "customer_id": customerId,
      "store_id": storeId,
      "items": items.map((e) => e.toApiJson()).toList(),
    };
  }

  // ---------------- API (GET) ----------------
  factory SaleModel.fromApiJson(Map<String, dynamic> json) {
    final itemsRaw = json["items"];
    final items = (itemsRaw is List)
        ? itemsRaw
            .whereType<Map>()
            .map((e) => SaleItemModel.fromApiJson(Map<String, dynamic>.from(e)))
            .toList()
        : <SaleItemModel>[];

    final accountId = (json["account_id"] ?? "").toString();
    final userId = (json["user_id"] ?? accountId).toString();

    final refundRaw = json["refund"];
    final refund = (refundRaw is Map)
        ? RefundModel.fromJson(Map<String, dynamic>.from(refundRaw))
        : null;

    return SaleModel(
      localId: (json["id"] ?? "").toString(),
      number: (json["number"] ?? "").toString(),
      date: _parseApiDate(json["date"]),
      totalAmount: _toIntMoney(json["total_amount"]),
      paymentMethod: (json["payment_method"] ?? "cash").toString(),
      posId: (json["pos_id"] ?? "").toString(),
      storeId: (json["store_id"] ?? "").toString(),
      customerId: json["customer_id"]?.toString(),
      accountId: accountId,
      userId: userId,
      items: items,
      refund: refund,
    );
  }

  // ---------------- CACHE (Hive) ----------------
  Map<String, dynamic> toJson() {
    return {
      "localId": localId,
      "number": number,
      "userId": userId,
      "accountId": accountId,
      "date": date.toIso8601String(),
      "totalAmount": totalAmount,
      "paymentMethod": paymentMethod,
      "posId": posId,
      "storeId": storeId,
      "customerId": customerId,
      "items": items.map((e) => e.toJson()).toList(),
      "refund": refund?.toJson(), // ✅ теперь работает
    };
  }

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json["items"];
    final items = (itemsRaw is List)
        ? itemsRaw
            .whereType<Map>()
            .map((e) => SaleItemModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <SaleItemModel>[];

    final refundRaw = json["refund"];
    final refund = (refundRaw is Map)
        ? RefundModel.fromJson(Map<String, dynamic>.from(refundRaw))
        : null;

    return SaleModel(
      localId: (json["localId"] ?? "").toString(),
      number: (json["number"] ?? "").toString(),
      userId: (json["userId"] ?? "").toString(),
      accountId: (json["accountId"] ?? "").toString(),
      date: DateTime.tryParse((json["date"] ?? "").toString()) ?? DateTime.now(),
      totalAmount: _toInt(json["totalAmount"]),
      paymentMethod: (json["paymentMethod"] ?? "cash").toString(),
      posId: (json["posId"] ?? "").toString(),
      storeId: (json["storeId"] ?? "").toString(),
      customerId: (json["customerId"] as String?),
      items: items,
      refund: refund,
    );
  }

  // ---------------- helpers ----------------

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();

    final s = v.toString().trim();
    if (s.isEmpty) return 0;

    final normalized = s.replaceAll(',', '.');
    final n = num.tryParse(normalized);
    if (n == null) return 0;

    return n.round();
  }

  static int _toIntMoney(dynamic v) => _toInt(v);

  static DateTime _parseApiDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return DateTime.now();

    // ISO или "YYYY-MM-DD HH:mm:ss"
    final isoLike = s.contains(' ') ? s.replaceFirst(' ', 'T') : s;
    return DateTime.tryParse(isoLike) ?? DateTime.now();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatDate(DateTime d) {
    return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
  }
}

class SaleItemModel {
  final String id;
  final String saleId;

  final String productId;
  final ProductModel? product;

  /// ✅ исходное кол-во в продаже
  final int quantity;

  final int price;
  final int totalPrice;

  /// ✅ сколько уже возвращено (может быть null/0)
  final int? refund_quantity;

  SaleItemModel({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.price,
    required this.totalPrice,
    this.product,
    this.refund_quantity,
  });

  SaleItemModel copyWith({
    String? id,
    String? saleId,
    String? productId,
    ProductModel? product,
    int? quantity,
    int? price,
    int? totalPrice,
    int? refund_quantity,
  }) {
    return SaleItemModel(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      totalPrice: totalPrice ?? this.totalPrice,
      refund_quantity: refund_quantity ?? this.refund_quantity,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      "product_id": productId,
      "quantity": quantity,
      "price": price,
      "total_price": totalPrice,
      "refund_quantity": refund_quantity,
    };
  }

  factory SaleItemModel.fromApiJson(Map<String, dynamic> json) {
    final productRaw = json["product"];
    final product = (productRaw is Map)
        ? ProductModel.fromJson(Map<String, dynamic>.from(productRaw))
        : null;

    return SaleItemModel(
      id: (json["id"] ?? "").toString(),
      saleId: (json["sale_id"] ?? "").toString(),
      productId: (json["product_id"] ?? "").toString(),
      product: product,
      quantity: SaleModel._toInt(json["quantity"]),
      price: SaleModel._toIntMoney(json["price"]),
      totalPrice: SaleModel._toIntMoney(json["total_price"]),
      refund_quantity: json["refund_quantity"] == null
          ? null
          : SaleModel._toInt(json["refund_quantity"]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "saleId": saleId,
      "productId": productId,
      "product": product?.toJson(),
      "quantity": quantity,
      "price": price,
      "totalPrice": totalPrice,
      "refund_quantity": refund_quantity,
    };
  }

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    final productRaw = json["product"];
    final product = (productRaw is Map)
        ? ProductModel.fromJson(Map<String, dynamic>.from(productRaw))
        : null;

    return SaleItemModel(
      id: (json["id"] ?? "").toString(),
      saleId: (json["saleId"] ?? "").toString(),
      productId: (json["productId"] ?? "").toString(),
      product: product,
      quantity: SaleModel._toInt(json["quantity"]),
      price: SaleModel._toInt(json["price"]),
      totalPrice: SaleModel._toInt(json["totalPrice"]),
      refund_quantity: json["refund_quantity"] == null
          ? null
          : SaleModel._toInt(json["refund_quantity"]),
    );
  }
}

class ProductModel {
  final String? id;
  final String name;
  final String measurementUnit;

  final String? barcode;
  final String? localBarcode;

  final double arrivalCost;
  final double sellingPrice;
  final double wholesalePrice;

  final String? categoryId;
  final String? globalProductId;

  ProductModel({
    required this.id,
    required this.name,
    required this.measurementUnit,
    required this.arrivalCost,
    required this.sellingPrice,
    required this.wholesalePrice,
    this.barcode,
    this.localBarcode,
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
    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;
    return double.tryParse(s.replaceAll(',', '.')) ?? 0.0;
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
      'category_id': categoryId,
      'global_product_id': globalProductId,
    };
  }
}

class SalePageModel {
  final List<SaleModel> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  bool get hasNextPage => currentPage < lastPage;

  SalePageModel({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  factory SalePageModel.fromApiResponse(Map<String, dynamic> json) {
    final dataRaw = json["data"];
    final list = (dataRaw is List)
        ? dataRaw
            .whereType<Map>()
            .map((e) => SaleModel.fromApiJson(Map<String, dynamic>.from(e)))
            .toList()
        : <SaleModel>[];

    final meta = (json["meta"] is Map)
        ? Map<String, dynamic>.from(json["meta"])
        : const <String, dynamic>{};

    return SalePageModel(
      items: list,
      currentPage: SaleModel._toInt(meta["current_page"]),
      lastPage: SaleModel._toInt(meta["last_page"]),
      total: SaleModel._toInt(meta["total"]),
      perPage: SaleModel._toInt(meta["per_page"]),
    );
  }
}
