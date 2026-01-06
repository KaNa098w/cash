// lib/core/models/sale_model.dart
class SaleModel {
  final String localId; // uuid для очереди (в API-листе сюда кладём id продажи)
  final DateTime date;

  final int totalAmount;
  final String paymentMethod;

  final String posId;
  final String storeId;
  final String userId;
  final String? customerId;

  final List<SaleItemModel> items;

  SaleModel({
    required this.localId,
    required this.date,
    required this.totalAmount,
    required this.paymentMethod,
    required this.posId,
    required this.storeId,
    required this.items,
    required this.userId,
    this.customerId,
  });

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

    return SaleModel(
      localId: (json["id"] ?? "").toString(),
      date: _parseApiDate(json["date"]),
      totalAmount: _toIntMoney(json["total_amount"]),
      paymentMethod: (json["payment_method"] ?? "cash").toString(),
      posId: (json["pos_id"] ?? "").toString(),
      customerId: json["customer_id"]?.toString(),

      // в твоём примере бэк это не отдаёт — ставим пустые значения
      storeId: (json["store_id"] ?? "").toString(),
      userId: (json["user_id"] ?? "").toString(),

      items: items,
    );
  }

  // ---------------- CACHE (Hive) ----------------
  Map<String, dynamic> toJson() {
    return {
      "localId": localId,
      "userId": userId,
      "date": date.toIso8601String(),
      "totalAmount": totalAmount,
      "paymentMethod": paymentMethod,
      "posId": posId,
      "storeId": storeId,
      "customerId": customerId,
      "items": items.map((e) => e.toJson()).toList(),
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

    return SaleModel(
      userId: (json["userId"] ?? "").toString(),
      localId: (json["localId"] ?? "").toString(),
      date: DateTime.tryParse((json["date"] ?? "").toString()) ?? DateTime.now(),
      totalAmount: _toInt(json["totalAmount"]),
      paymentMethod: (json["paymentMethod"] ?? "cash").toString(),
      posId: (json["posId"] ?? "").toString(),
      storeId: (json["storeId"] ?? "").toString(),
      customerId: (json["customerId"] as String?),
      items: items,
    );
  }

  // ---------------- helpers ----------------
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _toIntMoney(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();

    final s = v.toString().trim();
    if (s.isEmpty) return 0;

    final normalized = s.replaceAll(',', '.');
    final n = num.tryParse(normalized);
    if (n == null) return 0;

    return n.round();
  }

  static DateTime _parseApiDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return DateTime.now();

    final isoLike = s.contains(' ') ? s.replaceFirst(' ', 'T') : s;
    return DateTime.tryParse(isoLike) ?? DateTime.now();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatDate(DateTime d) {
    return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
  }
}

class SaleItemModel {
  final String productId;
  final int quantity;
  final int price;
  final int totalPrice;

  SaleItemModel({
    required this.productId,
    required this.quantity,
    required this.price,
    required this.totalPrice,
  });

  // API (snake_case) - POST
  Map<String, dynamic> toApiJson() {
    return {
      "product_id": productId,
      "quantity": quantity,
      "price": price,
      "total_price": totalPrice,
    };
  }

  // API (snake_case) - GET
  factory SaleItemModel.fromApiJson(Map<String, dynamic> json) {
    return SaleItemModel(
      productId: (json["product_id"] ?? "").toString(),
      quantity: SaleModel._toInt(json["quantity"]),
      price: SaleModel._toIntMoney(json["price"]),
      totalPrice: SaleModel._toIntMoney(json["total_price"]),
    );
  }

  // CACHE (camelCase)
  Map<String, dynamic> toJson() {
    return {
      "productId": productId,
      "quantity": quantity,
      "price": price,
      "totalPrice": totalPrice,
    };
  }

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      productId: (json["productId"] ?? "").toString(),
      quantity: SaleModel._toInt(json["quantity"]),
      price: SaleModel._toInt(json["price"]),
      totalPrice: SaleModel._toInt(json["totalPrice"]),
    );
  }
}
