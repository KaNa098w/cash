class PosPricingPlanStatus {
  const PosPricingPlanStatus({
    required this.isMaster,
    required this.isActive,
    required this.status,
    required this.availablePermissionGroups,
    this.endsAt,
    this.pricingPlan,
    this.storeLimit,
  });

  final bool isMaster;
  final bool isActive;
  final String status;
  final DateTime? endsAt;
  final PosPricingPlan? pricingPlan;
  final List<String> availablePermissionGroups;
  final int? storeLimit;

  factory PosPricingPlanStatus.fromApiJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return PosPricingPlanStatus.fromDataJson(data);
    }
    return PosPricingPlanStatus.fromDataJson(json);
  }

  factory PosPricingPlanStatus.fromDataJson(Map<String, dynamic> json) {
    final pricingPlanJson = json['pricing_plan'];
    final rawGroups = json['available_permission_groups'];
    return PosPricingPlanStatus(
      isMaster: _asBool(json['is_master']),
      isActive: _asBool(json['is_active']),
      status: (json['status'] ?? '').toString(),
      endsAt: _parseDate(json['ends_at']),
      pricingPlan: pricingPlanJson is Map<String, dynamic>
          ? PosPricingPlan.fromJson(pricingPlanJson)
          : null,
      availablePermissionGroups: rawGroups is List
          ? rawGroups
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const [],
      storeLimit: _parseInt(json['store_limit']),
    );
  }

  Map<String, dynamic> toJson() => {
        'is_master': isMaster,
        'is_active': isActive,
        'status': status,
        'ends_at': endsAt?.toIso8601String(),
        'pricing_plan': pricingPlan?.toJson(),
        'available_permission_groups': availablePermissionGroups,
        'store_limit': storeLimit,
      };

  bool shouldShowExpiryNotice({DateTime? now, int thresholdDays = 5}) {
    if (!isActive || isMaster || endsAt == null) return false;
    final days = daysUntilExpiry(now: now);
    return days != null && days >= 0 && days <= thresholdDays;
  }

  bool isAccessBlocked({DateTime? now}) {
    if (isMaster) return false;
    if (!isActive) return true;
    final end = endsAt;
    if (end == null) return false;
    return !end.toLocal().isAfter(now ?? DateTime.now());
  }

  int? daysUntilExpiry({DateTime? now}) {
    final end = endsAt;
    if (end == null) return null;
    final current = now ?? DateTime.now();
    final diff = end.toLocal().difference(current);
    return (diff.inMilliseconds / Duration.millisecondsPerDay).ceil();
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  static DateTime? _parseDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString().trim());
  }
}

class PosPricingPlan {
  const PosPricingPlan({
    required this.id,
    required this.name,
    required this.slug,
  });

  final String id;
  final String name;
  final String slug;

  factory PosPricingPlan.fromJson(Map<String, dynamic> json) {
    return PosPricingPlan(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
      };
}
