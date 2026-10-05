import 'dart:async';

import 'footer_panels_widget.dart';
import 'top_bar.dart' show PosTicketTab;
import '../pages/products/cart_list/cart_list.dart' show CartProductImage;
import '../../data/utils/money.dart' show money;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/core/print/marketplace_invoice_data.dart';
import 'package:leemon_app/features/presentation/widgets/invoice_preview_dialog.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/presentation/pages/marketplace_orders/marketplace_orders_controller.dart';
import 'package:provider/provider.dart';

Future<void> showIncomingOrdersDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'incoming-orders',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => const _IncomingOrdersDialog(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _IncomingOrdersDialog extends StatefulWidget {
  const _IncomingOrdersDialog();

  @override
  State<_IncomingOrdersDialog> createState() => _IncomingOrdersDialogState();
}

class _IncomingOrdersDialogState extends State<_IncomingOrdersDialog> {
  late final MarketplaceOrdersController _controller;
  String? _printingInvoiceOrderId;

  @override
  void initState() {
    super.initState();
    _controller = GetIt.I<MarketplaceOrdersController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthTokenProvider>();
      unawaited(() async {
        await _controller.configure(
          posKey: auth.posKey ?? '',
          deviceId: auth.deviceId ?? '',
        );
      }());
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Material(
      color: const Color(0xFFF3F4F6),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Theme(
          data: Theme.of(context).copyWith(
            textTheme:
                Theme.of(context).textTheme.apply(fontFamily: 'NotoSans'),
          ),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Column(
                  children: [
                    _Header(
                      controller: _controller,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    _StatusFilters(controller: _controller),
                    if (_controller.error != null)
                      _ErrorStrip(
                        text: _controller.error!,
                        onRefresh: _controller.refreshVisibleOrders,
                      ),
                    Expanded(
                      child: _OrderDetails(controller: _controller),
                    ),
                    _MarketplaceFooter(
                      controller: _controller,
                      printingInvoiceOrderId: _printingInvoiceOrderId,
                      onPrintInvoice: _printInvoice,
                      onOrders: _controller.refreshVisibleOrders,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printInvoice(MarketplaceOrder order) async {
    if (_printingInvoiceOrderId != null) return;
    setState(() => _printingInvoiceOrderId = order.id);

    final auth = context.read<AuthTokenProvider>();
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? '-'
        : auth.activeUserName!.trim();
    final storeName = (auth.storeName?.trim().isNotEmpty == true)
        ? auth.storeName!.trim()
        : (auth.posName?.trim().isNotEmpty == true)
            ? auth.posName!.trim()
            : 'Магазин';

    try {
      await showInvoicePreview(
        context,
        printerName: auth.invoicePrinterName,
        data: marketplaceInvoiceData(
          order,
          cashierName: cashierName,
          storeName: storeName,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка открытия накладной: $e')),
      );
    } finally {
      if (mounted) setState(() => _printingInvoiceOrderId = null);
    }
  }
}

class _Header extends StatefulWidget {
  const _Header({required this.controller, required this.onClose});
  final MarketplaceOrdersController controller;
  final VoidCallback onClose;
  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final _scrollController = ScrollController();
  MarketplaceOrderScope? _lastScope;
  MarketplaceOrdersController get controller => widget.controller;
  VoidCallback get onClose => widget.onClose;
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastScope != controller.scope) {
      _lastScope = controller.scope;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    final compact = MediaQuery.sizeOf(context).width <= 900;
    final busy = controller.loading || controller.actionLoading;
    return Container(
      height: compact ? 60 : 68,
      color: const Color(0xFF262B35),
      padding: EdgeInsets.fromLTRB(compact ? 10 : 20, 0, 8, 0),
      child: Row(children: [
        Expanded(
            child: Padding(
          padding: EdgeInsets.only(top: compact ? 8 : 14),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 240 &&
                  controller.scope == MarketplaceOrderScope.history) {
                unawaited(controller.loadMoreHistory());
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final order in controller.visibleOrders) ...[
                  Tooltip(
                    message:
                        'Заказ № ${order.displayNumber} · ${_statusLabel(order.status)} · ${order.customer.name}',
                    child: PosTicketTab(
                      text: '№ ${order.displayNumber}',
                      compact: compact,
                      active: controller.selectedOrder?.id == order.id,
                      onTap:
                          busy ? null : () => controller.selectOrder(order.id),
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 8),
                ],
                if (controller.visibleOrders.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                          controller.loading
                              ? 'Загрузка заказов…'
                              : 'В этом разделе заказов нет',
                          style: const TextStyle(color: Colors.white70))),
                if (controller.historyLoadingMore)
                  const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                TextButton(
                  onPressed: busy ? null : controller.refreshVisibleOrders,
                  child: Text('ЗАКАЗЫ',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 15 : 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2)),
                ),
              ]),
            ),
          ),
        )),
        const SizedBox(width: 12),
        IconButton(
            onPressed: busy ? null : controller.refreshVisibleOrders,
            icon: controller.loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Обновить'),
        IconButton(
            onPressed: controller.actionLoading ? null : onClose,
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Закрыть'),
      ]),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.controller});
  final MarketplaceOrdersController controller;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final scope in MarketplaceOrderScope.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  selected: controller.scope == scope,
                  showCheckmark: false,
                  selectedColor: const Color(0xFFEAF7F1),
                  label: Text(switch (scope) {
                    MarketplaceOrderScope.newOrders =>
                      'Новые · ${controller.newOrders.length}',
                    MarketplaceOrderScope.active =>
                      'В работе · ${controller.activeOrders.length}',
                    MarketplaceOrderScope.history => 'История',
                  }),
                  labelStyle: TextStyle(
                      color: controller.scope == scope
                          ? const Color(0xFF179D72)
                          : const Color(0xFF536074),
                      fontWeight: FontWeight.w600),
                  onSelected: controller.loading || controller.actionLoading
                      ? null
                      : (_) => controller.setScope(scope),
                ),
              ),
            if (controller.selectedOrder != null) ...[
              const SizedBox(width: 12),
              Icon(Icons.circle,
                  size: 8,
                  color: _statusColor(controller.selectedOrder!.status)),
              const SizedBox(width: 6),
              Text(_statusLabel(controller.selectedOrder!.status),
                  style: TextStyle(
                      color: _statusColor(controller.selectedOrder!.status),
                      fontWeight: FontWeight.w600)),
            ],
          ])),
    );
  }
}

