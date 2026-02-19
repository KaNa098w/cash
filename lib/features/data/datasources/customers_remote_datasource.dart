import 'package:dio/dio.dart';

class CustomerDto {
  final String id;
  final String name;
  final String phone;

  CustomerDto({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory CustomerDto.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    final phone = json['phone']?.toString() ?? '';
    if (id.isEmpty) throw Exception('CustomerDto: missing id');
    return CustomerDto(id: id, name: name, phone: phone);
  }
}

class CustomersRemoteDataSource {
  final Dio _dio;
  CustomersRemoteDataSource(this._dio);

  Future<CustomerDto> createCustomer({
    required String key,
    required String name,
    required String phone,
  }) async {
    final safeKey = key.trim();
    final safeName = name.trim();
    final safePhone = phone.trim();

    if (safeKey.isEmpty) throw ArgumentError.value(key, 'key', 'Key is required');
    if (safeName.isEmpty) throw ArgumentError.value(name, 'name', 'Name is required');
    if (safePhone.isEmpty) throw ArgumentError.value(phone, 'phone', 'Phone is required');

    final resp = await _dio.post(
      '/organizations/pos/$safeKey/customers',
      data: {'name': safeName, 'phone': safePhone},
    );

    final payload = _extractDataMap(resp.data, op: 'createCustomer');
    return CustomerDto.fromJson(payload);
  }

  /// GET /organizations/pos/{key}/customers
  Future<List<CustomerDto>> listCustomers({
    required String key,
    int? page,
    int? size,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) throw ArgumentError.value(key, 'key', 'Key is required');

    final resp = await _dio.get(
      '/organizations/pos/$safeKey/customers',
      queryParameters: {
        if (page != null) 'page': page,
        if (size != null) 'size': size,
      },
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('listCustomers: invalid response format (expected Map)');
    }

    final data = body['data'];

    // 1) data = [ ... ]
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => CustomerDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    // 2) data = { items: [ ... ] }
    if (data is Map && data['items'] is List) {
      final items = data['items'] as List;
      return items
          .whereType<Map>()
          .map((e) => CustomerDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    throw Exception('listCustomers: invalid "data" (expected List or {items:[]})');
  }

  Map<String, dynamic> _extractDataMap(dynamic body, {required String op}) {
    if (body is! Map<String, dynamic>) {
      throw Exception('$op: invalid response format (expected Map)');
    }
    final data = body['data'];
    if (data is! Map) {
      throw Exception('$op: invalid "data" (expected Map)');
    }
    return Map<String, dynamic>.from(data);
  }
}
