class RefundPick {
  RefundPick({
    required this.saleItemId,
    required this.productId,
    required this.checked,
    required this.quantity,
    required this.maxQuantity,
    required this.totalQuantity,
    required this.refundedQuantity,
    required this.price,
    this.originalMarkCodes = const <String>[],
    this.previouslyReturnedMarkCodes = const <String>[],
    this.markCodes = const <String>[],
    this.requiredMarkCodeCount = 0,
  });

  final String saleItemId;
  String productId;

  bool checked;
  int quantity;

  int maxQuantity;
  int totalQuantity;
  int refundedQuantity;

  final num price;
  final List<String> originalMarkCodes;
  final List<String> previouslyReturnedMarkCodes;
  List<String> markCodes;
  int requiredMarkCodeCount;

  bool get isMarked => originalMarkCodes.isNotEmpty;
  bool get hasRequiredMarkCodes {
    if (!isMarked) return true;
    final required =
        requiredMarkCodeCount > 0 ? requiredMarkCodeCount : quantity;
    return markCodes.length >= required;
  }
}