class _OrderDetails extends StatefulWidget {
  const _OrderDetails({required this.controller});
  final MarketplaceOrdersController controller;
  @override
  State<_OrderDetails> createState() => _OrderDetailsState();
}

class _OrderDetailsState extends State<_OrderDetails> {
  int? selectedIndex;
  String? selectedOrderId;
  MarketplaceOrdersController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final order = controller.selectedOrder;
    if (order == null) {
      return Center(
          child: controller.loading
              ? const CircularProgressIndicator()
              : Text(
                  switch (controller.scope) {
                    MarketplaceOrderScope.newOrders => 'Новых заказов пока нет',
                    MarketplaceOrderScope.active => 'Заказов в работе пока нет',
                    MarketplaceOrderScope.history => 'История заказов пуста',
                  },
                  style:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 18)));
    }
    if (selectedOrderId != order.id) {
      selectedIndex = null;
      selectedOrderId = order.id;
    }
    final items = order.groupedItems;
    return LayoutBuilder(builder: (context, constraints) {
      final scale = (constraints.maxWidth / 1100).clamp(0.5, 1.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          _ProductsHeader(scale: scale),
          Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('В заказе пока нет товаров'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: items.length < 6 ? 6 : items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => index < items.length
                          ? _GroupedItemCard(
                              item: items[index],
                              scale: scale,
                              selected: selectedIndex == index,
                              onTap: () =>
                                  setState(() => selectedIndex = index),
                            )
                          : Container(
                              height: 52,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14))),
                    )),
        ]),
      );
    });
  }
}

