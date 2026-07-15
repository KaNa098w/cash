import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:leemon_app/core/models/marketplace_order_models.dart';
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
    final compact = size.width < 1080;

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
                      onRefresh: _controller.refreshAll,
                    ),
                  Expanded(
                    child: compact
                        ? _CompactBody(controller: _controller)
                        : _WideBody(controller: _controller),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClose});

  final MarketplaceOrdersController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      color: const Color(0xFF202733),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_outlined,
              color: Colors.white, size: 28),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Онлайн заказы',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
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
          const SizedBox(width: 10),
          IconButton(
            onPressed: controller.loading ? null : controller.refreshAll,
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
        ],
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
  const _WideBody({required this.controller});

  final MarketplaceOrdersController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: _OrdersList(controller: controller),
        ),
        const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
        Expanded(child: _OrderDetails(controller: controller)),
      ],
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({required this.controller});

  final MarketplaceOrdersController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 230, child: _OrdersList(controller: controller)),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(child: _OrderDetails(controller: controller)),
      ],
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
      return const Center(
        child: Text(
          'Заказов нет',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final order = orders[index];
        final active = controller.selectedOrder?.id == order.id;
        return _OrderTile(
          order: order,
          active: active,
          onTap: () => controller.selectOrder(order.id),
        );
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.active,
    required this.onTap,
  });

  final MarketplaceOrder order;
  final bool active;
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
          ],
        ),
      ),
    );
  }
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({required this.controller});

  final MarketplaceOrdersController controller;

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
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Заказ № ${order.displayNumber}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (order.customer.name.isNotEmpty) order.customer.name,
                        if (order.customer.phone.isNotEmpty)
                          order.customer.phone,
                      ].join('  |  '),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                text: _statusLabel(order.status),
                color: _statusColor(order.status),
              ),
              const SizedBox(width: 12),
              if (!order.isAccepted &&
                  controller.scope == MarketplaceOrderScope.newOrders)
                FilledButton.icon(
                  onPressed: controller.actionLoading
                      ? null
                      : controller.acceptSelected,
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
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: order.groupedItems.isEmpty
              ? const Center(
                  child: Text(
                    'Позиции появятся после загрузки деталей заказа',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: order.groupedItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _GroupedItemCard(
                      item: order.groupedItems[index],
                      enabled: order.isAccepted &&
                          !order.isShipped &&
                          !controller.actionLoading,
                      onShip: (qty) async {
                        final result = await controller.shipSelectedItem(
                          item: order.groupedItems[index],
                          quantity: qty,
                        );
                        if (!context.mounted || result == null) return;
                        if (result.saleCreated) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Заказ отгружен. Продажа создана: ${result.saleId}',
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GroupedItemCard extends StatefulWidget {
  const _GroupedItemCard({
    required this.item,
    required this.enabled,
    required this.onShip,
  });

  final MarketplaceGroupedItem item;
  final bool enabled;
  final Future<void> Function(num quantity) onShip;

  @override
  State<_GroupedItemCard> createState() => _GroupedItemCardState();
}

class _GroupedItemCardState extends State<_GroupedItemCard> {
  late num _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = _defaultShipmentQuantity(widget.item.remainingQuantity);
  }

  @override
  void didUpdateWidget(covariant _GroupedItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.productId != widget.item.productId ||
        oldWidget.item.remainingQuantity != widget.item.remainingQuantity) {
      _quantity = _defaultShipmentQuantity(widget.item.remainingQuantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canShip = widget.enabled && item.remainingQuantity > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                Text(
                  [
                    if (item.sku.isNotEmpty) 'SKU ${item.sku}',
                    'Запрошено ${_fmt(item.requestedQuantity)}',
                    'Отгружено ${_fmt(item.shippedQuantity)}',
                    'Осталось ${_fmt(item.remainingQuantity)}',
                  ].join('  |  '),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _QtyStepper(
            value: _quantity,
            max: item.remainingQuantity,
            enabled: canShip,
            onChanged: (value) => setState(() => _quantity = value),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: canShip ? () => widget.onShip(_quantity) : null,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Отгрузить'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E7EB),
              disabledForegroundColor: const Color(0xFF94A3B8),
              minimumSize: const Size(134, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
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
            'Нет фото',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final num value;
  final num max;
  final bool enabled;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
            tooltip: 'Меньше',
          ),
          SizedBox(
            width: 46,
            child: Text(
              _fmt(value),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed:
                enabled && value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
            tooltip: 'Больше',
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
      return const Color(0xFF16A34A);
    default:
      return const Color(0xFF475569);
  }
}

String _fmt(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toString();
}

num _defaultShipmentQuantity(num remaining) {
  if (remaining <= 0) return 0;
  return remaining < 1 ? remaining : 1;
}
