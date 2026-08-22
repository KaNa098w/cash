import 'package:dio/dio.dart';

class CustomerDto {
  final String id;
  final String name;
  final String phone;
  final num balance;
  final num debtBalance;
  final String debtState;
  final num debtLimit;
  final bool debtAllowed;

  CustomerDto({
    required this.id,
    required this.name,
    required this.phone,
    this.balance = 0,
    this.debtBalance = 0,
    this.debtState = 'settled',
    this.debtLimit = 0,
    this.debtAllowed = true,
  });

  factory CustomerDto.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    final phone = json['phone']?.toString() ?? '';
    if (id.isEmpty) throw Exception('CustomerDto: missing id');
    return CustomerDto(
      id: id,
      name: name,
      phone: phone,
      balance: _readNum(
        json,
        const ['balance', 'debt_balance', 'current_debt', 'current_balance'],
      ),
      debtBalance: _readNum(
        json,
        const ['debt_balance', 'balance', 'current_debt', 'current_balance'],
      ),
      debtState: (json['debt_state'] ?? '').toString().trim().isEmpty
          ? _debtStateFromBalance(
              _readNum(
                json,
                const [
                  'debt_balance',
                  'balance',
                  'current_debt',
                  'current_balance'
                ],
              ),
            )
          : json['debt_state'].toString(),
      debtLimit: _readNum(
        json,
        const ['debt_limit', 'credit_limit', 'limit', 'max_debt'],
      ),
      debtAllowed: _readBool(
        json,
        const [
          'debt_allowed',
          'allow_debt',
          'credit_allowed',
          'allow_credit',
        ],
        fallback: true,
      ),
    );
  }

  CustomerDto copyWith({
    String? id,
    String? name,
    String? phone,
    num? balance,
    num? debtBalance,
    String? debtState,
    num? debtLimit,
    bool? debtAllowed,
  }) {
    return CustomerDto(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      balance: balance ?? this.balance,
      debtBalance: debtBalance ?? this.debtBalance,
      debtState: debtState ?? this.debtState,
      debtLimit: debtLimit ?? this.debtLimit,
      debtAllowed: debtAllowed ?? this.debtAllowed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'balance': balance,
        'debt_balance': debtBalance,
        'debt_state': debtState,
        'debt_limit': debtLimit,
        'debt_allowed': debtAllowed,
      };

  static num _readNum(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value;
      final parsed = num.tryParse((value ?? '').toString().trim());
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static bool _readBool(
    Map<String, dynamic> json,
    List<String> keys, {
    required bool fallback,
  }) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      final normalized = (value ?? '').toString().trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  static String _debtStateFromBalance(num value) {
    if (value > 0) return 'debt';
    if (value < 0) return 'advance';
    return 'settled';
  }
}

class CustomerSettlementDto {
  const CustomerSettlementDto({
    required this.id,
    required this.agent,
  });

  final String id;
  final CustomerDto agent;

  factory CustomerSettlementDto.fromJson(Map<String, dynamic> json) {
    final agentRaw = json['agent'];
    if (agentRaw is! Map) {
      throw Exception('CustomerSettlementDto: missing agent');
    }
    return CustomerSettlementDto(
      id: (json['id'] ?? '').toString(),
      agent: CustomerDto.fromJson(Map<String, dynamic>.from(agentRaw)),
    );
  }
}

class CustomerSettlementHistoryDto {
  const CustomerSettlementHistoryDto({
    required this.id,
    required this.amount,
    required this.date,
    this.remainingDebt,
    this.note,
  });

  final String id;
  final num amount;
  final DateTime date;
  final num? remainingDebt;
  final String? note;

  factory CustomerSettlementHistoryDto.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'] is Map
        ? Map<String, dynamic>.from(json['agent'] as Map)
        : const <String, dynamic>{};
    return CustomerSettlementHistoryDto(
      id: (json['id'] ?? json['client_settlement_id'] ?? '').toString(),
      amount: _firstNum(
        json,
        const ['amount', 'paid_amount', 'settlement_amount'],
      ),
      date: _firstDate(
            json,
            const ['date', 'created_at', 'settled_at'],
          ) ??
          DateTime.now(),
      remainingDebt: _firstNullableNum(
            json,
            const [
              'remaining_debt',
              'debt_balance',
              'balance_after',
              'current_debt',
            ],
          ) ??
          _firstNullableNum(
            agent,
            const ['debt_balance', 'balance', 'current_debt'],
          ),
      note: (json['note'] ?? '').toString().trim().isEmpty
          ? null
          : json['note'].toString().trim(),
    );
  }

  static num _firstNum(Map<String, dynamic> json, List<String> keys) =>
      _firstNullableNum(json, keys) ?? 0;

  static num? _firstNullableNum(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value;
      final parsed =
          num.tryParse((value ?? '').toString().replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  static DateTime? _firstDate(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = (json[key] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      final isoLike = raw.contains(' ') ? raw.replaceFirst(' ', 'T') : raw;
      final parsed = DateTime.tryParse(isoLike);
      if (parsed != null) return parsed;
    }
    return null;
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

    if (safeKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key is required');
    }
    if (safeName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Name is required');
    }
    if (safePhone.isEmpty) {
      throw ArgumentError.value(phone, 'phone', 'Phone is required');
    }

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
    bool hasDebt = false,
  }) async {
    final safeKey = key.trim();
    if (safeKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key is required');
    }

    final resp = await _dio.get(
      '/organizations/pos/$safeKey/customers',
      queryParameters: {
        if (page != null) 'page': page,
        if (size != null) 'size': size,
        if (hasDebt) 'filter[has_debt]': 1,
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

    throw Exception(
        'listCustomers: invalid "data" (expected List or {items:[]})');
  }

  Future<CustomerSettlementDto> settleDebt({
    required String key,
    required String customerId,
    required String accountId,
    required num amount,
    required DateTime date,
    required String userId,
    String? posSessionId,
    String? clientSettlementId,
    String? note,
  }) async {
    final safeKey = key.trim();
    final safeCustomerId = customerId.trim();
    final safeAccountId = accountId.trim();
    final safeUserId = userId.trim();

    if (safeKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key is required');
    }
    if (safeCustomerId.isEmpty) {
      throw ArgumentError.value(
          customerId, 'customerId', 'Customer is required');
    }
    if (safeAccountId.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'Account is required');
    }
    if (safeUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User is required');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Amount must be positive');
    }

    final resp = await _dio.post(
      '/organizations/pos/$safeKey/customers/$safeCustomerId/settlements',
      data: {
        'account_id': safeAccountId,
        'amount': amount,
        'date': _formatDate(date),
        'user_id': safeUserId,
        if ((posSessionId ?? '').trim().isNotEmpty)
          'pos_session_id': posSessionId!.trim(),
        if ((clientSettlementId ?? '').trim().isNotEmpty)
          'client_settlement_id': clientSettlementId!.trim(),
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );

    final payload = _extractDataMap(resp.data, op: 'settleDebt');
    return CustomerSettlementDto.fromJson(payload);
  }

  Future<List<CustomerSettlementHistoryDto>> listDebtSettlements({
    required String key,
    required String customerId,
    int perPage = 100,
  }) async {
    final safeKey = key.trim();
    final safeCustomerId = customerId.trim();
    if (safeKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key is required');
    }
    if (safeCustomerId.isEmpty) {
      throw ArgumentError.value(
        customerId,
        'customerId',
        'Customer is required',
      );
    }

    final resp = await _dio.get(
      '/organizations/pos/$safeKey/customers/$safeCustomerId/debt-history',
      queryParameters: {'perPage': perPage, 'page': 1},
    );
    if (resp.data is! Map) {
      throw Exception('listDebtSettlements: invalid response format');
    }
    final body = Map<String, dynamic>.from(resp.data as Map);
    final data = body['data'];
    final rawItems = data is List
        ? data
        : data is Map && data['items'] is List
            ? data['items'] as List
            : const <dynamic>[];
    return rawItems
        .whereType<Map>()
        .where(
          (item) =>
              (item['type'] ?? '').toString().trim().toLowerCase() ==
              'settlement',
        )
        .map((item) => CustomerSettlementHistoryDto.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.amount > 0)
        .toList(growable: false)
      ..sort((a, b) => b.date.compareTo(a.date));
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

  String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
