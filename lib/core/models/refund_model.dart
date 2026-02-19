// lib/core/models/refund_model.dart

class RefundModel {
  final String id;
  final String? number;
  final DateTime? date;

  final int? totalAmount;

  final String? reason;
  final String? note;

  final String? customerId;
  final String? saleId;

  final String? posId;
  final String? storeId;
  final String? accountId;

  final List<RefundItemModel> items;

  const RefundModel({
    required this.id,
     this.number,
     this.date,
     this.totalAmount,
     this.reason,
     this.note,
     this.customerId,
     this.saleId,
     this.posId,
     this.storeId,
     this.accountId,
     required this.items,
  });

  /// ✅ Удобно для optimistic update, когда у тебя есть только refundId
  /// и контекст из sale (saleId/posId/storeId/accountId).
  const RefundModel.minimal({
    required this.id,
    required this.saleId,
    required this.posId,
    required this.storeId,
    required this.accountId,
    this.number = '',
    this.date,
    this.totalAmount = 0,
    this.reason,
    this.note,
    this.customerId,
    this.items = const <RefundItemModel>[],
  });

  RefundModel copyWith({
    String? id,
    String? number,
    DateTime? date,
    int? totalAmount,
    String? reason,
    String? note,
    String? customerId,
    String? saleId,
    String? posId,
    String? storeId,
    String? accountId,
    List<RefundItemModel>? items,
  }) {
    return RefundModel(
      id: id ?? this.id,
      number: number ?? this.number,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      reason: reason ?? this.reason,
      note: note ?? this.note,
      customerId: customerId ?? this.customerId,
      saleId: saleId ?? this.saleId,
      posId: posId ?? this.posId,
      storeId: storeId ?? this.storeId,
      accountId: accountId ?? this.accountId,
      items: items ?? this.items,
    );
  }

  factory RefundModel.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List?) ?? const [];

    return RefundModel(
      id: (json['id'] ?? '').toString(),
      number: (json['number'] ?? '').toString(),
      date: _asDateTime(json['date']),
      totalAmount: _asInt(json['total_amount']),
      reason: json['reason']?.toString(),
      note: json['note']?.toString(),
      customerId: json['customer_id']?.toString(),
      saleId: (json['sale_id'] ?? '').toString(),
      posId: (json['pos_id'] ?? '').toString(),
      storeId: (json['store_id'] ?? '').toString(),
      accountId: (json['account_id'] ?? '').toString(),
      items: itemsRaw
          .whereType<Map>()
          .map((e) => RefundItemModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'date': date?.toIso8601String(),
      'total_amount': totalAmount,
      'reason': reason,
      'note': note,
      'customer_id': customerId,
      'sale_id': saleId,
      'pos_id': posId,
      'store_id': storeId,
      'account_id': accountId,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}

class RefundItemModel {
  final String id;
  final String refundId;
  final String saleItemId;
  final String productId;

  final int quantity;
  final int price;
  final int maxQuantity;

  const RefundItemModel({
    required this.id,
    required this.refundId,
    required this.saleItemId,
    required this.productId,
    required this.quantity,
    required this.price,
    required this.maxQuantity,
  });

  RefundItemModel copyWith({
    String? id,
    String? refundId,
    String? saleItemId,
    String? productId,
    int? quantity,
    int? price,
    int? maxQuantity,
  }) {
    return RefundItemModel(
      id: id ?? this.id,
      refundId: refundId ?? this.refundId,
      saleItemId: saleItemId ?? this.saleItemId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      maxQuantity: maxQuantity ?? this.maxQuantity,
    );
  }

  factory RefundItemModel.fromJson(Map<String, dynamic> json) {
    return RefundItemModel(
      id: (json['id'] ?? '').toString(),
      refundId: (json['refund_id'] ?? '').toString(),
      saleItemId: (json['sale_item_id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asInt(json['quantity']),
      price: _asInt(json['price']),
      maxQuantity: _asInt(json['max_quantity']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'refund_id': refundId,
      'sale_item_id': saleItemId,
      'product_id': productId,
      'quantity': quantity,
      'price': price,
      'max_quantity': maxQuantity,
    };
  }
}

// ===== helpers =====

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // поддержим "YYYY-MM-DD HH:mm:ss"
  final isoLike = s.contains(' ') ? s.replaceFirst(' ', 'T') : s;
  return DateTime.tryParse(isoLike);
}
