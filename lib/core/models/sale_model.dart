// lib/core/models/sale_model.dart
import 'refund_model.dart';

class SaleModel {
  final String localId; // id продажи
  final String number; // номер чека
  final DateTime date;

  final int totalAmount;
  final String paymentMethod;
  final String? paymentType;
  final int paidAmount;
  final int debtAmount;
  final int documentUnpaidAmount;
  final String? paidPaymentMethod;
  final DateTime? dueDate;
  final String? comment;
  final String? idempotencyKey;

  final String posId;
  final String storeId;

  final String userId;
  final String accountId;
  final String? posSessionId;

  final String? customerId;

  final List<SaleItemModel> items;
  final List<SalePaymentModel> payments;

  /// ✅ Возврат по этому чеку (если был)
  final RefundModel? refund;

  SaleModel({
    required this.localId,
    required this.number,
    required this.date,
    required this.totalAmount,
    required this.paymentMethod,
    this.paymentType,
    this.paidAmount = 0,
    this.debtAmount = 0,
    this.documentUnpaidAmount = 0,
    this.paidPaymentMethod,
    this.dueDate,
    this.comment,
    this.idempotencyKey,
    required this.posId,
    required this.storeId,
    required this.userId,
    required this.accountId,
    this.posSessionId,
    required this.items,
    this.payments = const <SalePaymentModel>[],
    this.customerId,
    this.refund,
  });

  SaleModel copyWith({
    String? localId,
    String? number,
    DateTime? date,
    int? totalAmount,
    String? paymentMethod,
    String? paymentType,
    int? paidAmount,
    int? debtAmount,
    int? documentUnpaidAmount,
    String? paidPaymentMethod,
    DateTime? dueDate,
    String? comment,
    String? idempotencyKey,
    String? posId,
    String? storeId,
    String? userId,
    String? accountId,
    String? posSessionId,
    String? customerId,
    List<SaleItemModel>? items,
    List<SalePaymentModel>? payments,
    RefundModel? refund,
  }) {
    return SaleModel(
      localId: localId ?? this.localId,
      number: number ?? this.number,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentType: paymentType ?? this.paymentType,
      paidAmount: paidAmount ?? this.paidAmount,
      debtAmount: debtAmount ?? this.debtAmount,
      documentUnpaidAmount: documentUnpaidAmount ?? this.documentUnpaidAmount,
      paidPaymentMethod: paidPaymentMethod ?? this.paidPaymentMethod,
      dueDate: dueDate ?? this.dueDate,
      comment: comment ?? this.comment,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      posId: posId ?? this.posId,
      storeId: storeId ?? this.storeId,
      userId: userId ?? this.userId,
      accountId: accountId ?? this.accountId,
      posSessionId: posSessionId ?? this.posSessionId,
      customerId: customerId ?? this.customerId,
      items: items ?? this.items,
      payments: payments ?? this.payments,
      refund: refund ?? this.refund,
    );
  }

