import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';

class MarketplaceOrdersRemoteDataSource {
  MarketplaceOrdersRemoteDataSource(this._dio);

  final Dio _dio;

  Future<MarketplacePosInfo> fetchPosInfo({required String key}) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    final response = await _dio.get('/organizations/pos/$safeKey');
    final body = _checkedMap(response.data, 'fetchPosInfo');
    return MarketplacePosInfo.fromJson(body);
  }

  Future<MarketplaceOrdersPage> listOrders({
    required String key,
    required MarketplaceOrderScope scope,
    int skip = 0,
    int take = 20,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    final response = await _dio.get(
      '/organizations/pos/$safeKey/marketplace/orders',
      queryParameters: {
        'scope': scope.apiValue,
        'skip': skip < 0 ? 0 : skip,
        'take': take.clamp(1, 100),
      },
    );
    return MarketplaceOrdersPage.fromJson(
      _checkedMap(response.data, 'listOrders'),
    );
  }

  Future<MarketplaceOrder> getOrder({
    required String key,
    required String orderId,
  }) async {
    final safeKey = key.trim();
    final safeOrderId = orderId.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');
    if (safeOrderId.isEmpty) throw Exception('order id is empty');

    final response = await _dio.get(
      '/organizations/pos/$safeKey/marketplace/orders/$safeOrderId',
    );
    final body = _checkedMap(response.data, 'getOrder');
    final data = body['data'];
    if (data is Map) {
      return MarketplaceOrder.fromJson(Map<String, dynamic>.from(data));
    }
    return MarketplaceOrder.fromJson(body);
  }

  Future<MarketplaceAcceptResult> acceptOrder({
    required String key,
    required String orderId,
  }) async {
    final safeKey = key.trim();
    final safeOrderId = orderId.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');
    if (safeOrderId.isEmpty) throw Exception('order id is empty');

    final response = await _dio.post(
      '/organizations/pos/$safeKey/marketplace/orders/$safeOrderId/accept',
    );
    return MarketplaceAcceptResult.fromJson(
      _checkedMap(response.data, 'acceptOrder'),
    );
  }

  Future<MarketplaceShipmentResult> shipItem({
    required String key,
    required String orderId,
    required String productId,
    required num quantity,
    required String idempotencyKey,
  }) async {
    final safeKey = key.trim();
    final safeOrderId = orderId.trim();
    final safeProductId = productId.trim();
    final safeIdempotencyKey = idempotencyKey.trim();

    if (safeKey.isEmpty) throw Exception('pos key is empty');
    if (safeOrderId.isEmpty) throw Exception('order id is empty');
    if (safeProductId.isEmpty) throw Exception('product id is empty');
    if (safeIdempotencyKey.isEmpty) {
      throw Exception('idempotency key is empty');
    }
    if (quantity is! int || quantity < 1 || quantity > 100) {
      throw Exception('shipment quantity must be an integer from 1 to 100');
    }

    final response = await _dio.put(
      '/organizations/pos/$safeKey/marketplace/orders/$safeOrderId/items/shipment',
      data: {
        'productId': safeProductId,
        'quantity': quantity,
      },
      options: Options(headers: {'Idempotency-Key': safeIdempotencyKey}),
    );
    return MarketplaceShipmentResult.fromJson(
      _checkedMap(response.data, 'shipItem'),
    );
  }
}

Map<String, dynamic> _asMap(Object? value, String operation) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw Exception('$operation: invalid response format');
}

Map<String, dynamic> _checkedMap(Object? value, String operation) {
  final body = _asMap(value, operation);
  if (body['ok'] == false) {
    final rawStatus = body['status'];
    final status = rawStatus is num
        ? rawStatus.toInt()
        : int.tryParse(rawStatus?.toString() ?? '');
    final result = body['result'];
    final resultMessage = result is Map ? result['message'] : null;
    final message =
        (body['message'] ?? resultMessage ?? 'Операция отклонена').toString();
    throw MarketplaceOrdersApiException(
      operation: operation,
      message: message,
      statusCode: status,
    );
  }
  return body;
}

class MarketplaceOrdersApiException implements Exception {
  const MarketplaceOrdersApiException({
    required this.operation,
    required this.message,
    this.statusCode,
  });

  final String operation;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
