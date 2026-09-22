import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

class EmptyRepository implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const product = Product(id: 'P', name: 'Товар', price: 1500);
  test('invoice survives restart, freezes cart and cannot become cash sale',
      () async {
    var cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(Duration.zero);
    cubit.addWithQty(product, 2);
    final id = cubit.state.activeTicketId;
    final checkout = {
      'pos_key': 'KEY',
      'payload': {
        'client_invoice_id': 'STABLE',
        'items': [
          {
            'product_id': 'P',
            'quantity': 2,
            'mark_codes': ['CODE']
          }
        ]
      }
    };
    await cubit.saveInvoiceCheckout(id, checkout);
    cubit.setQty(0, 10);
    cubit.removeAt(0);
    cubit.clearAfterPayment();
    expect(cubit.state.items.single.qty, 2);
    await expectLater(cubit.saveCheckout({'sale': {}}), throwsStateError);
    await cubit.close();
    cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cubit.state.activeTicket.invoiceCheckout, checkout);
    expect(cubit.state.activeTicket.hasPendingCheckout, isTrue);
    cubit.createHoldTicket();
    cubit.closeTicket(id);
    expect(cubit.state.tickets.any((t) => t.id == id), isTrue);
    final active = cubit.state.activeTicketId;
    cubit.addWithQty(product, 1);
    cubit.completeCheckout(id);
    expect(cubit.state.activeTicketId, active);
    expect(cubit.state.items.single.qty, 1);
    expect(cubit.state.tickets.any((t) => t.id == id), isFalse);
    await cubit.close();
  });
  test('validation rejection releases invoice without discarding cart',
      () async {
    final cubit = PosCubit(EmptyRepository());
    await Future<void>.delayed(Duration.zero);
    cubit.addWithQty(product, 2);
    await cubit
        .saveInvoiceCheckout(cubit.state.activeTicketId, {'payload': {}});
    cubit.releaseInvoiceCheckout(cubit.state.activeTicketId);
    cubit.setQty(0, 3);
    expect(cubit.state.items.single.qty, 3);
    expect(cubit.state.activeTicket.hasPendingCheckout, isFalse);
    await cubit.close();
  });
}