  // ---------------- API (POST) ----------------
  Map<String, dynamic> toApiJson() {
    final exactTotal = double.parse(
      items.fold(0.0, (s, e) => s + e.totalPrice).toStringAsFixed(2),
    );
    return {
      "date": _formatDate(date),
      "total_amount": exactTotal,
      "payment_method": paymentMethod,
      if ((paymentType ?? '').trim().isNotEmpty) "payment_type": paymentType,
      if (paidAmount > 0) "paid_amount": paidAmount,
      if (debtAmount > 0) "debt_amount": debtAmount,
      if ((paidPaymentMethod ?? '').trim().isNotEmpty)
        "paid_payment_method": paidPaymentMethod,
      if (dueDate != null) "due_date": _formatIsoDate(dueDate!),
      if ((comment ?? '').trim().isNotEmpty) "comment": comment,
      if ((idempotencyKey ?? '').trim().isNotEmpty)
        "idempotency_key": idempotencyKey,
      "user_id": userId,
      "pos_id": posId,
      if ((posSessionId ?? '').trim().isNotEmpty)
        "pos_session_id": posSessionId,
      if (customerId != null && customerId!.isNotEmpty)
        "customer_id": customerId,
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

    final payments = _parsePayments(json["payments"]);
    final accountId = (json["account_id"] ?? "").toString();
    final userId = (json["user_id"] ?? accountId).toString();

    final refundRaw = json["refund"];
    final refund = (refundRaw is Map)
        ? RefundModel.fromJson(Map<String, dynamic>.from(refundRaw))
        : null;

    final enrichedItems = _applyRefundQty(items, refund);

    return SaleModel(
      localId: (json["id"] ?? "").toString(),
      number: (json["number"] ?? "").toString(),
      date: _parseApiDate(json["date"]),
      totalAmount: _toIntMoney(json["total_amount"]),
      paymentMethod: (json["payment_method"] ?? "cash").toString(),
      paymentType: json["payment_type"]?.toString(),
      paidAmount: _toIntMoney(json["paid_amount"]),
      debtAmount: _toIntMoney(json["debt_amount"]),
      documentUnpaidAmount: _toIntMoney(json["document_unpaid_amount"]),
      paidPaymentMethod: json["paid_payment_method"]?.toString(),
      dueDate: _parseApiDateOrNull(json["due_date"]),
      comment: json["comment"]?.toString(),
      idempotencyKey: json["idempotency_key"]?.toString(),
      posId: (json["pos_id"] ?? "").toString(),
      storeId: (json["store_id"] ?? "").toString(),
      customerId: json["customer_id"]?.toString(),
      accountId: accountId,
      userId: userId,
      posSessionId: json["pos_session_id"]?.toString(),
      items: enrichedItems,
      payments: payments,
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
      "posSessionId": posSessionId,
      "date": date.toIso8601String(),
      "totalAmount": totalAmount,
      "paymentMethod": paymentMethod,
      "paymentType": paymentType,
      "paidAmount": paidAmount,
      "debtAmount": debtAmount,
      "documentUnpaidAmount": documentUnpaidAmount,
      "paidPaymentMethod": paidPaymentMethod,
      "dueDate": dueDate?.toIso8601String(),
      "comment": comment,
      "idempotencyKey": idempotencyKey,
      "posId": posId,
      "storeId": storeId,
      "customerId": customerId,
      "items": items.map((e) => e.toJson()).toList(),
      "payments": payments.map((e) => e.toJson()).toList(),
      "refund": refund?.toJson(),
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

    final payments = _parsePayments(json["payments"]);
    final refundRaw = json["refund"];
    final refund = (refundRaw is Map)
        ? RefundModel.fromJson(Map<String, dynamic>.from(refundRaw))
        : null;

    final enrichedItems = _applyRefundQty(items, refund);

    return SaleModel(
      localId: (json["localId"] ?? "").toString(),
      number: (json["number"] ?? "").toString(),
      userId: (json["userId"] ?? "").toString(),
      accountId: (json["accountId"] ?? "").toString(),
      posSessionId: json["posSessionId"]?.toString(),
      date:
          DateTime.tryParse((json["date"] ?? "").toString()) ?? DateTime.now(),
      totalAmount: _toInt(json["totalAmount"]),
      paymentMethod: (json["paymentMethod"] ?? "cash").toString(),
      paymentType: json["paymentType"]?.toString(),
      paidAmount: _toInt(json["paidAmount"]),
      debtAmount: _toInt(json["debtAmount"]),
      documentUnpaidAmount: _toInt(json["documentUnpaidAmount"]),
      paidPaymentMethod: json["paidPaymentMethod"]?.toString(),
      dueDate: _parseApiDateOrNull(json["dueDate"]),
      comment: json["comment"]?.toString(),
      idempotencyKey: json["idempotencyKey"]?.toString(),
      posId: (json["posId"] ?? "").toString(),
      storeId: (json["storeId"] ?? "").toString(),
      customerId: (json["customerId"] as String?),
      items: enrichedItems,
      payments: payments,
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

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is num) return v.toDouble();

    final s = v.toString().trim();
    if (s.isEmpty) return 0;

    final normalized = s.replaceAll(',', '.');
    final n = num.tryParse(normalized);
    if (n == null) return 0;

    return n.toDouble();
  }

  static int _toIntMoney(dynamic v) => _toInt(v);

  static List<SalePaymentModel> _parsePayments(dynamic raw) {
    if (raw is! List) return const <SalePaymentModel>[];
    return raw
        .whereType<Map>()
        .map((e) => SalePaymentModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  static List<SaleItemModel> _applyRefundQty(
    List<SaleItemModel> items,
    RefundModel? refund,
  ) {
    if (refund == null || refund.items.isEmpty) return items;

    // saleItemId → refunded qty; fallback key: productId
    final byItemId = <String, int>{};
    final byProductId = <String, int>{};
    for (final ri in refund.items) {
      if (ri.saleItemId.trim().isNotEmpty) {
        byItemId[ri.saleItemId] = (byItemId[ri.saleItemId] ?? 0) + ri.quantity;
      }
      if (ri.productId.trim().isNotEmpty) {
        byProductId[ri.productId] =
            (byProductId[ri.productId] ?? 0) + ri.quantity;
      }
    }

    return items.map((item) {
      if (item.refund_quantity != null && item.refund_quantity! > 0) {
        return item;
      }
      final qty = byItemId[item.id] ?? byProductId[item.productId] ?? 0;
      return qty > 0 ? item.copyWith(refund_quantity: qty) : item;
    }).toList(growable: false);
  }

  static DateTime _parseApiDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return DateTime.now();

    // ISO или "YYYY-MM-DD HH:mm:ss"
    final isoLike = s.contains(' ') ? s.replaceFirst(' ', 'T') : s;
    return DateTime.tryParse(isoLike) ?? DateTime.now();
  }

  static DateTime? _parseApiDateOrNull(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    final isoLike = s.contains(' ') ? s.replaceFirst(' ', 'T') : s;
    return DateTime.tryParse(isoLike);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatDate(DateTime d) {
    return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
  }

  static String _formatIsoDate(DateTime d) {
    return '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }
}

class SalePaymentAccountModel {
  const SalePaymentAccountModel({
    required this.id,
    required this.name,
    this.type,
  });

  final String id;
  final String name;
  final String? type;

  factory SalePaymentAccountModel.fromJson(Map<String, dynamic> json) {
    return SalePaymentAccountModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: json['type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
    };
  }
}

class SalePaymentModel {
  const SalePaymentModel({
    required this.accountId,
    required this.amount,
    this.account,
    this.clientPaymentId,
  });

  final String accountId;
  final num amount;
  final SalePaymentAccountModel? account;
  final String? clientPaymentId;

  String get accountName {
    final name = (account?.name ?? '').trim();
    return name.isEmpty ? 'Счет не указан' : name;
  }

  factory SalePaymentModel.fromJson(Map<String, dynamic> json) {
    final accountRaw = json['account'];
    return SalePaymentModel(
      accountId: (json['account_id'] ?? '').toString(),
      amount: _numFromJson(json['amount']),
      account: accountRaw is Map
          ? SalePaymentAccountModel.fromJson(
              Map<String, dynamic>.from(accountRaw),
            )
          : null,
      clientPaymentId: json['client_payment_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      'amount': amount,
      if (clientPaymentId != null) 'client_payment_id': clientPaymentId,
      'account': account?.toJson(),
    };
  }

  static num _numFromJson(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }
}

class SaleItemModel {
  static const universalProductDisplayName = 'Универсальный продукт';

  final String id;
  final String saleId;

  final String productId;
  final ProductModel? product;

  /// ✅ исходное кол-во в продаже
  final double quantity;

  final double price;
  final double totalPrice;

  /// ✅ сколько уже возвращено (может быть null/0)
  // ignore: non_constant_identifier_names
  final int? refund_quantity;

  SaleItemModel({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.price,
    required this.totalPrice,
    this.product,
    // ignore: non_constant_identifier_names
    this.refund_quantity,
  });

  bool get isUniversalProduct {
    if (product?.isUniversal == true) return true;
    final normalized = (product?.name ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalized == 'универсальный продукт' ||
        normalized == 'универсальный товар pos' ||
        normalized == 'универсальный товар';
  }

  String get displayProductName {
    if (isUniversalProduct) return universalProductDisplayName;
    final name = (product?.name ?? '').trim();
    if (name.isNotEmpty) return name;
    return 'Товар $productId';
  }

  SaleItemModel copyWith({
    String? id,
    String? saleId,
    String? productId,
    ProductModel? product,
    double? quantity,
    double? price,
    double? totalPrice,
    // ignore: non_constant_identifier_names
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
      quantity: SaleModel._toDouble(json["quantity"]),
      price: SaleModel._toDouble(json["price"]),
      totalPrice: SaleModel._toDouble(json["total_price"]),
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
      quantity: SaleModel._toDouble(json["quantity"]),
      price: SaleModel._toDouble(json["price"]),
      totalPrice: SaleModel._toDouble(json["totalPrice"]),
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
  final bool isUniversal;

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
    this.isUniversal = false,
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
      isUniversal: json['is_universal'] == true ||
          json['is_universal'] == 1 ||
          json['is_universal']?.toString().trim() == '1',
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
      'is_universal': isUniversal ? 1 : 0,
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
