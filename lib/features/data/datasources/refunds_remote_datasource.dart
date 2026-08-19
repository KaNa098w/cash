import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/refund_model.dart';

class RefundsRemoteDatasource {
  final Dio _dio;
  RefundsRemoteDatasource(this._dio);

  Future<RefundPageModel> fetchRefunds({
    required String key,
    int page = 1,
    String? saleId,
    String? customerId,
    DateTime? date,
    num? totalAmount,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) {
      throw Exception('fetchRefunds: pos key is empty');
    }

    final query = <String, dynamic>{
      'page': page,
      if ((saleId ?? '').trim().isNotEmpty) 'filter[sale_id]': saleId!.trim(),
      if ((customerId ?? '').trim().isNotEmpty)
        'filter[customer_id]': customerId!.trim(),
      if (date != null) 'filter[date]': _formatIsoDate(date),
      if (totalAmount != null) 'filter[total_amount]': _moneyValue(totalAmount),
    };

    final resp = await _dio.get(
      '/organizations/pos/$safeKey/refunds',
      queryParameters: query,
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('fetchRefunds: invalid response format (expected Map)');
    }

    return RefundPageModel.fromApiResponse(body);
  }

  Future<List<RefundModel>> fetchAllRefunds({
    required String key,
    DateTime? date,
  }) async {
    final first = await fetchRefunds(key: key, page: 1, date: date);
    final all = <RefundModel>[...first.items];
    var page = first.currentPage;
    final lastPage = first.lastPage <= 0 ? first.currentPage : first.lastPage;

    while (page < lastPage) {
      page++;
      final next = await fetchRefunds(key: key, page: page, date: date);
      all.addAll(next.items);
      if (next.currentPage <= 0 || next.currentPage >= next.lastPage) break;
    }

    return all;
  }

  Future<String> createRefundV2({
    required String key,
    required String saleId,
    String? customerId,
    required num totalAmount,
    required List<RefundItemPayload> items,
    String? returnAccessKey,
    String? userId,
    DateTime? date,
    String? reasonCode,
    String? note,
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

    final accessKey = (returnAccessKey ?? '').trim();
    final directorUserId = (userId ?? '').trim();
    if (accessKey.isEmpty && directorUserId.isEmpty) {
      throw Exception('createRefundV2: return access is missing');
    }

    final payload = <String, dynamic>{
      "date": _formatDateForApi(date ?? DateTime.now()),
      "sale_id": saleId.trim(),
      "total_amount": _moneyValue(totalAmount),
      if (directorUserId.isNotEmpty) "user_id": directorUserId,
      if (customerId != null && customerId.trim().isNotEmpty)
        "customer_id": customerId.trim(),
      if ((reasonCode ?? '').trim().isNotEmpty)
        "reason_code": reasonCode!.trim(),
      if ((note ?? '').trim().isNotEmpty) "note": note!.trim(),
      "items": items.map((e) => e.toJson()).toList(),
    };

    final resp = await _dio.post(
      '/organizations/pos/$safeKey/refunds',
      data: payload,
      options: accessKey.isNotEmpty
          ? Options(headers: {'X-Return-Access-Key': accessKey})
          : null,
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
    String? returnAccessKey,
    String? userId,
    String? reasonCode,
    String? note,
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
    final accessKey = (returnAccessKey ?? '').trim();
    final directorUserId = (userId ?? '').trim();
    if (accessKey.isEmpty && directorUserId.isEmpty) {
      throw Exception('updateRefundV2: return access is missing');
    }

    final payload = <String, dynamic>{
      "date": _formatDateForApi(date ?? DateTime.now()),
      "total_amount": _moneyValue(totalAmount),
      if (directorUserId.isNotEmpty) "user_id": directorUserId,
      if ((reasonCode ?? '').trim().isNotEmpty)
        "reason_code": reasonCode!.trim(),
      if ((note ?? '').trim().isNotEmpty) "note": note!.trim(),
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
      options: accessKey.isNotEmpty
          ? Options(headers: {'X-Return-Access-Key': accessKey})
          : null,
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

  num _moneyValue(num v) => v;

  String _formatDateForApi(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _formatIsoDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
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
