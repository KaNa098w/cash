import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
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
      color: const Color(0xFFF7F8FA),
      child: SizedBox(
        width: size.width,
        height: size.height,
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
                  if (_controller.error != null)
                    _ErrorStrip(
                      text: _controller.error!,
                      onRefresh: _controller.refreshVisibleOrders,
                    ),
                  Expanded(
                    child: _WideBody(
                      controller: _controller,
                      printingInvoiceOrderId: _printingInvoiceOrderId,
                      onPrintInvoice: _printInvoice,
                    ),
                  ),
                ],
              );
            },
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
      final doc = await buildInvoicePdf(
        InvoicePdfData(
          money: _formatOrderTotal,
          invoiceDate: order.createdAt ?? DateTime.now(),
          invoiceNumber: order.displayNumber,
          cashierName: cashierName,
          storeName: storeName,
          buyerName: order.customer.name,
          items: order.groupedItems
              .map(
                (item) => ReceiptPdfItem(
                  name: item.name.isEmpty ? item.productId : item.name,
                  quantity: item.requestedQuantity,
                  baseUnitPrice: item.unitPrice,
                  unitPrice: item.unitPrice,
                  lineTotal: item.total > 0
                      ? item.total
                      : item.unitPrice * item.requestedQuantity,
                ),
              )
              .toList(),
          total: order.displayTotal,
          paymentMethodLabel: 'Онлайн-заказ',
        ),
      );
      await PrintService().printPdfBytesSilently(
        await doc.save(),
        printerName: auth.invoicePrinterName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Накладная отправлена на печать')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка печати накладной: $e')),
      );
    } finally {
      if (mounted) setState(() => _printingInvoiceOrderId = null);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClose});

  final MarketplaceOrdersController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final scopes = <Widget>[
          _ScopeButton(
            text: 'Новые',
            count: controller.newOrders.length,
            active: controller.scope == MarketplaceOrderScope.newOrders,
            onTap: () => controller.setScope(MarketplaceOrderScope.newOrders),
          ),
          const SizedBox(width: 8),
          _ScopeButton(
            text: 'В работе',
            count: controller.activeOrders.length,
            active: controller.scope == MarketplaceOrderScope.active,
            onTap: () => controller.setScope(MarketplaceOrderScope.active),
          ),
          const SizedBox(width: 8),
          _ScopeButton(
            text: 'История',
            count: controller.historyOrders.length,
            active: controller.scope == MarketplaceOrderScope.history,
            onTap: () => controller.setScope(MarketplaceOrderScope.history),
          ),
        ];
        final utilityButtons = <Widget>[
          IconButton(
            onPressed:
                controller.loading ? null : controller.refreshVisibleOrders,
            icon: controller.loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Обновить',
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Закрыть',
          ),
        ];

        return Container(
          height: compact ? 124 : 76,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
          color: const Color(0xFF202733),
          child: compact
              ? Column(
                  children: [
                    SizedBox(
                      height: 64,
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined,
                              color: Colors.white, size: 26),
                          const SizedBox(width: 12),
                          const Expanded(child: _HeaderTitle()),
                          ...utilityButtons,
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: scopes),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 14),
                    const Expanded(child: _HeaderTitle()),
                    ...scopes,
                    const SizedBox(width: 10),
                    ...utilityButtons,
                  ],
                ),
        );
      },
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Онлайн заказы',
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.text,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String text;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFF3A4352),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
              text,
              style: TextStyle(
                color: active ? const Color(0xFF111827) : Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFFEFF6FF)
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? const Color(0xFF1D4ED8) : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideBody extends StatelessWidget {
  const _WideBody({
    required this.controller,
    required this.printingInvoiceOrderId,
    required this.onPrintInvoice,
  });

  final MarketplaceOrdersController controller;
  final String? printingInvoiceOrderId;
  final ValueChanged<MarketplaceOrder> onPrintInvoice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = constraints.maxWidth < 900 ? 280.0 : 360.0;
        return Row(
          children: [
            SizedBox(
              width: listWidth,
              child: _OrdersList(controller: controller),
            ),
            const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: _OrderDetails(
                controller: controller,
                printingInvoiceOrderId: printingInvoiceOrderId,
                onPrintInvoice: onPrintInvoice,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.controller});

  final MarketplaceOrdersController controller;

  @override
  Widget build(BuildContext context) {
    final orders = controller.visibleOrders;
    if (orders.isEmpty && controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refreshVisibleOrders,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'Заказов нет',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final showHistoryLoader =
        controller.scope == MarketplaceOrderScope.history &&
            controller.historyLoadingMore;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 240 &&
            controller.scope == MarketplaceOrderScope.history) {
          unawaited(controller.loadMoreHistory());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: controller.refreshVisibleOrders,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          itemCount: orders.length + (showHistoryLoader ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == orders.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final order = orders[index];
            final active = controller.selectedOrder?.id == order.id;
            return _OrderTile(
              order: order,
              active: active,
              showHistoryInfo:
                  controller.scope == MarketplaceOrderScope.history,
              onTap: () => controller.selectOrder(order.id),
            );
          },
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.active,
    required this.showHistoryInfo,
    required this.onTap,
  });

  final MarketplaceOrder order;
  final bool active;
  final bool showHistoryInfo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(order.status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Заказ № ${order.displayNumber}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusPill(text: _statusLabel(order.status), color: accent),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              order.customer.name.isEmpty ? 'Покупатель' : order.customer.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (order.customer.phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                order.customer.phone,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (showHistoryInfo) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (order.createdAt != null)
                    Expanded(
                      child: Text(
                        _formatOrderDate(order.createdAt!),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (order.displayTotal > 0)
                    Text(
                      _formatOrderTotal(order.displayTotal),
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({
    required this.controller,
    required this.printingInvoiceOrderId,
    required this.onPrintInvoice,
  });

  final MarketplaceOrdersController controller;
  final String? printingInvoiceOrderId;
  final ValueChanged<MarketplaceOrder> onPrintInvoice;

  @override
  Widget build(BuildContext context) {
    final order = controller.selectedOrder;
    if (order == null) {
      return const Center(
        child: Text(
          'Выберите заказ',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF172033), Color(0xFF263750)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: _OrderActionsHeader(
            order: order,
            controller: controller,
            printingInvoiceOrderId: printingInvoiceOrderId,
            onPrintInvoice: onPrintInvoice,
            onShip: () => _confirmAndShip(context, controller),
          ),
        ),
        _OrderSummary(order: order),
        Expanded(
          child: order.groupedItems.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 44,
                          color: Color(0xFF94A3B8),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Backend не передал позиции этого заказа',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                  itemCount: order.groupedItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _GroupedItemCard(
                      item: order.groupedItems[index],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmAndShip(
    BuildContext context,
    MarketplaceOrdersController controller,
  ) async {
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
    if (confirmed != true || !context.mounted) return;

    final result = await controller.shipSelectedOrder();
    if (!context.mounted || result == null) return;
    final saleSuffix = result.saleCreated && result.saleId.isNotEmpty
        ? ' Продажа создана: ${result.saleId}'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Заказ полностью отгружен.$saleSuffix')),
    );
  }
}

class _OrderActionsHeader extends StatelessWidget {
  const _OrderActionsHeader({
    required this.order,
    required this.controller,
    required this.printingInvoiceOrderId,
    required this.onPrintInvoice,
    required this.onShip,
  });

  final MarketplaceOrder order;
  final MarketplaceOrdersController controller;
  final String? printingInvoiceOrderId;
  final ValueChanged<MarketplaceOrder> onPrintInvoice;
  final VoidCallback onShip;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (controller.scope == MarketplaceOrderScope.active)
        OutlinedButton.icon(
          onPressed: printingInvoiceOrderId == null
              ? () => onPrintInvoice(order)
              : null,
          icon: printingInvoiceOrderId == order.id
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined),
          label: const Text('Распечатать накладную'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            minimumSize: const Size(210, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      if (!order.isAccepted &&
          controller.scope == MarketplaceOrderScope.newOrders)
        FilledButton.icon(
          onPressed:
              controller.actionLoading ? null : controller.acceptSelected,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Принять'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            minimumSize: const Size(128, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      if (controller.scope != MarketplaceOrderScope.history &&
          (order.status == 'processing' || order.status == 'partially_shipped'))
        FilledButton.icon(
          onPressed: controller.actionLoading ? null : onShip,
          icon: controller.actionLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.local_shipping_outlined),
          label: const Text('Отгрузить заказ'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            minimumSize: const Size(170, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Заказ № ${order.displayNumber}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Подробная информация и состав заказа',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StatusPill(
              text: _statusLabel(order.status),
              color: _statusColor(order.status),
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 10,
              children: actions,
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final MarketplaceOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FA),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryTile(
                icon: Icons.person_outline,
                label: 'Покупатель',
                value: order.customer.name.isEmpty
                    ? 'Не указан'
                    : order.customer.name,
                detail: order.customer.phone,
              ),
              _SummaryTile(
                icon: order.fulfillmentLabel == 'Самовывоз'
                    ? Icons.storefront_outlined
                    : Icons.local_shipping_outlined,
                label: 'Получение',
                value: order.fulfillmentLabel,
                detail: order.deliveryAddress,
                width: 432,
              ),
              _SummaryTile(
                icon: Icons.schedule_outlined,
                label: 'Дата заказа',
                value: order.createdAt == null
                    ? 'Не указана'
                    : _formatOrderDate(order.createdAt!),
              ),
              _SummaryTile(
                icon: Icons.payments_outlined,
                label: 'Итого',
                value: order.displayTotal > 0
                    ? _formatOrderTotal(order.displayTotal)
                    : 'Не указан',
                emphasized: true,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.shopping_bag_outlined,
                size: 20,
                color: Color(0xFF334155),
              ),
              const SizedBox(width: 8),
              Text(
                'Состав заказа · ${order.groupedItems.length}',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    this.detail = '',
    this.emphasized = false,
    this.width = 210,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool emphasized;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: emphasized
                  ? const Color(0xFFDBEAFE)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: emphasized
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF0F172A),
                    fontSize: emphasized ? 17 : 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedItemCard extends StatelessWidget {
  const _GroupedItemCard({required this.item});

  final MarketplaceGroupedItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _OrderProductImage(url: item.imageUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name.isEmpty ? item.productId : item.name,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                if (item.sku.isNotEmpty)
                  Text(
                    'Артикул: ${item.sku}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ItemMetric(
                      label: 'Количество',
                      value: _fmt(item.requestedQuantity),
                    ),
                    if (item.shippedQuantity > 0)
                      _ItemMetric(
                        label: 'Отгружено',
                        value: _fmt(item.shippedQuantity),
                        color: const Color(0xFF16A34A),
                      ),
                    if (item.remainingQuantity > 0)
                      _ItemMetric(
                        label: 'Осталось',
                        value: _fmt(item.remainingQuantity),
                        color: const Color(0xFFB45309),
                      ),
                    if (item.unitPrice > 0)
                      _ItemMetric(
                        label: 'Цена',
                        value: _formatOrderTotal(item.unitPrice),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (item.total > 0) ...[
            const SizedBox(width: 14),
            Text(
              _formatOrderTotal(item.total),
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemMetric extends StatelessWidget {
  const _ItemMetric({
    required this.label,
    required this.value,
    this.color = const Color(0xFF475569),
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _OrderProductImage extends StatelessWidget {
  const _OrderProductImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url.trim());
    return Container(
      width: 84,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: uri == null || !uri.isAbsolute
          ? const _OrderNoPhoto()
          : Image.network(
              uri.toString(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _OrderNoPhoto(),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
    );
  }
}

class _OrderNoPhoto extends StatelessWidget {
  const _OrderNoPhoto();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 25,
            color: Color(0xFF94A3B8),
          ),
          SizedBox(height: 4),
          Text(
            'Фото не передано',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
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

String _statusLabel(String status) {
  switch (status) {
    case 'awaiting_confirmation':
      return 'Новый';
    case 'processing':
      return 'В работе';
    case 'partially_shipped':
      return 'Частично';
    case 'shipped':
      return 'Отгружен';
    case 'delivered':
      return 'Доставлен';
    case 'completed':
      return 'Завершён';
    case 'cancelled':
      return 'Отменён';
    case 'partially_cancelled':
      return 'Частично отменён';
    default:
      return status.isEmpty ? 'Статус' : status;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'awaiting_confirmation':
      return const Color(0xFF0F766E);
    case 'processing':
      return const Color(0xFF2563EB);
    case 'partially_shipped':
      return const Color(0xFFB45309);
    case 'shipped':
    case 'delivered':
    case 'completed':
      return const Color(0xFF16A34A);
    case 'cancelled':
    case 'partially_cancelled':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF475569);
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
