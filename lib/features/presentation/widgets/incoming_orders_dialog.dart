import 'package:leemon_app/core/models/sale_model.dart' as sale;
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sale_items_box.dart';
import 'dart:async';

import 'footer_panels_widget.dart';
import 'top_bar.dart' show PosTicketTab, PosMenuTab;
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
  bool _showHistory = false;
  bool _openingMarketplace = true;
  bool _initialSelectionPending = true;
  int _viewRevision = 0;

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
          force: true,
        );
        if (!mounted) return;
        if (_initialSelectionPending) {
          final newest = _controller.latestNewOrder;
          if (newest != null) {
            await _openOrder(newest);
          } else {
            setState(() => _showHistory = true);
          }
        }
        if (mounted) setState(() => _openingMarketplace = false);
      }());
    });
  }

  Future<void> _openOrder(MarketplaceOrder order) async {
    _initialSelectionPending = false;
    final revision = ++_viewRevision;
    await _controller.selectOrder(order.id, fallback: order);
    if (mounted &&
        revision == _viewRevision &&
        _controller.selectedOrder?.id == order.id) {
      setState(() => _showHistory = false);
    }
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
                      showHistory: _showHistory,
                      onHistory: () => setState(() {
                        _initialSelectionPending = false;
                        _viewRevision++;
                        _showHistory = true;
                      }),
                      onOrder: _openOrder,
                    ),
                    if (_controller.error != null)
                      _ErrorStrip(
                        text: _controller.error!,
                        onRefresh: _controller.refreshVisibleOrders,
                      ),
                    Expanded(
                      child: _openingMarketplace
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF15966A)))
                          : IndexedStack(
                              index: _showHistory ? 0 : 1,
                              children: [
                                  _MarketplaceHistory(controller: _controller),
                                  _OrderDetails(controller: _controller),
                                ]),
                    ),
                    if (!_showHistory && !_openingMarketplace)
                      _MarketplaceFooter(
                        controller: _controller,
                        printingInvoiceOrderId: _printingInvoiceOrderId,
                        onPrintInvoice: _printInvoice,
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
  const _Header(
      {required this.controller,
      required this.onClose,
      required this.showHistory,
      required this.onHistory,
      required this.onOrder});
  final bool showHistory;
  final VoidCallback onHistory;
  final ValueChanged<MarketplaceOrder> onOrder;
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
              if (notification.metrics.extentAfter < 240) {
                unawaited(controller.loadMoreHistory());
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                PosMenuTab(
                    text: 'История',
                    icon: 'assets/svg/history.svg',
                    active: widget.showHistory,
                    compact: compact,
                    onTap: widget.onHistory),
                SizedBox(width: compact ? 12 : 8),
                for (final order in controller.topBarOrders) ...[
                  Tooltip(
                    message:
                        'Заказ № ${order.displayNumber} · ${_statusLabel(order.status)} · ${order.customer.name}',
                    child: PosTicketTab(
                      text: '№ ${order.displayNumber}',
                      statusDotColor: _orderDotColor(order.status),
                      compact: compact,
                      active: !widget.showHistory &&
                          controller.selectedOrder?.id == order.id,
                      onTap: busy ? null : () => widget.onOrder(order),
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 8),
                ],
                if (controller.topBarOrders.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                          controller.loading
                              ? 'Загрузка заказов…'
                              : 'Нет активных заказов',
                          style: const TextStyle(color: Colors.white70))),
                if (controller.historyLoadingMore)
                  const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
            ),
          ),
        )),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Обновить заказы',
          onPressed: busy ? null : controller.refreshVisibleOrders,
          style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38),
          icon: controller.loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.refresh_rounded, size: 26),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: controller.actionLoading ? null : onClose,
          icon: const Icon(Icons.logout_rounded, size: 21),
          label: const Text('Выйти',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
              minimumSize: const Size(124, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: const Color(0xFFCB5B52),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]),
    );
  }
}

class _MarketplaceHistory extends StatefulWidget {
  const _MarketplaceHistory({required this.controller});
  final MarketplaceOrdersController controller;
  @override
  State<_MarketplaceHistory> createState() => _MarketplaceHistoryState();
}

