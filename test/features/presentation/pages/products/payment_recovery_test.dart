import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/features/presentation/widgets/remove_cart_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/features/domain/entities/product.dart';
import 'package:leemon_app/features/domain/entities/payment.dart';
import 'package:leemon_app/features/domain/repositories/pos_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

class _Repository implements PosRepository {
  @override
  Future<List<Product>> searchProducts(String query) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PosCubit> cart() async {
    final cubit = PosCubit(_Repository());
    await Future<void>.delayed(Duration.zero);
    cubit.add(const Product(id: 'p', name: 'Product', price: 100));
    cubit.setPaymentKind(PaymentKind.card);
    cubit.setReceived(100);
    return cubit;
  }

  testWidgets('delete preserves a submitted sale without blocking the basket',
      (tester) async {
    final cubit = (await tester.runAsync(cart))!;
    await tester.pumpWidget(MaterialApp(
        home: BlocProvider.value(
      value: cubit,
      child: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => removeCartItem(context, 0),
                    child: const Text('Delete'),
                  ))),
    )));
    await tester.runAsync(() => cubit.saveCheckout({
          'sale': {'localId': 'sale'},
          'sale_request_started': true
        }));
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cubit.flushPendingState();
    });
    await tester.pumpAndSettle();
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.tickets.first.checkout, isNotNull);
    expect(cubit.state.tickets.first.items.length, 1);
    expect(find.byType(SnackBar), findsNothing);
    cubit.switchTicket(cubit.state.tickets.first.id);
    await tester.runAsync(() => cubit.saveCheckout({
          'sale': {'localId': 'sale'},
          'sale_request_started': false
        }));
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.activeTicket.checkout, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  test('recovery preserves products and persists a cash draft', () async {
    final cubit = await cart();
    final items = cubit.state.items;
    await cubit.recoverPaymentDraft();
    expect(cubit.state.items, items);
    expect(cubit.state.paymentKind, PaymentKind.cash);
    expect(cubit.state.received, 0);
    await cubit.close();
    final restored = PosCubit(_Repository());
    await Future<void>.delayed(Duration.zero);
    expect(restored.state.items.length, 1);
    expect(restored.state.paymentKind, PaymentKind.cash);
    await restored.close();
  });

  test('payment selection is not blocked by an older checkout', () async {
    for (final kind in [PaymentKind.cash, PaymentKind.card]) {
      final cubit = await cart();
      final originalId = cubit.state.activeTicketId;
      final items = cubit.state.items;
      final checkout = {
        'sale': {'localId': 'sale'},
        'sale_request_started': true,
      };
      await cubit.saveCheckout(checkout);
      cubit.changePaymentKind(kind);
      expect(cubit.state.paymentKind, kind);
      expect(cubit.state.activeTicketId, isNot(originalId));
      expect(cubit.state.activeTicket.hasPendingCheckout, isFalse);
      expect(cubit.state.items, items);
      expect(cubit.state.activeTicket.clientSaleId, isNull);
      expect(cubit.state.tickets.firstWhere((t) => t.id == originalId).checkout,
          checkout);
      cubit.setReceived(100);
      expect(cubit.state.received, 100);
      cubit.changePaymentKind(PaymentKind.card);
      expect(cubit.state.tickets.length, 2);
      await cubit.close();
      SharedPreferences.setMockInitialValues({});
    }
  });

  test('deleting queued sale clears only its matching checkout durably',
      () async {
    final cubit = await cart();
    final saleId = cubit.ensureClientSaleId();
    await cubit.saveCheckout({
      'sale': {'localId': saleId}
    });
    final originalId = cubit.state.activeTicketId;
    cubit.createHoldTicket();
    await cubit.saveCheckout({
      'sale': {'localId': 'other-sale'}
    });
    await cubit.releaseDeletedSale(saleId);
    final released = cubit.state.tickets.firstWhere((t) => t.id == originalId);
    expect(released.checkout, isNull);
    expect(released.clientSaleId, isNull);
    expect(released.items.length, 1);
    expect(cubit.state.activeTicket.checkout, isNotNull);
    await cubit.close();
    final restored = PosCubit(_Repository());
    await Future<void>.delayed(Duration.zero);
    expect(
        restored.state.tickets.firstWhere((t) => t.id == originalId).checkout,
        isNull);
    await restored.close();
  });

  test('only a known unsubmitted checkout may be released', () async {
    for (final flag in [null, true, false]) {
      final cubit = await cart();
      await cubit.saveCheckout({
        'sale': {'localId': 'sale'},
        if (flag != null) 'sale_request_started': flag,
      });
      if (flag == false) {
        await cubit.recoverPaymentDraft();
        expect(cubit.state.activeTicket.checkout, isNull);
      } else {
        await expectLater(cubit.recoverPaymentDraft(), throwsStateError);
        expect(cubit.state.activeTicket.checkout, isNotNull);
      }
      await cubit.close();
      SharedPreferences.setMockInitialValues({});
    }
  });

  test('Kaspi journal and active operations prevent reset', () async {
    final cubit = await cart();
    await cubit.saveCheckout({
      'sale': {'localId': 'sale'},
      'sale_request_started': false,
    });
    final prefs = await SharedPreferences.getInstance();
    for (final status in ['starting', 'wait', 'success']) {
      await prefs.setString(
          'kaspi.payment.sale', jsonEncode({'status': status}));
      await expectLater(cubit.recoverPaymentDraft(), throwsStateError);
      expect(cubit.state.activeTicket.checkout, isNotNull);
    }
    await prefs.remove('kaspi.payment.sale');
    final ticketId = cubit.state.activeTicketId;
    final operation = cubit.beginPaymentOperation()!;
    await expectLater(cubit.recoverPaymentDraft(), throwsStateError);
    cubit.endPaymentOperation(ticketId, operation);
    await cubit.recoverPaymentDraft();
    expect(cubit.state.items.length, 1);
    await cubit.close();
  });

  test('a running payment locks only its own ticket', () async {
    final cubit = await cart();
    final originalId = cubit.state.activeTicketId;
    final operation = cubit.beginPaymentOperation()!;
    expect(cubit.beginPaymentOperation(), isNull);
    cubit.changePaymentKind(PaymentKind.cash);
    expect(cubit.state.paymentKind, PaymentKind.card);

    cubit.createHoldTicket();
    final nextId = cubit.state.activeTicketId;
    cubit.add(const Product(id: 'next', name: 'Next customer', price: 200));
    expect(cubit.paymentOperationInProgress, isFalse);
    cubit.changePaymentKind(PaymentKind.cash);
    expect(cubit.state.paymentKind, PaymentKind.cash);
    final nextOperation = cubit.beginPaymentOperation()!;

    cubit.endPaymentOperation(originalId, operation);
    expect(cubit.paymentOperationInProgress, isTrue);
    cubit.endPaymentOperation(nextId, nextOperation);
    expect(cubit.paymentOperationInProgress, isFalse);
    await cubit.close();
  });

  test('late cleanup cannot unlock or clear the next customer payment', () async {
    final cubit = await cart();
    final ticketId = cubit.state.activeTicketId;
    final oldOperation = cubit.beginPaymentOperation()!;
    await cubit.saveCheckout({'sale': {'localId': 'old-sale'}});
    cubit.completeCheckout(ticketId);
    cubit.endPaymentOperation(ticketId, oldOperation);

    cubit.add(const Product(id: 'new', name: 'New customer', price: 200));
    cubit.changePaymentKind(PaymentKind.card);
    cubit.setReceived(200);
    final newOperation = cubit.beginPaymentOperation()!;
    await cubit.saveCheckout({'sale': {'localId': 'new-sale'}});
    // Old printer/fiscal work finishes after a new checkout has begun.
    cubit.endPaymentOperation(ticketId, oldOperation);
    expect(cubit.paymentOperationInProgress, isTrue);
    expect(cubit.state.items.single.product.id, 'new');
    expect(cubit.state.activeTicket.checkout!['sale']['localId'], 'new-sale');
    expect(cubit.state.received, 200);
    cubit.endPaymentOperation(ticketId, newOperation);
    await cubit.close();
  });

  test('late payment persistence and rejection target their original ticket',
      () async {
    final cubit = await cart();
    final originalId = cubit.state.activeTicketId;
    cubit.createHoldTicket();
    cubit.add(const Product(id: 'new', name: 'New customer', price: 200));
    final activeId = cubit.state.activeTicketId;
    await cubit.saveCheckout({'sale': {'localId': 'new-sale'}});
    await cubit.saveCheckout({'sale': {'localId': 'old-sale'}},
        ticketId: originalId);
    expect(cubit.state.activeTicketId, activeId);
    expect(cubit.state.activeTicket.checkout!['sale']['localId'], 'new-sale');
    cubit.releaseCheckout(ticketId: originalId);
    expect(cubit.state.tickets.first.checkout, isNull);
    expect(cubit.state.activeTicket.checkout!['sale']['localId'], 'new-sale');
    await cubit.close();
  });
}
