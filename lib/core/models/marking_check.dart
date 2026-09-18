class MarkingCheckItem {
  const MarkingCheckItem(
      {required this.productId,
      required this.requiresMarking,
      required this.ready,
      required this.scanRequired,
      required this.openQuantity,
      required this.packageQuantity,
      required this.providedCodesCount,
      required this.requiredCodesCount,
      required this.missingQuantity,
      this.errorCode,
      this.message});

  final String productId;
  final bool requiresMarking, ready, scanRequired;
  final double openQuantity, missingQuantity;
  final double? packageQuantity;
  final int providedCodesCount, requiredCodesCount;
  final String? errorCode, message;

  factory MarkingCheckItem.fromJson(Map<String, dynamic> json) =>
      MarkingCheckItem(
        productId: json['product_id'] as String,
        requiresMarking: json['requires_marking'] == true,
        ready: json['ready'] == true,
        scanRequired: json['scan_required'] == true,
        openQuantity: (json['open_quantity'] as num?)?.toDouble() ?? 0,
        packageQuantity: (json['package_quantity'] as num?)?.toDouble(),
        providedCodesCount:
            (json['provided_codes_count'] as num?)?.toInt() ?? 0,
        requiredCodesCount:
            (json['required_codes_count'] as num?)?.toInt() ?? 0,
        missingQuantity: (json['missing_quantity'] as num?)?.toDouble() ?? 0,
        errorCode: json['error_code'] as String?,
        message: json['message'] as String?,
      );
}

class MarkingCheckResponse {
  const MarkingCheckResponse({required this.ready, required this.items});
  final bool ready;
  final List<MarkingCheckItem> items;
  bool get canPay => ready && items.every((item) => item.ready);
  factory MarkingCheckResponse.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map);
    return MarkingCheckResponse(
        ready: data['ready'] == true,
        items: (data['items'] as List)
            .map((item) => MarkingCheckItem.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList());
  }
}
