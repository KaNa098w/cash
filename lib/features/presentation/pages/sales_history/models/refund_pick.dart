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
  });

  final String saleItemId;
  String productId;

  bool checked;
  int quantity;

  int maxQuantity;
  int totalQuantity;
  int refundedQuantity;

  final num price;
}
