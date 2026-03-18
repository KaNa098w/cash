import 'package:dio/dio.dart';

import 'package:leemon_app/core/di/utils/dio_error_utils.dart';

import 'pos_sync_models.dart';

class PosSyncRemoteDataSource {
  PosSyncRemoteDataSource(this._dio);

  final Dio _dio;

  Future<int> fetchServerCursor({
    required String key,
  }) async {
    final response = await _dio.get('/organizations/pos/$key/sync/state');
    final body = _asMap(response.data);
    final data = _nestedMap(body['data']) ?? const <String, dynamic>{};
    return _readInt(
      data['cursor'] ?? body['cursor'] ?? data['next_cursor'] ?? body['next_cursor'],
    );
  }

  Future<Map<String, dynamic>> fetchPosInfo({
    required String key,
  }) async {
    final response = await _dio.get('/organizations/pos/$key');
    final body = _asMap(response.data);
    return _nestedMap(body['data']) ?? body;
  }

  Future<List<Map<String, dynamic>>> fetchAllProducts({
    required String key,
  }) {
    return _fetchPaginatedList('/organizations/pos/$key/products');
  }

  Future<List<Map<String, dynamic>>> fetchAllAccounts({
    required String key,
  }) {
    return _fetchPaginatedList('/organizations/pos/$key/accounts');
  }

  Future<List<Map<String, dynamic>>> fetchAllExpenseTypes({
    required String key,
  }) {
    return _fetchPaginatedList('/organizations/pos/$key/expense-types');
  }

  Future<List<Map<String, dynamic>>> fetchAllCustomers({
    required String key,
  }) {
    return _fetchPaginatedList('/organizations/pos/$key/customers');
  }