class _MarketplaceHistoryState extends State<_MarketplaceHistory> {
  final search = TextEditingController();
  final scroll = ScrollController();
  Timer? debounce;
  bool searching = false;
  String query = '';
  String? expandedOrderId;
  MarketplaceOrder? expandedOrder;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.hasClients &&
          scroll.position.extentAfter < 300 &&
          query.isEmpty) {
        unawaited(widget.controller.loadMoreHistory());
      }
    });
  }

  void changeQuery(String value) {
    setState(
        () => query = value.trim().toLowerCase().replaceAll('№', '').trim());
    debounce?.cancel();
    if (query.isNotEmpty) {
      debounce = Timer(const Duration(milliseconds: 350), searchHistory);
    }
  }

  Future<void> searchHistory() async {
    if (searching || !mounted || query.isEmpty) return;
    setState(() => searching = true);
    try {
      while (mounted &&
          query.isNotEmpty &&
          widget.controller.historyHasMore &&
          !widget.controller.loading) {
        await widget.controller.loadMoreHistory();
        if (widget.controller.error != null) break;
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> toggleOrder(MarketplaceOrder order) async {
    if (expandedOrderId == order.id) {
      setState(() {
        expandedOrderId = null;
        expandedOrder = null;
      });
      return;
    }
    setState(() {
      expandedOrderId = order.id;
      expandedOrder = null;
    });
    await widget.controller.selectOrder(order.id);
    if (mounted && expandedOrderId == order.id) {
      setState(() => expandedOrder =
          widget.controller.selectedOrder?.id == order.id
              ? widget.controller.selectedOrder
              : order);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final orders = controller.shippedOrders
        .where((order) =>
            query.isEmpty || order.displayNumber.toLowerCase().contains(query))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: search,
              onChanged: changeQuery,
              onSubmitted: (_) => searchHistory(),
              decoration: InputDecoration(
                  hintText: 'Поиск по номеру заказа',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Color(0xFF456B5A)),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить поиск',
                          onPressed: () {
                            search.clear();
                            changeQuery('');
                          },
                          icon: const Icon(Icons.close_rounded)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFD7DED9))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFD7DED9))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF456B5A), width: 1.5))),
            ),
            const SizedBox(height: 10),
            Text(
                searching
                    ? 'Ищем в истории заказов…'
                    : query.isNotEmpty
                        ? 'Найдено заказов: ${orders.length}'
                        : 'Заказов: ${orders.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ])),
      if (searching || controller.historyLoadingMore)
        const LinearProgressIndicator(minHeight: 2, color: Color(0xFF15966A)),
      Expanded(
          child: controller.loading && orders.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF15966A)))
              : orders.isEmpty
                  ? Center(
                      child: Text(
                          query.isEmpty
                              ? 'Заказов пока нет'
                              : searching
                                  ? 'Поиск в истории…'
                                  : 'Заказ с таким номером не найден',
                          style: const TextStyle(
                              fontSize: 16, color: Color(0xFF64748B))))
                  : LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxWidth < 850;
                      Widget cell(String text, int flex,
                              {Color? color, bool bold = false}) =>
                          Expanded(
                              flex: flex,
                              child: Text(text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: bold
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color:
                                          color ?? const Color(0xFF334155))));
                      return Column(children: [
                        if (!compact)
                          Padding(
                              padding: const EdgeInsets.fromLTRB(42, 4, 42, 12),
                              child: Row(children: [
                                cell('Номер', 18),
                                cell('Дата', 23),
                                cell('Статус', 23),
                                cell('Покупатель', 23),
                                cell('Сумма', 18),
                                const SizedBox(width: 26)
                              ])),
                        Expanded(
                            child: Scrollbar(
                                controller: scroll,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: scroll,
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                  itemCount: orders.length +
                                      (controller.historyHasMore &&
                                              query.isEmpty
                                          ? 1
                                          : 0),
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 14),
                                  itemBuilder: (context, index) {
                                    if (index == orders.length) {
                                      return Center(
                                          child: TextButton(
                                              onPressed: controller
                                                      .historyLoadingMore
                                                  ? null
                                                  : controller.loadMoreHistory,
                                              child:
                                                  const Text('Показать ещё')));
                                    }
                                    final order = orders[index];
                                    final color = _statusColor(order.status);
                                    final status = Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                            color:
                                                color.withValues(alpha: 0.09),
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: Text(_statusLabel(order.status),
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: color,
                                                fontWeight: FontWeight.w600)));
                                    return Material(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        clipBehavior: Clip.antiAlias,
                                        child: Column(children: [
                                          InkWell(
                                            onTap: controller.loading ||
                                                    controller.actionLoading
                                                ? null
                                                : () => toggleOrder(order),
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 22,
                                                        vertical: 18),
                                                child: compact
                                                    ? Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                            Row(children: [
                                                              Expanded(
                                                                  child: _OrderNumber(
                                                                      order:
                                                                          order,
                                                                      fontSize:
                                                                          18)),
                                                              Icon(
                                                                  expandedOrderId ==
                                                                          order
                                                                              .id
                                                                      ? Icons
                                                                          .expand_less_rounded
                                                                      : Icons
                                                                          .expand_more_rounded,
                                                                  color: const Color(
                                                                      0xFF64748B))
                                                            ]),
                                                            const SizedBox(
                                                                height: 10),
                                                            Wrap(
                                                                spacing: 12,
                                                                runSpacing: 8,
                                                                crossAxisAlignment:
                                                                    WrapCrossAlignment
                                                                        .center,
                                                                children: [
                                                                  status,
                                                                  Text(
                                                                      _formatOrderTotal(
                                                                          order
                                                                              .displayTotal),
                                                                      style: const TextStyle(
                                                                          fontSize:
                                                                              17,
                                                                          fontWeight:
                                                                              FontWeight.w700))
                                                                ]),
                                                            const SizedBox(
                                                                height: 10),
                                                            Text(
                                                                [
                                                                  if (order
                                                                          .createdAt !=
                                                                      null)
                                                                    _formatOrderDate(
                                                                        order
                                                                            .createdAt!),
                                                                  if (order
                                                                      .customer
                                                                      .name
                                                                      .isNotEmpty)
                                                                    order
                                                                        .customer
                                                                        .name
                                                                ].join(' · '),
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    color: Color(
                                                                        0xFF64748B))),
                                                          ])
                                                    : Row(children: [
                                                        Expanded(
                                                            flex: 18,
                                                            child: _OrderNumber(
                                                                order: order)),
                                                        cell(
                                                            order.createdAt ==
                                                                    null
                                                                ? '—'
                                                                : _formatOrderDate(
                                                                    order
                                                                        .createdAt!),
                                                            23),
                                                        Expanded(
                                                            flex: 23,
                                                            child: Align(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: status)),
                                                        cell(
                                                            order.customer.name
                                                                    .isEmpty
                                                                ? 'Покупатель не указан'
                                                                : order.customer
                                                                    .name,
                                                            23),
                                                        cell(
                                                            _formatOrderTotal(order
                                                                .displayTotal),
                                                            18,
                                                            bold: true),
                                                        Icon(
                                                            expandedOrderId ==
                                                                    order.id
                                                                ? Icons
                                                                    .expand_less_rounded
                                                                : Icons
                                                                    .expand_more_rounded,
                                                            size: 26,
                                                            color: const Color(
                                                                0xFF64748B)),
                                                      ])),
                                          ),
                                          if (expandedOrderId == order.id)
                                            expandedOrder == null
                                                ? const Padding(
                                                    padding: EdgeInsets.all(24),
                                                    child:
                                                        CircularProgressIndicator(
                                                            color: Color(
                                                                0xFF15966A)))
                                                : _OrderHistoryDetails(
                                                    order: expandedOrder!),
                                        ]));
                                  },
                                ))),
                      ]);
                    })),
    ]);
  }
}

