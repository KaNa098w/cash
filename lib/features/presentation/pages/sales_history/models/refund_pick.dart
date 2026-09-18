import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/marking/refund_marking_allocation.dart';

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
    this.markingParts = const [],
    this.returnedMarkingParts = const [],
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

  final List<MarkingPartModel> markingParts;
  List<MarkingPartModel> returnedMarkingParts;

  bool get isMarked => originalMarkCodes.isNotEmpty;
  bool get hasRequiredMarkCodes {
    if (!isMarked) return true;
    return RefundMarkingAllocation.covers(
        quantity: quantity,
        codes: markCodes,
        originalCodes: originalMarkCodes,
        sold: markingParts,
        returned: returnedMarkingParts);
  }
}