class _ProductsHeader extends StatelessWidget {
  const _ProductsHeader({required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) {
    Widget cell(String label, double width) => SizedBox(
        width: width * scale,
        child: Text(label,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 18)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(width: 65 * scale),
        const Expanded(
            child: Text('Наименование',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18))),
        cell('Цена', 100),
        SizedBox(width: 30 * scale),
        cell('Количество', 170),
        SizedBox(width: 10 * scale),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: cell('Скидка', 80)),
        SizedBox(width: 25 * scale),
        cell('Сумма', 140),
        SizedBox(width: 60 * scale),
      ]),
    );
  }
}

class _MarketplaceFooter extends StatelessWidget {
  const _MarketplaceFooter(
      {required this.controller,
      required this.printingInvoiceOrderId,
      required this.onPrintInvoice,
      required this.onOrders,
      required this.onClose});
  final MarketplaceOrdersController controller;
  final String? printingInvoiceOrderId;
  final ValueChanged<MarketplaceOrder> onPrintInvoice;
  final VoidCallback onOrders;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final order = controller.selectedOrder;
    final busy = controller.loading || controller.actionLoading;
    final canShip = order != null &&
        controller.scope != MarketplaceOrderScope.history &&
        (order.status == 'processing' || order.status == 'partially_shipped') &&
        order.groupedItems.any((item) => item.remainingQuantity > 0);
    final canAccept = order != null &&
        !order.isAccepted &&
        controller.scope == MarketplaceOrderScope.newOrders;
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      final controls = FooterControlsOnly(
        smallAmountText: 'Итого',
        bigAmountText: _formatOrderTotal(order?.displayTotal ?? 0),
        paymentLabel: controller.actionLoading ? 'ПОДОЖДИТЕ' : 'ОТГРУЗИТЬ',
        minusLabel: 'Обновить',
        plusLabel: 'Принять',
        payCardLabel: 'Заказы',
        quickLabel: printingInvoiceOrderId != null ? 'Открытие…' : 'Накладная',
        quickBackgroundColor: const Color(0xFFF9B32C),
        quickForegroundColor: Colors.black,
        paymentBackgroundColor: const Color(0xFF4BCA9B),
        paymentDisabledBackgroundColor:
            const Color.fromARGB(255, 132, 186, 163),
        paymentForegroundColor: Colors.white,
        cancelLabel: 'НАЗАД',
        quickEnabled: !busy && order != null && printingInvoiceOrderId == null,
        onMinus: busy ? null : controller.refreshVisibleOrders,
        onPlus: busy || !canAccept ? null : controller.acceptSelected,
        onPayCard: busy ? null : onOrders,
        onQuick: busy || order == null || printingInvoiceOrderId != null
            ? null
            : () => onPrintInvoice(order),
        onCancel: controller.actionLoading ? null : onClose,
        onPay: busy || !canShip
            ? null
            : () => _confirmAndShip(context, controller),
      );
      final customer = order == null
          ? 'Выберите заказ'
          : [
              order.customer.name.isEmpty
                  ? 'Покупатель не указан'
                  : order.customer.name,
              if (order.customer.phone.isNotEmpty) order.customer.phone,
              order.fulfillmentLabel,
              if (order.deliveryAddress.isNotEmpty) order.deliveryAddress,
              if (order.createdAt != null) _formatOrderDate(order.createdAt!),
            ].join(' · ');
      return Container(
        color: const Color(0xFF2B3440),
        padding: const EdgeInsets.only(left: 16),
        height: compact ? 208 : (constraints.maxWidth < 1200 ? 172 : 182),
        child: compact
            ? Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 16, 0),
                    child: Text(customer,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white))),
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                            width: 600, height: 160, child: controls))),
              ])
            : Row(children: [
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: const Color(0xFF373D46),
                        border: Border.all(color: Colors.white),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              order == null
                                  ? 'Маркетплейс'
                                  : 'Заказ № ${order.displayNumber}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(customer,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ]),
                  ),
                )),
                SizedBox(width: 600, child: controls),
              ]),
      );
    });
  }
}