  Future<SyncPullBatch> pullChanges({
    required String key,
    required int cursor,
    int limit = 500,
  }) async {
    final response = await _dio.get(
      '/organizations/pos/$key/sync/pull',
      queryParameters: {
        'cursor': cursor,
        'limit': limit,
      },
    );

    final body = _asMap(response.data);
    final data = _nestedMap(body['data']) ?? body;
    final rawItems = _nestedList(data['items']) ??
        _nestedList(data['changes']) ??
        _nestedList(data['events']) ??
        _nestedList(body['items']) ??
        _nestedList(body['changes']) ??
        _nestedList(body['events']) ??
        <dynamic>[];

    final items = rawItems
        .whereType<Object>()
        .map((item) => _parseChange(item))
        .whereType<SyncPullChange>()
        .toList(growable: false);

    final nextCursor = _readInt(
      data['next_cursor'] ?? body['next_cursor'] ?? data['cursor'] ?? body['cursor'] ?? cursor,
    );
    final hasMore = _readBool(
      data['has_more'] ?? body['has_more'] ?? (items.isNotEmpty && nextCursor > cursor),
    );

    return SyncPullBatch(
      items: items,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Future<void> sendOperation({
    required OutboxOperationType type,
    required String key,
    required Map<String, dynamic> payload,
  }) async {
    switch (type) {
      case OutboxOperationType.sale:
        await _dio.post('/organizations/pos/$key/sales', data: payload);
        return;
      case OutboxOperationType.payment:
        await _dio.post('/organizations/pos/$key/payments', data: payload);
        return;
      case OutboxOperationType.refund:
        final query = <String, dynamic>{};
        final returnAccessKey = (payload['return_access_key'] ?? '').toString().trim();
        if (returnAccessKey.isNotEmpty) {
          query['return_access_key'] = returnAccessKey;
        }
        final body = Map<String, dynamic>.from(payload)..remove('return_access_key');
        await _dio.post(
          '/organizations/pos/$key/refunds',
          queryParameters: query.isEmpty ? null : query,
          data: body,
        );
        return;
      case OutboxOperationType.sessionOpen:
        await _dio.post('/organizations/pos/$key/open-session', data: payload);
        return;
      case OutboxOperationType.sessionClose:
        await _dio.put('/organizations/pos/$key/close-session', data: payload);
        return;
    }
  }

  bool isRetryable(Object error) {
    return error is DioException && shouldQueueOnDioError(error);
  }

  String extractErrorCode(Object error) {
    if (error is! DioException) return 'UNKNOWN_ERROR';
    final body = error.response?.data;
    final data = _asMapOrNull(body);
    final nestedError = _nestedMap(data?['error']);
    final code = nestedError?['code'] ??
        data?['error_code'] ??
        data?['code'] ??
        data?['status'] ??
        error.response?.statusCode;
    final normalized = code?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return 'HTTP_${error.response?.statusCode ?? 0}';
    }
    return normalized.toUpperCase();
  }

  String extractErrorMessage(Object error) {
    if (error is! DioException) return error.toString();
    final body = error.response?.data;
    final data = _asMapOrNull(body);
    final nestedError = _nestedMap(data?['error']);
    final message = nestedError?['message'] ??
        data?['message'] ??
        data?['error_message'] ??
        error.message;
    final normalized = message?.toString().trim();
    return (normalized == null || normalized.isEmpty) ? error.toString() : normalized;
  }

  bool isManualErrorCode(String code) {
    switch (code.trim().toUpperCase()) {
      case 'VALIDATION_FAILED':
      case 'INSUFFICIENT_STOCK':
      case 'REFERENCE_NOT_FOUND':
      case 'ACCOUNT_NOT_ALLOWED':
        return true;
      default:
        return false;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPaginatedList(String path) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    const perPage = 500;

    while (true) {
      final response = await _dio.get(
        path,
        queryParameters: {
          'page': page,
          'perPage': perPage,
          'size': perPage,
        },
      );

      final body = _asMap(response.data);
      final data = body['data'];

      List<Map<String, dynamic>> items;
      if (data is List) {
        items = data.map(_asMap).toList(growable: false);
      } else {
        final map = _nestedMap(data) ?? const <String, dynamic>{};
        final list = _nestedList(map['items']) ?? _nestedList(map['data']) ?? const <dynamic>[];
        items = list.map(_asMap).toList(growable: false);
      }

      all.addAll(items);

      final meta = _nestedMap(body['meta']) ?? _nestedMap(body['pagination']) ?? const <String, dynamic>{};
      final currentPage = _readInt(meta['current_page'] ?? meta['page'] ?? page);
      final lastPage = _readInt(meta['last_page'] ?? meta['total_pages'] ?? currentPage);
      if (items.isEmpty || currentPage >= lastPage) {
        break;
      }
      page += 1;
    }

    return all;
  }

  SyncPullChange? _parseChange(Object? raw) {
    final map = _asMapOrNull(raw);
    if (map == null) return null;

    final entity = (map['entity'] ??
            map['resource'] ??
            map['table'] ??
            map['collection'] ??
            map['model'])
        ?.toString();
    final action = (map['action'] ?? map['type'] ?? map['operation'] ?? map['op'])?.toString();
    if (entity == null || entity.trim().isEmpty || action == null || action.trim().isEmpty) {
      return null;
    }

    final payload = _nestedMap(map['payload']) ??
        _nestedMap(map['data']) ??
        _nestedMap(map['record']) ??
        _nestedMap(map['item']);
    final targetId = (map['id'] ?? map['resource_id'] ?? payload?['id'])?.toString();

    return SyncPullChange(
      entity: entity,
      action: action,
      payload: payload,
      targetId: targetId,
      raw: map,
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    final map = _asMapOrNull(value);
    if (map == null) {
      throw Exception('Expected map response, got ${value.runtimeType}');
    }
    return map;
  }

  Map<String, dynamic>? _asMapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic>? _nestedMap(dynamic value) {
    return _asMapOrNull(value);
  }

  List<dynamic>? _nestedList(dynamic value) {
    if (value is List) return value;
    return null;
  }

  int _readInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
}