class _OrderNumber extends StatelessWidget {
  const _OrderNumber({required this.order, this.fontSize = 15});
  final MarketplaceOrder order;
  final double fontSize;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Text('№ ${order.displayNumber}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155)))),
        if (_orderDotColor(order.status) != null) ...[
          const SizedBox(width: 7),
          Icon(Icons.circle, size: 7, color: _orderDotColor(order.status)),
        ],
      ]);
}

class _OrderHistoryDetails extends StatelessWidget {
  const _OrderHistoryDetails({required this.order});
  final MarketplaceOrder order;

  sale.SaleItemModel previewItem(MarketplaceGroupedItem item) {
    final subtotal = item.unitPrice * item.requestedQuantity;
    final discount =
        (subtotal - item.lineTotal).clamp(0, double.infinity).toDouble();
    return sale.SaleItemModel(
      id: item.productId,
      saleId: order.id,
      productId: item.productId,
      quantity: item.requestedQuantity.toDouble(),
      price: item.unitPrice.toDouble(),
      basePrice: item.unitPrice.toDouble(),
      totalPrice: item.lineTotal.toDouble(),
      totalDiscount: discount,
      discountPercent: subtotal > 0
          ? (discount / subtotal * 100).clamp(0, 100).toDouble()
          : 0,
      product: sale.ProductModel.fromJson({
        'id': item.productId,
        'name': item.name.isEmpty ? item.productId : item.name,
        'barcode': item.sku
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(16)),
              child: LayoutBuilder(builder: (context, constraints) {
                final columnWidth = constraints.maxWidth < 600
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 20) / 2;
                Widget info(String label, String value, IconData icon) =>
                    SizedBox(
                        width: columnWidth,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon,
                                  size: 18, color: const Color(0xFF6B7280)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(label,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6B7280))),
                                    const SizedBox(height: 3),
                                    SelectableText(value,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4)),
                                  ])),
                            ]));
                return Wrap(spacing: 20, runSpacing: 14, children: [
                  info(
                      'Телефон',
                      order.customer.phone.isEmpty
                          ? 'Не указан'
                          : order.customer.phone,
                      Icons.phone_outlined),
                  info('Получение', order.fulfillmentLabel,
                      Icons.local_shipping_outlined),
                  if (order.deliveryAddress.isNotEmpty)
                    info('Адрес', order.deliveryAddress,
                        Icons.location_on_outlined),
                ]);
              })),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final width =
                constraints.maxWidth < 680 ? 680.0 : constraints.maxWidth;
            return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                    width: width,
                    child: SaleItemsBox(
                      items: order.groupedItems.map(previewItem).toList(),
                      picks: const {},
                      selectable: false,
                      onToggleItem: (_, __) {},
                      onQtyChanged: (_, __) {},
                      refundedQtyOf: (_) => 0,
                      availableQtyOf: (_) => 0,
                    )));
          }),
          const SizedBox(height: 14),
          Text('Итого: ${_formatOrderTotal(order.displayTotal)}',
              textAlign: TextAlign.right,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _OrderStatusCard extends StatelessWidget {
  const _OrderStatusCard({required this.order});
  final MarketplaceOrder order;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(order.status);
    final icon = switch (order.status) {
      'awaiting_confirmation' => Icons.schedule_rounded,
      'processing' => Icons.inventory_2_outlined,
      'partially_shipped' => Icons.local_shipping_outlined,
      'shipped' => Icons.local_shipping_rounded,
      'delivered' || 'completed' => Icons.check_circle_outline_rounded,
      'cancelled' || 'partially_cancelled' => Icons.cancel_outlined,
      _ => Icons.info_outline_rounded,
    };
    final description = switch (order.status) {
      'awaiting_confirmation' => 'Примите заказ, чтобы начать сборку.',
      'processing' => 'Заказ принят. Подготовьте товары к отгрузке.',
      'partially_shipped' =>
        'Часть товаров отгружена. Осталось подготовить остальные позиции.',
      'shipped' => 'Товары отгружены. Повторная отгрузка не требуется.',
      'delivered' => 'Заказ доставлен покупателю.',
      'completed' => 'Работа с заказом завершена.',
      'cancelled' => 'Заказ отменён. Приём и отгрузка недоступны.',
      'partially_cancelled' =>
        'Часть заказа отменена. Проверьте состав и количество товаров.',
      _ => 'Обновите заказ, чтобы проверить его текущее состояние.',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_statusLabel(order.status),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text('Статус заказа № ${order.displayNumber}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B))),
              ]),
          const SizedBox(height: 3),
          Text(description,
              style: const TextStyle(
                  fontSize: 12, height: 1.3, color: Color(0xFF64748B))),
        ])),
      ]),
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
              : const Text('Заказов пока нет',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 18)));
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
          _OrderStatusCard(order: order),
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
      required this.onClose});
  final MarketplaceOrdersController controller;
  final String? printingInvoiceOrderId;
  final ValueChanged<MarketplaceOrder> onPrintInvoice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final order = controller.selectedOrder;
    final busy = controller.loading || controller.actionLoading;
    final canShip = order != null &&
        (order.status == 'processing' || order.status == 'partially_shipped') &&
        order.groupedItems.any((item) => item.remainingQuantity > 0);
    final canAccept = order != null &&
        !controller.selectedOrderAcceptedByThisPos &&
        order.acceptableItems.isNotEmpty &&
        (order.status == 'awaiting_confirmation' ||
            order.status == 'processing');
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      final controls = FooterControlsOnly(
        smallAmountText: 'Итого',
        bigAmountText: _formatOrderTotal(order?.displayTotal ?? 0),
        showAdjustmentButtons: false,
        showPayCardButton: false,
        paymentLabel: controller.actionLoading
            ? 'ПОДОЖДИТЕ'
            : canAccept
                ? 'ПРИНЯТЬ'
                : 'ОТГРУЗИТЬ',
        quickLabel: printingInvoiceOrderId != null ? 'Открытие…' : 'Накладная',
        quickBackgroundColor: const Color(0xFFF9B32C),
        quickForegroundColor: Colors.black,
        paymentBackgroundColor: const Color(0xFF4BCA9B),
        paymentDisabledBackgroundColor:
            const Color.fromARGB(255, 132, 186, 163),
        paymentForegroundColor: Colors.white,
        cancelLabel: 'НАЗАД',
        quickEnabled: !busy && order != null && printingInvoiceOrderId == null,
        onQuick: busy || order == null || printingInvoiceOrderId != null
            ? null
            : () => onPrintInvoice(order),
        onCancel: controller.actionLoading ? null : onClose,
        onPay: busy || (!canAccept && !canShip)
            ? null
            : canAccept
                ? () => _confirmAndAccept(context, controller)
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

Future<void> _confirmAndAccept(
  BuildContext context,
  MarketplaceOrdersController controller,
) async {
  final order = controller.selectedOrder;
  if (order == null) return;
  final items = order.acceptableItems;
  final fields = items
      .map((item) =>
          TextEditingController(text: item.availableQuantity.toString()))
      .toList();
  String? error;
  try {
    final selected = await showDialog<List<MarketplaceOrderQuantity>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('Приём товаров со склада этой кассы'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Укажите все количества одним запросом. После приёма изменить их нельзя. 0 — пропустить позицию.'),
                  for (var i = 0; i < items.length; i++)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: fields[i],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: items[i].name.isEmpty
                                ? items[i].id
                                : items[i].name,
                            helperText:
                                'Доступно: ${items[i].availableQuantity}',
                          ),
                        )),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ]),
              )),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () {
                  final quantities = <MarketplaceOrderQuantity>[];
                  for (var i = 0; i < items.length; i++) {
                    final quantity = num.tryParse(
                        fields[i].text.trim().replaceAll(',', '.'));
                    if (quantity == null ||
                        !quantity.isFinite ||
                        quantity < 0 ||
                        quantity > items[i].availableQuantity) {
                      setState(() => error =
                          'Количество должно быть от 0 до доступного остатка.');
                      return;
                    }
                    if (quantity > 0) {
                      quantities.add(MarketplaceOrderQuantity(
                          id: items[i].id, quantity: quantity));
                    }
                  }
                  if (quantities.isEmpty) {
                    setState(() =>
                        error = 'Укажите количество хотя бы одной позиции.');
                    return;
                  }
                  Navigator.pop(dialogContext, quantities);
                },
                child: const Text('Принять')),
          ],
        );
      }),
    );
    if (selected != null &&
        context.mounted &&
        controller.selectedOrder?.id == order.id) {
      await controller.acceptSelected(items: selected);
    }
  } finally {
    // Dispose after the dialog route has finished its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final field in fields) {
      field.dispose();
    }
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
      content:
          const Text('Отгрузить весь оставшийся объём, принятый этой кассой?'),
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
    SnackBar(
        content: Text('Принятые этой кассой товары отгружены.$saleSuffix')),
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

Color? _orderDotColor(String status) => switch (status) {
      'awaiting_confirmation' => const Color(0xFF22B982),
      'processing' || 'partially_shipped' => const Color(0xFFF59E0B),
      _ => null,
    };
