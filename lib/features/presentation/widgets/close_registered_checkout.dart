import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';

Future<void> closeRegisteredCheckout(
    BuildContext context, PosTicket ticket) async {
  final checkout = ticket.checkout;
  if (checkout == null) return;
  final cubit = context.read<PosCubit>();
  final auth = context.read<AuthTokenProvider>();
  final messenger = ScaffoldMessenger.of(context);
  void notify(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));

  try {
    final sale =
        SaleModel.fromJson(Map<String, dynamic>.from(checkout['sale']));
    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    if (key.isEmpty ||
        deviceId.isEmpty ||
        sale.storeId != auth.storeId ||
        (checkout['pos_key'] != null && checkout['pos_key'] != key) ||
        (checkout['device_id'] != null && checkout['device_id'] != deviceId)) {
      notify('Для сверки оплаты вернитесь в исходный магазин и терминал.');
      return;
    }
    notify('Проверяем регистрацию продажи…');
    final registered = await GetIt.I<PosSyncService>().isSaleRegistered(
        clientSaleId: sale.localId, key: key, deviceId: deviceId);
    if (!context.mounted || cubit.isClosed) return;
    if (!registered) {
      notify(
          'Регистрация продажи пока не подтверждена. Повторите оплату этого чека для сверки.');
      return;
    }
    // The ticket may have been completed or replaced while syncing.
    if (!cubit.state.tickets.any((current) =>
        current.id == ticket.id && identical(current.checkout, checkout))) {
      return;
    }
    cubit.completeCheckout(ticket.id);
    await cubit.flushPendingState();
    if (context.mounted) {
      notify('Отложенный чек закрыт. Продажа сохранена в истории.');
    }
  } catch (_) {
    if (context.mounted) {
      notify(
          'Не удалось проверить оплату. Проверьте соединение и повторите закрытие.');
    }
  }
}
