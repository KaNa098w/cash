class PosProvisionResponse {
  final String id;
  final String name;
  final String number;
  final String key;
  final String accountId;
  final String storeId;
  final String storeName;
  final bool isTest;
  final bool allowCustomSalePrices;
  final bool allowBelowCostSalePrices;
  final bool allowRefundsWithoutSale;
  final String organizationId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final List<PosUser> users;

  PosProvisionResponse({
    required this.id,
    required this.name,
    this.number = '',
    required this.key,
    required this.accountId,
    required this.storeId,
    required this.storeName,
    this.isTest = false,
    this.allowCustomSalePrices = false,
    this.allowBelowCostSalePrices = false,
    this.allowRefundsWithoutSale = false,
    required this.organizationId,
    required this.users,
    this.createdAt,
    this.updatedAt,
  });

  factory PosProvisionResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid response: missing "data". json=$json');
    }
    final id = (data['id'] ?? '').toString();

    final name = (data['name'] ?? '').toString();
    final number = (data['number'] ?? '').toString();
    final key = (data['key'] ?? '').toString();
    final accountId = (data['account_id'] ?? '').toString();
    final storeId = (data['store_id'] ?? '').toString();
    final isTest = _asBool(data['is_test']);
    String storeName =
        (data['store_name'] ?? data['storeName'] ?? '').toString();
    final store = data['store'];
    if (store is Map<String, dynamic>) {
      final fromStore = (store['name'] ?? store['title'] ?? '').toString();
      if (fromStore.isNotEmpty) storeName = fromStore;
    }
    final allowCustomSalePrices = _asBool(
      store is Map<String, dynamic>
          ? store['allow_custom_sale_prices']
          : data['allow_custom_sale_prices'],
    );
    final allowBelowCostSalePrices = _asBool(
      store is Map<String, dynamic>
          ? store['allow_below_cost_sale_prices']
          : data['allow_below_cost_sale_prices'],
    );
    final allowRefundsWithoutSale = _asBool(
      store is Map<String, dynamic>
          ? store['allow_refunds_without_sale']
          : data['allow_refunds_without_sale'],
    );
    final organizationId = (data['organization_id'] ?? '').toString();

    if (name.isEmpty ||
        key.isEmpty ||
        accountId.isEmpty ||
        storeId.isEmpty ||
        organizationId.isEmpty) {
      throw Exception('Missing required fields in response.data: $data');
    }

    DateTime? parseDt(dynamic v) {
      // created: { human: "...", string: "2025-..." }
      if (v is Map<String, dynamic>) {
        final s = v['string'];
        if (s is String && s.isNotEmpty) return DateTime.tryParse(s);
      }
      return null;
    }

    final rawUsers = data['users'];
    final users = _uniqueUsersById(
      (rawUsers is List ? rawUsers : const [])
          .whereType<Map<String, dynamic>>()
          .map(PosUser.fromJson),
    );

    return PosProvisionResponse(
      id: id,
      name: name,
      number: number,
      key: key,
      accountId: accountId,
      storeId: storeId,
      storeName: storeName,
      isTest: isTest,
      allowCustomSalePrices: allowCustomSalePrices,
      allowBelowCostSalePrices: allowBelowCostSalePrices,
      allowRefundsWithoutSale: allowRefundsWithoutSale,
      organizationId: organizationId,
      createdAt: parseDt(data['created']),
      updatedAt: parseDt(data['updated']),
      users: users,
    );
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  static List<PosUser> _uniqueUsersById(Iterable<PosUser> users) {
    final uniqueById = <String, PosUser>{};
    for (final user in users) {
      uniqueById[user.id] = user;
    }
    return uniqueById.values.toList();
  }
}

class PosUser {
  final String id;
  final String name;
  final String emailAddress;
  final bool emailVerified;

  // Приходит с API (может быть пустым, если из кэша)
  final String pinCode;

  // Храним в кэше
  final String? pinHash;

  final String? avatar;
  final List<String> roles;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PosUser({
    required this.id,
    required this.name,
    required this.emailAddress,
    required this.emailVerified,
    required this.pinCode,
    this.pinHash,
    this.avatar,
    this.roles = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory PosUser.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? '').toString();

    String emailAddress = '';
    bool emailVerified = false;
    final email = json['email'];
    if (email is Map<String, dynamic>) {
      emailAddress = (email['address'] ?? '').toString();
      emailVerified = email['verified'] == true;
    } else if (email is String) {
      emailAddress = email;
    }

    final pinCode = (json['pin_code'] ?? json['pinCode'] ?? '').toString();
    final pinHash = (json['pin_hash'] ?? '').toString();
    final avatar = (json['avatar'] ?? '')?.toString();
    final rolesRaw = json['roles'];
    final roles = rolesRaw is List
        ? rolesRaw
            .map((role) => role.toString().trim())
            .where((role) => role.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    DateTime? parseDt(dynamic v) {
      if (v is Map<String, dynamic>) {
        final s = v['string'];
        if (s is String && s.isNotEmpty) return DateTime.tryParse(s);
      }
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    if (id.isEmpty) throw Exception('PosUser.id is empty. json=$json');
    if (name.isEmpty) throw Exception('PosUser.name is empty. json=$json');

    // В кэше pin_code может не быть — это ок, если есть pin_hash
    if (pinCode.isEmpty && pinHash.isEmpty) {
      throw Exception('PosUser pin missing (pin_code/pin_hash). json=$json');
    }

    return PosUser(
      id: id,
      name: name,
      emailAddress: emailAddress,
      emailVerified: emailVerified,
      pinCode: pinCode,
      pinHash: pinHash.isEmpty ? null : pinHash,
      avatar: (avatar != null && avatar.isNotEmpty) ? avatar : null,
      roles: roles,
      createdAt: parseDt(json['created']),
      updatedAt: parseDt(json['updated']),
    );
  }

  PosUser copyWith({String? pinHash, String? pinCode, List<String>? roles}) =>
      PosUser(
        id: id,
        name: name,
        emailAddress: emailAddress,
        emailVerified: emailVerified,
        pinCode: pinCode ?? this.pinCode,
        pinHash: pinHash ?? this.pinHash,
        avatar: avatar,
        roles: roles ?? this.roles,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': {
          'address': emailAddress,
          'verified': emailVerified,
        },
        // ВАЖНО: pin_code не кладём в кэш
        'pin_hash': pinHash,
        'avatar': avatar,
        'roles': roles,
        'created': createdAt?.toIso8601String(),
        'updated': updatedAt?.toIso8601String(),
      };
}
