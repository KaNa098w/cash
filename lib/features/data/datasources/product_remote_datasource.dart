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
          'perPage': perPage, // если параметр другой — поменяй
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
        return ProductModel.fromJson(Map<String, dynamic>.from(e));
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

  Future<String?> findProductNameByBarcode({
    required String key,
    required String barcode,
    required String deviceId,
  }) async {
    final safeKey = key.trim();
    final safeBarcode = barcode.trim();
    final safeDeviceId = deviceId.trim();

    if (safeKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'POS key is empty');
    }
    if (!RegExp(r'^\d{11,13}$').hasMatch(safeBarcode)) {
      throw ArgumentError.value(
        barcode,
        'barcode',
        'Barcode must contain 11 to 13 digits',
      );
    }
    if (safeDeviceId.isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Device id is empty');
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '/organizations/pos/$safeKey/products/name',
      queryParameters: {
        'barcode': safeBarcode,
        'device_id': safeDeviceId,
      },
    );

    final data = response.data?['data'];
    if (data is! Map) {
      throw const FormatException('Invalid product name response');
    }

    final name = data['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  Future<ProductModel> createProduct({
    required String key,
    required String barcode,
    required double sellingPrice,
    required String deviceId,
    String? name,
    MeasurementUnit? measurementUnit,
  }) async {
    final safeKey = key.trim();
    final safeBarcode = barcode.trim();
    final safeDeviceId = deviceId.trim();
    final safeName = name?.trim() ?? '';

    if (safeKey.isEmpty) throw Exception('createProduct: pos key is empty');
    if (safeDeviceId.isEmpty) {
      throw Exception('createProduct: device id is empty');
    }

    final response = await _dio.post(
      '/organizations/pos/$safeKey/products',
      data: <String, dynamic>{
        'barcode': safeBarcode,
        'selling_price': sellingPrice,
        'device_id': safeDeviceId,
        if (safeName.isNotEmpty) 'name': safeName,
        if (measurementUnit != null)
          'measurement_unit': measurementUnit.apiValue,
      },
    );

    final body = response.data;
    final data = body is Map ? body['data'] : null;
    if (response.statusCode != 201 || data is! Map) {
      throw StateError('Некорректный ответ при создании товара');
    }

    final product = ProductModel.fromJson(Map<String, dynamic>.from(data));
    if ((product.id ?? '').trim().isEmpty ||
        (product.barcode ?? '').trim().isEmpty) {
      throw StateError('В ответе отсутствуют данные созданного товара');
    }
    return product;
  }

  Future<ProductModel> updateProductPrice({
    required String key,
    required String productId,
    required String userId,
    required String deviceId,
    required double sellingPrice,
    String? refundAccessKey,
  }) async {
    final safeKey = key.trim();
    final safeProductId = productId.trim();
    final safeUserId = userId.trim();
    final safeDeviceId = deviceId.trim();
    final accessKey = refundAccessKey?.trim();

    if (safeKey.isEmpty) {
      throw Exception('updateProductPrice: pos key is empty');
    }
    if (safeProductId.isEmpty) {
      throw Exception('updateProductPrice: product id is empty');
    }
    if (safeUserId.isEmpty) {
      throw Exception('updateProductPrice: user id is empty');
    }
    if (safeDeviceId.isEmpty) {
      throw Exception('updateProductPrice: device id is empty');
    }

    final response = await _dio.put(
      '/organizations/pos/$safeKey/products/$safeProductId/price',
      data: {
        'selling_price': sellingPrice,
        'user_id': safeUserId,
        'device_id': safeDeviceId,
        if (accessKey != null && accessKey.isNotEmpty)
          'refund_access_key': accessKey,
      },
      options: accessKey == null || accessKey.isEmpty
          ? null
          : Options(headers: {'X-Return-Access-Key': accessKey}),
    );

    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw Exception(
        'updateProductPrice: invalid response format (expected Map)',
      );
    }
    final data = body['data'];
    if (data is! Map) {
      throw Exception('updateProductPrice: invalid "data" (expected Map)');
    }

    return ProductModel.fromJson(Map<String, dynamic>.from(data));
  }
}
