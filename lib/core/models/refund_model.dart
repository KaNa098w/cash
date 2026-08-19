// lib/core/models/refund_model.dart

import 'package:leemon_app/core/models/sale_model.dart'
    show MarkingPartModel, ProductModel;

class RefundModel {
  final String id;
  final String? number;
  final DateTime? date;

  final num? totalAmount;
  final String? paymentMethod;

  final String? reason;
  final String? reasonCode;
  final String? note;

  final String? customerId;
  final String? saleId;

  final String? posId;
  final String? storeId;
  final String? accountId;

  final List<RefundItemModel> items;
  final List<Map<String, dynamic>> payments;

  const RefundModel({
    required this.id,
    this.number,
    this.date,
    this.totalAmount,
    this.paymentMethod,
    this.reason,
    this.reasonCode,
    this.note,
    this.customerId,
    this.saleId,
    this.posId,
    this.storeId,
    this.accountId,
    required this.items,
    this.payments = const <Map<String, dynamic>>[],
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
    this.paymentMethod,
    this.reason,
    this.reasonCode,
    this.note,
    this.customerId,
    this.items = const <RefundItemModel>[],
    this.payments = const <Map<String, dynamic>>[],
  });

  RefundModel copyWith({
    String? id,
    String? number,
    DateTime? date,
    num? totalAmount,
    String? paymentMethod,
    String? reason,
    String? reasonCode,
    String? note,
    String? customerId,
    String? saleId,
    String? posId,
    String? storeId,
    String? accountId,
    List<RefundItemModel>? items,
    List<Map<String, dynamic>>? payments,
  }) {
    return RefundModel(
      id: id ?? this.id,
      number: number ?? this.number,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      reason: reason ?? this.reason,
      reasonCode: reasonCode ?? this.reasonCode,
      note: note ?? this.note,
      customerId: customerId ?? this.customerId,
      saleId: saleId ?? this.saleId,
      posId: posId ?? this.posId,
      storeId: storeId ?? this.storeId,
      accountId: accountId ?? this.accountId,
      items: items ?? this.items,
      payments: payments ?? this.payments,
    );
  }

  factory RefundModel.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List?) ?? const [];
    final paymentsRaw = (json['payments'] as List?) ?? const [];

    return RefundModel(
      id: (json['id'] ?? '').toString(),
      number: (json['number'] ?? '').toString(),
      date: _asDateTime(json['date']),
      totalAmount: _asNum(json['total_amount']),
      paymentMethod: json['payment_method']?.toString(),
      reason: json['reason']?.toString(),
      reasonCode: json['reason_code']?.toString(),
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
      payments: paymentsRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'date': date?.toIso8601String(),
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'reason': reason,
      'reason_code': reasonCode,
      'note': note,
      'customer_id': customerId,
      'sale_id': saleId,
      'pos_id': posId,
      'store_id': storeId,
      'account_id': accountId,
      'items': items.map((e) => e.toJson()).toList(),
      'payments': payments,
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
  final ProductModel? product;
  final List<String> markCodes;
  final List<MarkingPartModel> markingParts;

  const RefundItemModel({
    required this.id,
    required this.refundId,
    required this.saleItemId,
    required this.productId,
    required this.quantity,
    required this.price,
    required this.maxQuantity,
    this.product,
    this.markCodes = const <String>[],
    this.markingParts = const <MarkingPartModel>[],
  });

  RefundItemModel copyWith({
    String? id,
    String? refundId,
    String? saleItemId,
    String? productId,
    int? quantity,
    int? price,
    int? maxQuantity,
    ProductModel? product,
    List<String>? markCodes,
    List<MarkingPartModel>? markingParts,
  }) {
    return RefundItemModel(
      id: id ?? this.id,
      refundId: refundId ?? this.refundId,
      saleItemId: saleItemId ?? this.saleItemId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      product: product ?? this.product,
      markCodes: markCodes ?? this.markCodes,
      markingParts: markingParts ?? this.markingParts,
    );
  }

  factory RefundItemModel.fromJson(Map<String, dynamic> json) {
    final productRaw = json['product'];
    final product = (productRaw is Map)
        ? ProductModel.fromJson(Map<String, dynamic>.from(productRaw))
        : null;

    return RefundItemModel(
      id: (json['id'] ?? '').toString(),
      refundId: (json['refund_id'] ?? '').toString(),
      saleItemId: (json['sale_item_id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asInt(json['quantity']),
      price: _asInt(json['price']),
      maxQuantity: _asInt(json['max_quantity']),
      product: product,
      markCodes: (json['mark_codes'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>[],
      markingParts: (json['marking_parts'] as List?)
              ?.whereType<Map>()
              .map((part) => MarkingPartModel.fromJson(
                    Map<String, dynamic>.from(part),
                  ))
              .toList(growable: false) ??
          const <MarkingPartModel>[],
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
      'product': product?.toJson(),
      if (markCodes.isNotEmpty) 'mark_codes': markCodes,
      if (markingParts.isNotEmpty)
        'marking_parts': markingParts.map((part) => part.toJson()).toList(),
    };
  }

  String get productName {
    final name = (product?.name ?? '').trim();
    if (name.isNotEmpty) return name;
    return productId.trim().isEmpty ? 'Товар' : 'Товар $productId';
  }
}

class RefundPageModel {
  final List<RefundModel> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  bool get hasNextPage => currentPage < lastPage;

  const RefundPageModel({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  factory RefundPageModel.fromApiResponse(Map<String, dynamic> json) {
    final dataRaw = json['data'];
    final list = (dataRaw is List)
        ? dataRaw
            .whereType<Map>()
            .map((e) => RefundModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <RefundModel>[];

    final meta = (json['meta'] is Map)
        ? Map<String, dynamic>.from(json['meta'])
        : const <String, dynamic>{};

    final currentPage = _asInt(meta['current_page']);
    final lastPage = _asInt(meta['last_page']);

    return RefundPageModel(
      items: list,
      currentPage: currentPage <= 0 ? 1 : currentPage,
      lastPage: lastPage <= 0 ? 1 : lastPage,
      total: _asInt(meta['total']),
      perPage: _asInt(meta['per_page']),
    );
  }
}

// ===== helpers =====

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return num.tryParse(v.toString().replaceAll(',', '.'))?.round() ?? 0;
}

num _asNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v;
  return num.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // поддержим "YYYY-MM-DD HH:mm:ss"
  final isoLike = s.contains(' ') ? s.replaceFirst(' ', 'T') : s;
  return DateTime.tryParse(isoLike);
}