Future<void> _confirmAndShip(
  BuildContext context,
  MarketplaceOrdersController controller,
) async {
  final orderId = controller.selectedOrder?.id;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Подтверждение отгрузки'),
      content: const Text('Отгрузить все оставшиеся позиции заказа?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Отгрузить'),
        ),
      ],
    ),
  );
  if (confirmed != true ||
      !context.mounted ||
      controller.selectedOrder?.id != orderId ||
      controller.loading) {
    return;
  }

  final result = await controller.shipSelectedOrder();
  if (!context.mounted || result == null) return;
  final saleSuffix = result.saleCreated && result.saleId.isNotEmpty
      ? ' Продажа создана: ${result.saleId}'
      : '';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Заказ полностью отгружен.$saleSuffix')),
  );
}

class _GroupedItemCard extends StatelessWidget {
  const _GroupedItemCard(
      {required this.item,
      required this.selected,
      required this.onTap,
      required this.scale});
  final double scale;
  final MarketplaceGroupedItem item;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final subtotal = item.unitPrice * item.requestedQuantity;
    final discount = subtotal > 0
        ? ((subtotal - item.lineTotal) / subtotal * 100).clamp(0, 100)
        : 0.0;
    const priceStyle = TextStyle(
        fontFamily: 'NotoSans',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0.27);
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      borderRadius: BorderRadius.circular(14),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: selected ? const Color(0xFFD3D3D3) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              CartProductImage(imageUrl: item.imageUrl),
              SizedBox(width: 15 * scale),
              Expanded(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.name.isEmpty ? item.productId : item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    if (item.shippedQuantity > 0)
                      Text(
                          'Отгружено: ${_fmt(item.shippedQuantity)} · Осталось: ${_fmt(item.remainingQuantity)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF258808), fontSize: 12)),
                  ])),
              SizedBox(
                  width: 130 * scale,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(money(item.unitPrice),
                          textAlign: TextAlign.right, style: priceStyle))),
              SizedBox(width: 16 * scale),
              SizedBox(
                  width: 170 * scale,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 90,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                            color: selected ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Text(_fmt(item.requestedQuantity),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.15)),
                      ))),
              SizedBox(width: 10 * scale),
              SizedBox(
                  width: 60 * scale,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 50, minHeight: 29.397),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: discount > 0
                            ? const Color(0xFFCBE9C5)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14.3445),
                        border: Border.all(
                            color: discount > 0
                                ? const Color(0xFFCBE9C5)
                                : const Color(0xFFE5E7EB))),
                    child: Text('${_fmt(discount.round())}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: discount > 0
                                ? const Color(0xFF258808)
                                : const Color(0xFF9CA3AF),
                            fontFamily: 'NotoSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            letterSpacing: 0.34)),
                  )),
              SizedBox(width: 16 * scale),
              SizedBox(
                  width: 150 * scale,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(money(item.lineTotal),
                          key: ValueKey(
                              'line-total-${item.productId}-${item.name}'),
                          textAlign: TextAlign.right,
                          style: priceStyle))),
              SizedBox(width: 48 * scale),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.text, required this.onRefresh});

  final String text;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: const Color(0xFFFFF1F2),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFBE123C), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF9F1239),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

String _fmt(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toString();
}

String _formatOrderDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _formatOrderTotal(num value) {
  final fixed =
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  if (parts.length > 1) buffer.write(',${parts[1]}');
  return '$buffer ₸';
}

String _statusLabel(String status) => switch (status) {
      'awaiting_confirmation' => 'Ожидает приёма',
      'processing' => 'В сборке',
      'partially_shipped' => 'Частично отгружен',
      'shipped' => 'Отгружен',
      'delivered' => 'Доставлен',
      'completed' => 'Завершён',
      'cancelled' => 'Отменён',
      'partially_cancelled' => 'Частично отменён',
      _ => 'Статус не указан',
    };
Color _statusColor(String status) => switch (status) {
      'awaiting_confirmation' => const Color(0xFFB45309),
      'processing' => const Color(0xFF2563EB),
      'partially_shipped' || 'partially_cancelled' => const Color(0xFFB45309),
      'shipped' || 'delivered' || 'completed' => const Color(0xFF179D72),
      'cancelled' => const Color(0xFFBE123C),
      _ => const Color(0xFF536074),
    };
