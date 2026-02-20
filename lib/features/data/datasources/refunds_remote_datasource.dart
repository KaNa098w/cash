import 'package:dio/dio.dart';

class RefundsRemoteDatasource {
  final Dio _dio;
  RefundsRemoteDatasource(this._dio);

  Future<String> createRefundV2({
    required String key,
    required String saleId,
    String? customerId,
    required num totalAmount,
    required List<RefundItemPayload> items,
    required String returnAccessKey,
    DateTime? date,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) {
      throw Exception('createRefundV2: pos key is empty');
    }
    if (saleId.trim().isEmpty) {
      throw Exception('createRefundV2: saleId is empty');
    }
    if (items.isEmpty) {
      throw Exception('createRefundV2: items is empty');
    }

    final accessKey = returnAccessKey.trim();
    if (accessKey.isEmpty) {
      throw Exception('createRefundV2: returnAccessKey is empty');
    }

    final payload = <String, dynamic>{
      "date": _formatDateForApi(date ?? DateTime.now()),
      "sale_id": saleId.trim(),
      "total_amount": _toIntMoney(totalAmount),
      if (customerId != null && customerId.trim().isNotEmpty)
        "customer_id": customerId.trim(),
      "items": items.map((e) => e.toJson()).toList(),
    };

    final resp = await _dio.post(
      '/organizations/pos/$safeKey/refunds',
      data: payload,
      queryParameters: {
        'return_access_key': accessKey,
      },
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('createRefundV2: invalid response format (expected Map)');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('createRefundV2: invalid "data" (expected Map)');
    }

    final id = data['id']?.toString().trim();
    if (id == null || id.isEmpty) {
      throw Exception('createRefundV2: missing data.id');
    }

    return id;
  }

  Future<String> updateRefundV2({
    required String key,
    required String refundId,
    required String saleId,
    String? customerId,
    required num totalAmount,
    required List<RefundItemPayload> items,
    DateTime? date,
    required String returnAccessKey,
  }) async {
    final safeKey = key.trim();
    final rid = refundId.trim();

    if (safeKey.isEmpty) {
      throw Exception('updateRefundV2: pos key is empty');
    }
    if (rid.isEmpty) {
      throw Exception('updateRefundV2: refundId is empty');
    }
    if (items.isEmpty) {
      throw Exception('updateRefundV2: items is empty');
    }

    final payload = <String, dynamic>{
      "date": _formatDateForApi(date ?? DateTime.now()),
      "total_amount": _toIntMoney(totalAmount),
      if (customerId != null && customerId.trim().isNotEmpty)
        "customer_id": customerId.trim(),

      // ⚠️ Часто backend запрещает менять sale_id при update.
      // Если у тебя будет ошибка на PUT — просто УДАЛИ эту строку.
      "sale_id": saleId.trim(),

      "items": items.map((e) => e.toJson()).toList(),
    };

    final resp = await _dio.put(
      '/organizations/pos/$safeKey/refunds/$rid', // ✅ ВАЖНО: /refunds/{refundId}
      data: payload,
      queryParameters: {
        'return_access_key': returnAccessKey,
      },
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('updateRefundV2: invalid response format (expected Map)');
    }

    final data = body['data'];
    if (data is Map<String, dynamic>) {
      final id = data['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }

    // если backend не возвращает data.id — просто вернём текущий
    return rid;
  }

  int _toIntMoney(num v) => v.round();

  String _formatDateForApi(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

class RefundItemPayload {
  RefundItemPayload({
    required this.productId,
    required this.saleItemId,
    required this.quantity,
    required this.price,
  });

  final String productId;
  final String saleItemId;
  final int quantity;
  final num price;

  Map<String, dynamic> toJson() => <String, dynamic>{
        "product_id": productId,
        "sale_item_id": saleItemId,
        "quantity": quantity,
        "price": price,
      };
}
