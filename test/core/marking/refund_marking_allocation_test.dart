import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/marking/refund_marking_allocation.dart';
import 'package:leemon_app/core/models/refund_inventory_action.dart';
import 'package:leemon_app/core/models/sale_model.dart';

void main() {
  const first = '010460026601046921FIRST';
  const second = '010460026601046921SECOND';
  const sold = [
    MarkingPartModel(code: first, quantity: 2, packageQuantity: 10),
    MarkingPartModel(code: second, quantity: 1, packageQuantity: 10),
  ];
  bool covers(num quantity, List<String> codes,
          {List<MarkingPartModel> returned = const []}) =>
      RefundMarkingAllocation.covers(
          quantity: quantity,
          codes: codes,
          originalCodes: [first, second],
          sold: sold,
          returned: returned);

  test(
      'one packaging code covers multiple returned units, AIM prefix is canonicalized',
      () {
    expect(covers(2, [']d2$first\r\n']), isTrue);
    expect(covers(2, [second]), isFalse);
    expect(covers(3, [first, second]), isTrue);
    expect(covers(3, [first]), isFalse);
  });
  test(
      'previous partial refund reduces capacity but does not forbid the package code',
      () {
    const returned = [
      MarkingPartModel(code: ']d2$first', quantity: 1, packageQuantity: 10)
    ];
    expect(covers(1, [first], returned: returned), isTrue);
    expect(covers(2, [first], returned: returned), isFalse);
    expect(covers(2, [first, second], returned: returned), isTrue);
  });
  test('duplicates and codes outside original sale are rejected', () {
    expect(covers(3, [first, ']d2$first']), isFalse);
    expect(covers(1, ['010460026601046921OTHER']), isFalse);
  });
  test('legacy sale without marking_parts never requires one code per unit',
      () {
    expect(
        RefundMarkingAllocation.covers(
            quantity: 5, codes: [first], originalCodes: [first], sold: []),
        isTrue);
  });
  test('reason defaults match inventory contract', () {
    for (final reason in ['defective', 'damaged', 'expired']) {
      expect(RefundInventoryAction.forReason(reason),
          RefundInventoryAction.writeOff);
    }
    for (final reason in ['incorrect_quantity', 'duplicate_sale']) {
      expect(RefundInventoryAction.forReason(reason),
          RefundInventoryAction.reverseSale);
    }
    expect(RefundInventoryAction.forReason('incorrect_price'),
        RefundInventoryAction.amountCorrection);
    expect(RefundInventoryAction.forReason('customer_changed_mind'),
        RefundInventoryAction.returnToStock);
  });
}
