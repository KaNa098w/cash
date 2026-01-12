// lib/features/pos/data/datasources/sale_remote_datasource.dart
import 'package:dio/dio.dart';
import 'package:pos_desktop_clean/core/models/sale_item_response.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';

class SaleRemoteDataSource {
  SaleRemoteDataSource(this._dio);
  final Dio _dio;

  Future<void> createSale({
    required String key,
    required String deviceId,
    required SaleModel sale,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    await _dio.post(
      '/organizations/pos/$safeKey/sales',
      queryParameters: {'device_id': deviceId},
      data: sale.toApiJson(),
    );
  }

  /// ОДНА страница (Laravel pagination)
  Future<PaginatedSales> getSales({
    required String key,
    int page = 1,
    int perPage = 15,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw Exception('pos key is empty');

    final response = await _dio.get(
      '/organizations/pos/$safeKey/sales',
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'include': 'items', 
      },
    );

    final data = response.data;

    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid sales response: expected Map, got ${data.runtimeType}');
    }

    final rawList = data['data'];
    if (rawList is! List) {
      throw Exception('Invalid sales "data": expected List, got ${rawList.runtimeType}');
    }

    final items = rawList.map((e) {
      if (e is! Map) throw Exception('Sale item is not a Map: ${e.runtimeType}');
      return SaleModel.fromApiJson(Map<String, dynamic>.from(e as Map));
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

  /// ВСЕ страницы (если понадобится)
  Future<List<SaleModel>> getAllSales({
    required String key,
    int perPage = 15,
  }) async {
    var page = 1;
    final all = <SaleModel>[];

    while (true) {
      final res = await getSales(key: key, page: page, perPage: perPage);
      all.addAll(res.items);

      if (res.currentPage >= res.lastPage) break;
      page += 1;
    }

    return all;
  }
}
