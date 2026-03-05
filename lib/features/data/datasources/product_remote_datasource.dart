import 'package:dio/dio.dart';
import 'package:leemon_app/core/models/product_response.dart';

class ProductRemoteDataSource {
  final Dio _dio;

  ProductRemoteDataSource(this._dio);

  Future<PaginatedProducts> getProducts({
    int page = 1,
    int perPage = 50,
    required String key,
  }) {
    return _getProductsPage(page: page, perPage: perPage, key: key);
  }

  /// Внутренний метод, получающий одну страницу.
  Future<PaginatedProducts> _getProductsPage({
    required int page,
    required int perPage,
    required String key,
  }) async {
    try {
      final response = await _dio.get(
        '/organizations/pos/$key/products',
        queryParameters: {
          'page': page,
          'per_page': perPage, // если параметр другой — поменяй
        },
      );

      final data = response.data;

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid products response format: expected Map, got ${data.runtimeType}',
        );
      }

      final rawList = data['data'];
      if (rawList is! List) {
        throw Exception(
          'Invalid products "data" format: expected List, got ${rawList.runtimeType}',
        );
      }

      final items = rawList.map((e) {
        if (e is! Map) {
          throw Exception('Product item is not a Map: ${e.runtimeType}');
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

  /// Получить ВСЕ продукты со всех страниц.
  /// Используем для синка в Hive.
  Future<List<ProductModel>> getAllProducts({
    required String key,
    int perPage = 50,
    void Function(int currentPage, int lastPage)? onPageProgress,
  }) async {
    var page = 1;
    final all = <ProductModel>[];

    while (true) {
      final pageResult = await _getProductsPage(
        page: page,
        perPage: perPage,
        key: key,
      );

      all.addAll(pageResult.items);
      onPageProgress?.call(pageResult.currentPage, pageResult.lastPage);

      if (pageResult.currentPage >= pageResult.lastPage) break;
      page += 1;
    }

    return all;
  }
}
