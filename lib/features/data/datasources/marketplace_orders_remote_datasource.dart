import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';

class MarketplaceOrdersRemoteDataSource {
  MarketplaceOrdersRemoteDataSource(this._dio);

  final Dio _dio;

  Future<MarketplacePosInfo> fetchPosInfo({required String key}) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    final path = '/organizations/pos/$safeKey';
    _logMarketplaceRequest('GET', path);
    final response = await _dio.get(path);
    _logMarketplaceResponse('GET', path, response);
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

    final path = '/organizations/pos/$safeKey/marketplace/orders';
    final query = <String, dynamic>{
      'scope': scope.apiValue,
      'skip': skip < 0 ? 0 : skip,
      'take': take.clamp(1, 100),
    };
    _logMarketplaceRequest('GET', path, query: query);
    final response = await _dio.get(
      path,
      queryParameters: query,
    );
    _logMarketplaceResponse('GET', path, response);
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

    final path = '/organizations/pos/$safeKey/marketplace/orders/$safeOrderId';
    _logMarketplaceRequest('GET', path);
    final response = await _dio.get(path);
    _logMarketplaceResponse('GET', path, response);
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

    final path =
        '/organizations/pos/$safeKey/marketplace/orders/$safeOrderId/accept';
    _logMarketplaceRequest('POST', path, body: const <String, dynamic>{});
    final response = await _dio.post(path);
    _logMarketplaceResponse('POST', path, response);
    return MarketplaceAcceptResult.fromJson(
      _checkedMap(response.data, 'acceptOrder'),
    );
  }

  Future<MarketplaceShipmentResult> shipOrder({
    required String key,
    required String orderId,
    required String idempotencyKey,
  }) async {
    final safeKey = key.trim();
    final safeOrderId = orderId.trim();
    final safeIdempotencyKey = idempotencyKey.trim();

    if (safeKey.isEmpty) throw Exception('pos key is empty');
    if (safeOrderId.isEmpty) throw Exception('order id is empty');
    if (safeIdempotencyKey.isEmpty) {
      throw Exception('idempotency key is empty');
    }

    final path =
        '/organizations/pos/$safeKey/marketplace/orders/$safeOrderId/items/shipment';
    final body = <String, dynamic>{};
    _logMarketplaceRequest('PUT', path, body: body);
    final response = await _dio.put(
      path,
      data: body,
      options: Options(headers: {'Idempotency-Key': safeIdempotencyKey}),
    );
    _logMarketplaceResponse('PUT', path, response);
    final responseBody = _checkedMap(response.data, 'shipOrder');
    final result = MarketplaceShipmentResult.fromJson(responseBody);
    if (!result.ok) {
      throw MarketplaceOrdersApiException(
        operation: 'shipOrder',
        message: (responseBody['message'] ?? 'Не удалось отгрузить заказ')
            .toString(),
        statusCode: result.status,
      );
    }
    return result;
  }
}

void _logMarketplaceRequest(
  String method,
  String path, {
  Map<String, dynamic>? query,
  Object? body,
}) {
  _printMarketplaceLog(
    '[MARKETPLACE REQUEST]\n'
    'method: $method\n'
    'url: $path\n'
    'query: ${_prettyJson(query ?? const <String, dynamic>{})}\n'
    'body: ${body == null ? '<empty>' : _prettyJson(body)}',
  );
}

void _logMarketplaceResponse(
  String method,
  String path,
  Response<dynamic> response,
) {
  _printMarketplaceLog(
    '[MARKETPLACE RESPONSE]\n'
    'method: $method\n'
    'url: $path\n'
    'status: ${response.statusCode}\n'
    'body: ${_prettyJson(response.data)}',
  );
}

String _prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

void _printMarketplaceLog(String value) {
  const chunkSize = 800;
  for (var offset = 0; offset < value.length; offset += chunkSize) {
    final end =
        (offset + chunkSize < value.length) ? offset + chunkSize : value.length;
    debugPrintSynchronously(value.substring(offset, end));
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
