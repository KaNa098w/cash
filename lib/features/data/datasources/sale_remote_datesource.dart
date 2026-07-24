// lib/features/pos/data/datasources/sale_remote_datasource.dart
import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/sale_item_response.dart';
import 'package:leemon_app/core/models/sale_model.dart';

class SaleRemoteDataSource {
  SaleRemoteDataSource(this._dio);
  final Dio _dio;

  Future<SaleModel?> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    final response = await _dio.post(
      '/organizations/pos/$safeKey/sales',
      queryParameters: {
        'device_id': deviceId,
      },
      data: sale.toApiJson(),
    );

    final body = response.data;
    try {
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return SaleModel.fromApiJson(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {
      // ignore parse errors and fallback to caller-provided sale model
    }
    return null;
  }

  Future<PaginatedSales> getSales({
    required String key,
    int page = 1,
    int perPage = 15,
    String sort = '-date',
    String? customerId,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    final response = await _dio.get(
      '/organizations/pos/$safeKey/sales',
      queryParameters: {
        'page': page,
        'perPage': perPage,
        'include': 'refund.items,payments.account',
        'sort': sort,
        if ((customerId ?? '').trim().isNotEmpty)
          'filter[customer_id]': customerId!.trim(),
      },
    );

    final data = response.data;

    if (data is! Map<String, dynamic>) {
      throw Exception(
          'Invalid sales response: expected Map, got ${data.runtimeType}');
    }

    final rawList = data['data'];
    if (rawList is! List) {
      throw Exception(
          'Invalid sales "data": expected List, got ${rawList.runtimeType}');
    }

    final items = rawList.map((e) {
      if (e is! Map) {
        throw Exception('Sale item is not a Map: ${e.runtimeType}');
      }
      return SaleModel.fromApiJson(Map<String, dynamic>.from(e));
    }).toList();

    final meta = data['meta'] as Map<String, dynamic>? ?? const {};
    final currentPage = (meta['current_page'] as num?)?.toInt() ?? page;
    final lastPage = (meta['last_page'] as num?)?.toInt() ?? currentPage;
    final total = (meta['total'] as num?)?.toInt() ?? items.length;
    final perPageMeta = (meta['per_page'] as num?)?.toInt() ?? perPage;

    return PaginatedSales(
      items: items,
      currentPage: currentPage,
      lastPage: lastPage,
      total: total,
      perPage: perPageMeta,
    );
  }

  Future<SaleModel> fetchSaleById({
    required String key,
    required String saleId,
  }) async {
    final safeKey = key.trim();
    final sid = saleId.trim();

    if (safeKey.isEmpty) throw Exception('fetchSaleById: key is empty');
    if (sid.isEmpty) throw Exception('fetchSaleById: saleId is empty');

    final resp = await _dio.get(
      '/organizations/pos/sales/$sid',
      queryParameters: {
        'include': 'refund.items,payments.account',
      },
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('fetchSaleById: invalid response (expected Map)');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('fetchSaleById: invalid data (expected Map)');
    }

    return SaleModel.fromApiJson(Map<String, dynamic>.from(data));
  }

  Future<SaleModel?> getLastSale({
    required String key,
  }) async {
    final res = await getSales(
      key: key,
      page: 1,
      perPage: 1,
      sort: '-created_at',
    );
    if (res.items.isEmpty) return null;
    return res.items.first;
  }

  Future<List<SaleModel>> getAllSales({
    required String key,
    int perPage = 15,
    String? customerId,
  }) async {
    var page = 1;
    final all = <SaleModel>[];

    while (true) {
      final res = await getSales(
        key: key,
        page: page,
        perPage: perPage,
        customerId: customerId,
      );
      all.addAll(res.items);

      if (res.currentPage >= res.lastPage) break;
      page += 1;
    }

    return all;
  }
}
