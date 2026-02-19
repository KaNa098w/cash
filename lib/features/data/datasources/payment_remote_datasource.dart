import 'package:dio/dio.dart';

class PaymentsRemoteDataSource {
  final Dio _dio;
  PaymentsRemoteDataSource(this._dio);

  Future<String> createPayment({
    required String key,
    String? expenseTypeId,
    required bool isExpense,
    required num amount,
    String? createdById,
  }) async {
    final safeKey = key.trim();

    final data = <String, dynamic>{
      'expense_type_id': expenseTypeId,
      'is_expense': isExpense,
      'amount': amount,
      'created_by_id': createdById,
    }..removeWhere((_, v) => v == null);

    final resp = await _dio.post(
      '/organizations/pos/$safeKey/payments',
      data: data,
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('createPayment: invalid response format (expected Map)');
    }

    final payload = body['data'];
    if (payload is! Map<String, dynamic>) {
      throw Exception('createPayment: invalid "data" (expected Map)');
    }

    final id = payload['id']?.toString();
    if (id == null || id.isEmpty) {
      throw Exception('createPayment: missing data.id');
    }

    return id;
  }

  /// GET /organizations/pos/{key}/expense-types
  Future<List<Map<String, dynamic>>> fetchExpenseTypes({
    required String key,
  }) async {
    final safeKey = key.trim();

    final resp = await _dio.get(
      '/organizations/pos/$safeKey/expense-types',
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception(
          'fetchExpenseTypes: invalid response format (expected Map)');
    }

    final data = body['data'];
    if (data is! List) {
      throw Exception('fetchExpenseTypes: invalid "data" (expected List)');
    }

    return data.map<Map<String, dynamic>>((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return Map<String, dynamic>.from(e);
      throw Exception('fetchExpenseTypes: invalid item (expected Map)');
    }).toList(growable: false);
  }
}
