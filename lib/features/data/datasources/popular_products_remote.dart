import 'package:dio/dio.dart';
import 'package:pos_desktop_clean/core/models/product_response.dart';

class PopularProductsRemoteDataSource {
  final Dio _dio;

  PopularProductsRemoteDataSource(this._dio);

  Future<PaginatedProducts> getPopularProducts({
    int page = 1,
    int perPage = 50,
    required String key,
  }) {
    return _getPopularProductsPage(page: page, perPage: perPage, key: key);
  }

  Future<PaginatedProducts> _getPopularProductsPage({
    required int page,
    required int perPage,
    required String key,
  }) async {
    try {
      final response = await _dio.get(
        '/organizations/pos/$key/popular-products',
        queryParameters: {
          'page': page,
          'per_page': perPage,
        },
      );

      final data = response.data;

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid popular-products response format: expected Map, got ${data.runtimeType}',
        );
      }

      final rawList = data['data'];
      if (rawList is! List) {
        throw Exception(
          'Invalid popular-products "data" format: expected List, got ${rawList.runtimeType}',
        );
      }

      final items = rawList.map((e) {
        if (e is! Map) {
          throw Exception(
              'Popular product item is not a Map: ${e.runtimeType}');
        }
        return ProductModel.fromJson(Map<String, dynamic>.from(e as Map));
      }).toList();

      final meta = data['meta'] as Map<String, dynamic>? ?? const {};

      final currentPage = (meta['current_page'] as num?)?.toInt() ?? page;
      final lastPage = (meta['last_page'] as num?)?.toInt() ?? currentPage;
      final total = (meta['total'] as num?)?.toInt() ?? items.length;
      final perPageMeta = (meta['per_page'] as num?)?.toInt() ?? perPage;

      return PaginatedProducts(
        items: items,
        currentPage: currentPage,
        lastPage: lastPage,
        total: total,
        perPage: perPageMeta,
      );
    } on DioException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  /// Если нужно вытащить все "популярные" для синка в Hive
  Future<List<ProductModel>> getAllPopularProducts({
    required String key,
    int perPage = 50,
  }) async {
    var page = 1;
    final all = <ProductModel>[];

    while (true) {
      final pageResult = await _getPopularProductsPage(
        page: page,
        perPage: perPage,
        key: key,
      );

      all.addAll(pageResult.items);

      if (pageResult.currentPage >= pageResult.lastPage) break;
      page += 1;
    }

    return all;
  }
}
