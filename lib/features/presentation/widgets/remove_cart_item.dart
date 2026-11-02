import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

Future<void> removeCartItem(BuildContext context, int index) async {
  final cubit = context.read<PosCubit>();
  final ticket = cubit.state.activeTicket;
  if (index < 0 || index >= ticket.items.length) return;
  final item = ticket.items[index];
  try {
    while (cubit.paymentOperationInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!context.mounted || cubit.isClosed) return;
    }
    if (cubit.state.activeTicketId != ticket.id) return;
    if (ticket.hasPendingCheckout) {
      try {
        await cubit.recoverPaymentDraft();
      } on StateError {
        // Preserve unresolved payment in its original ticket; removeAt opens
        // an editable basket without showing a blocking explanation.
      }
    }
    if (!context.mounted || cubit.state.activeTicketId != ticket.id) return;
    // Never remove a different item if the cart changed during recovery.
    if (index >= cubit.state.items.length || cubit.state.items[index] != item) {
      return;
    }
    cubit.removeAt(index);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error is StateError
          ? 'Товар не удалён. ${error.message}'
          : 'Товар не удалён. Не удалось проверить незавершённую оплату.'),
      duration: const Duration(seconds: 8),
    ));
  }
}
