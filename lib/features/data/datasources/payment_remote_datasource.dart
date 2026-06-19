import 'package:dio/dio.dart';

class PaymentsRemoteDataSource {
  final Dio _dio;
  PaymentsRemoteDataSource(this._dio);

  Future<PaymentOperationPageModel> fetchPayments({
    required String key,
    int page = 1,
    int perPage = 25,
    bool? isExpense,
    String? expenseTypeId,
    String? accountId,
    DateTime? date,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) {
      throw Exception('fetchPayments: pos key is empty');
    }

    final resp = await _dio.get(
      '/organizations/pos/$safeKey/payments',
      queryParameters: <String, dynamic>{
        'page': page,
        'perPage': perPage,
        if (isExpense != null) 'filter[is_expense]': isExpense ? 1 : 0,
        if ((expenseTypeId ?? '').trim().isNotEmpty)
          'filter[expense_type_id]': expenseTypeId!.trim(),
        if ((accountId ?? '').trim().isNotEmpty)
          'filter[account_id]': accountId!.trim(),
        if (date != null) 'filter[date]': _formatIsoDate(date),
      },
    );

    final body = resp.data;
    if (body is! Map<String, dynamic>) {
      throw Exception('fetchPayments: invalid response format (expected Map)');
    }

    return PaymentOperationPageModel.fromApiResponse(body);
  }

  Future<String> createPayment({
    required String key,
    String? expenseTypeId,
    required bool isExpense,
    required num amount,
    String? comment,
    String? createdById,
  }) async {
    final safeKey = key.trim();

    final data = <String, dynamic>{
      'expense_type_id': expenseTypeId,
      'is_expense': isExpense,
      'amount': amount,
      'comment': comment,
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

  String _formatIsoDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class PaymentOperationModel {
  const PaymentOperationModel({
    required this.id,
    required this.number,
    required this.isExpense,
    required this.amount,
    required this.comment,
    required this.expenseTypeId,
    required this.accountId,
    required this.posId,
    required this.posSessionId,
    required this.date,
  });

  final String id;
  final String number;
  final bool isExpense;
  final num amount;
  final String comment;
  final String expenseTypeId;
  final String accountId;
  final String posId;
  final String posSessionId;
  final DateTime? date;

  factory PaymentOperationModel.fromJson(Map<String, dynamic> json) {
    return PaymentOperationModel(
      id: (json['id'] ?? '').toString(),
      number: (json['number'] ?? '').toString(),
      isExpense: _asBool(json['is_expense']),
      amount: _asNum(json['amount']),
      comment: (json['comment'] ?? '').toString(),
      expenseTypeId: (json['expense_type_id'] ?? '').toString(),
      accountId: (json['account_id'] ?? '').toString(),
      posId: (json['pos_id'] ?? '').toString(),
      posSessionId: (json['pos_session_id'] ?? '').toString(),
      date: _asDateTime(json['date']),
    );
  }
}

class PaymentOperationPageModel {
  const PaymentOperationPageModel({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });

  final List<PaymentOperationModel> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  factory PaymentOperationPageModel.fromApiResponse(Map<String, dynamic> json) {
    final dataRaw = json['data'];
    final items = dataRaw is List
        ? dataRaw
            .whereType<Map>()
            .map((e) =>
                PaymentOperationModel.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : <PaymentOperationModel>[];

    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'])
        : const <String, dynamic>{};
    final currentPage = _asInt(meta['current_page']);
    final lastPage = _asInt(meta['last_page']);

    return PaymentOperationPageModel(
      items: items,
      currentPage: currentPage <= 0 ? 1 : currentPage,
      lastPage: lastPage <= 0 ? 1 : lastPage,
      total: _asInt(meta['total']),
      perPage: _asInt(meta['per_page']),
    );
  }
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final raw = value?.toString().trim().toLowerCase() ?? '';
  return raw == '1' || raw == 'true' || raw == 'yes';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
}

DateTime? _asDateTime(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(
      raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw);
}
