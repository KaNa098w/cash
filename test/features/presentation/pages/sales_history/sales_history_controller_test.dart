import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_history_controller.dart';

void main() {
  test('blocks duplicate refund while submitting and during cooldown',
      () async {
    final controller = SalesHistoryController();
    addTearDown(controller.dispose);

    expect(controller.tryStartRefund('sale-1', () {}), isTrue);
    expect(controller.tryStartRefund('sale-1', () {}), isFalse);

    controller.startRefundCooldown(
      'sale-1',
      const Duration(milliseconds: 30),
      () {},
    );
    expect(controller.tryStartRefund('sale-1', () {}), isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.tryStartRefund('sale-1', () {}), isTrue);
  });
}
