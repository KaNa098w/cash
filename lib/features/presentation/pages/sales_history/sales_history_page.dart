import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pdf/pdf.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/error_bloc.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_history_controller.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_search_bar.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

import 'state/sales_cubit.dart';
import 'state/sales_state.dart';

import 'utils/app_scroll_behavior.dart';
import 'utils/sales_filter.dart';
import 'widgets/sale_card.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  String? _expandedSaleId;

  final ScrollController _scrollController = ScrollController();
  late final SalesHistoryCubit _cubit;

  final _controller = SalesHistoryController();

  final TextEditingController _saleSearchCtrl = TextEditingController();
  Timer? _saleSearchDebounce;
  String _saleQuery = '';

  int? _statusCodeOf(Object e) {
    try {
      final dynamic de = e;
      final dynamic resp = de.response;
      final code = resp?.statusCode;
      if (code is int) return code;
    } catch (_) {}
    return null;
  }

  static const double _fs = 18;
  final FocusNode _saleSearchFocusNode = FocusNode();
  bool _saleKeyboardOpen = false;

  @override
  void initState() {
    super.initState();

    final remote = GetIt.I<SaleRemoteDataSource>();
    final sync = GetIt.I<PosSyncService>();
    _cubit = SalesHistoryCubit(remote, sync);

    _saleSearchCtrl.addListener(() {
      _saleSearchDebounce?.cancel();
      _saleSearchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          _saleQuery = _saleSearchCtrl.text.trim();
          _expandedSaleId = null;
        });
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthTokenProvider>();
      final key = auth.posKey?.trim() ?? '';

      if (key.isEmpty) {
        _cubit.showError('POS key пустой. Пройдите provisioning.');
        return;
      }

      _cubit.loadFirst(key: key);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        if (pos.maxScrollExtent <= 0) _maybeLoadMore();
      });
    });

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      final pos = _scrollController.position;
      const threshold = 240.0;

      if (pos.pixels >= pos.maxScrollExtent - threshold) {
        _maybeLoadMore();
      }
    });
  }

  @override
  void dispose() {
    _saleSearchDebounce?.cancel();
    _saleSearchCtrl.dispose();
    _saleSearchFocusNode.dispose();

    _scrollController.dispose();
    _controller.dispose();
    _cubit.close();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!mounted) return;
    if (_saleQuery.isNotEmpty) return;

    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) return;

    final state = _cubit.state;
    if (state.loading) return;
    if (state.loadingMore) return;

    _cubit.loadMore(key: key);
  }

  Future<T?> _runWithDialogFocus<T>(Future<T?> Function() open) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _saleSearchFocusNode.unfocus();

    try {
      return await open();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _saleSearchFocusNode.requestFocus();
        final t = _saleSearchCtrl.text;
        _saleSearchCtrl.selection = TextSelection.collapsed(offset: t.length);
      });
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _storeName(AuthTokenProvider auth) {
    final raw = auth.storeName?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
    final posName = auth.posName?.trim() ?? '';
    if (posName.isNotEmpty) return posName;
    return 'Магазин';
  }


  Future<void> _printSaleReceipt(SaleModel sale) async {
    final auth = context.read<AuthTokenProvider>();
    final printer = PrintService();
    final pageFormat =
        auth.receiptPaperMm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? (sale.userId.trim().isEmpty ? '-' : sale.userId.trim())
        : auth.activeUserName!.trim();

    try {
      await printer.print80mmSilently(
        () => buildReceiptPdf(
          ReceiptPdfData(
            pageFormat: pageFormat,
            money: money,
            receiptDate: sale.date,
            receiptNumber:
                sale.number.trim().isEmpty ? sale.localId : sale.number.trim(),
            cashierName: cashierName,
            storeName: _storeName(auth),
            items: sale.items
                .map(
                  (it) => ReceiptPdfItem(
                    name: (it.product?.name ?? '').trim().isEmpty
                        ? 'Товар ${it.productId}'
                        : it.product!.name,
                    quantity: it.quantity,
                    unitPrice: it.price,
                    lineTotal: it.totalPrice,
                  ),
                )
                .toList(),
            total: sale.totalAmount,
            discountSum: 0,
            paymentMethodLabel: switch (sale.paymentMethod.trim().toLowerCase()) {
              'cash' => 'Наличные',
              'card' => 'Безналичный',
              'credit' => 'В долг',
              _ => sale.paymentMethod.trim().isEmpty ? '-' : sale.paymentMethod.trim(),
            },
            isCashPayment: sale.paymentMethod.trim().toLowerCase() == 'cash',
          ),
        ),
        format: pageFormat,
      );
      if (!mounted) return;
      _snack('Чек отправлен на печать');
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка печати: $e');
    }
  }

  Future<void> _showRefundSuccessDialog({
    required bool updated,
    required int itemsCount,
    required num totalAmount,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'refund-success',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 420,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF16A34A),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      updated
                          ? 'Возврат успешно обновлён'
                          : 'Возврат успешно оформлен',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Позиции: $itemsCount',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Сумма: ${money(totalAmount.toDouble())}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _applySaleSearch() {
    setState(() {
      _saleQuery = _saleSearchCtrl.text.trim();
      _expandedSaleId = null;
    });
  }

  void _openSaleKeyboard() {
    if (_saleKeyboardOpen) return;
    _saleKeyboardOpen = true;

    _runWithDialogFocus(() {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.15),
        builder: (ctx) {
          return OnScreenKeyboardSheet(
            controllerGetter: () => _saleSearchCtrl,
            onEnter: () {
              Navigator.of(ctx).pop();
              _applySaleSearch();
            },
            onClose: () => Navigator.of(ctx).pop(),
          );
        },
      );
    }).whenComplete(() {
      _saleKeyboardOpen = false;
    });
  }

  Future<void> _submitRefund(BuildContext context, SaleModel sale) async {
    final auth = context.read<AuthTokenProvider>();

    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';

    if (key.isEmpty) return _snack('Нет posKey');
    if (deviceId.isEmpty) return _snack('Нет deviceId');

    final saleId = sale.localId.trim();
    if (saleId.isEmpty) return _snack('saleId пустой (sale.localId)');
    if (_controller.isRefundLoading(saleId)) return;

    final picks = _controller
        .salePickMap(saleId)
        .values
        .where((e) => e.checked && e.quantity > 0)
        .toList();

    if (picks.isEmpty) return _snack('Выбери товары для возврата');

    final items = picks.map((e) {
      if (e.productId.trim().isEmpty) {
        throw Exception('product_id пустой у sale_item_id=${e.saleItemId}');
      }
      return <String, dynamic>{
        'product_id': e.productId,
        'sale_item_id': e.saleItemId,
        'quantity': e.quantity,
        'price': e.price,
      };
    }).toList();

    final totalAmount = items.fold<int>(
      0,
      (sum, it) =>
          sum +
          (((it['price'] as num?) ?? 0).round() *
              ((it['quantity'] as num?) ?? 0).round()),
    );

    final sync = sl<PosSyncService>();
    final refundId = (sale.refund?.id ?? '').trim();
    var effectiveRefundId = refundId;
    final pickedBySaleItemId = <String, int>{
      for (final p in picks) p.saleItemId: p.quantity,
    };

    _controller.setRefundLoading(saleId, true, () => setState(() {}));

    try {
      final ok = await _runWithDialogFocus(() async {
        return showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => RefundAccessDialog(
            onScanned: (barcode) async {
              final accessKey = barcode.trim();
              if (accessKey.isEmpty) return false;

              try {
                if (refundId.isNotEmpty) {
                  // ✅ ВАЖНО: добавь в updateRefundV2 параметр returnAccessKey и прокинь в запрос
                  final result = await sync.createRefund(
                    key: key,
                    deviceId: deviceId,
                    saleId: saleId,
                    totalAmount: totalAmount,
                    items: items,
                    date: DateTime.now(),
                    returnAccessKey: accessKey, // <— добавить в datasource
                  );
                  if (result.result == QueueSendResult.manual) {
                    throw Exception(
                      result.errorMessage ??
                          'Р’РѕР·РІСЂР°С‚ С‚СЂРµР±СѓРµС‚ СЂСѓС‡РЅРѕР№ РѕР±СЂР°Р±РѕС‚РєРё',
                    );
                  }
                  effectiveRefundId = result.clientId;
                } else {
                  final result = await sync.createRefund(
                    key: key,
                    deviceId: deviceId,
                    saleId: saleId,
                    totalAmount: totalAmount,
                    items: items,
                    date: DateTime.now(),
                    returnAccessKey: accessKey,
                  );
                  if (result.result == QueueSendResult.manual) {
                    throw Exception(
                      result.errorMessage ??
                          'Р’РѕР·РІСЂР°С‚ С‚СЂРµР±СѓРµС‚ СЂСѓС‡РЅРѕР№ РѕР±СЂР°Р±РѕС‚РєРё',
                    );
                  }
                  effectiveRefundId = result.clientId;
                }
                return true; // 200 — доступ есть
              } catch (e) {
                // 401 — доступ нет, диалог покажет ошибку и попросит перескан
                if (_statusCodeOf(e) == 401) return false;
                rethrow; // остальные ошибки покажем как "Ошибка запроса"
              }
            },
          ),
        );
      });

      if (ok != true) return; // отмена/закрытие/нет доступа

      if (!mounted) return;
      _cubit.applyRefundOptimistic(
        saleId: saleId,
        refundId: effectiveRefundId,
        pickedBySaleItemId: pickedBySaleItemId,
      );
      await _showRefundSuccessDialog(
        updated: refundId.isNotEmpty,
        itemsCount: picks.length,
        totalAmount: totalAmount,
      );

      _controller.clearPicksForSale(saleId, () => setState(() {}));
      await _cubit.refreshSaleById(key: key, saleId: saleId);
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка возврата: $e');
    } finally {
      if (mounted)
        _controller.setRefundLoading(saleId, false, () => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: _fs, color: Colors.black),
      child: BlocProvider.value(
        value: _cubit,
        child: BlocBuilder<SalesHistoryCubit, SalesHistoryState>(
          builder: (context, state) {
            final visibleSales = filterSales(state.sales, _saleQuery);
            final showLoadMoreTile = state.loadingMore && _saleQuery.isEmpty;
            final savedCashierName =
                context.read<AuthTokenProvider>().activeUserName ?? '';

            return Column(
              children: [
                SalesSearchBar(
                  controller: _saleSearchCtrl,
                  focusNode: _saleSearchFocusNode,
                  foundCount:
                      _saleQuery.isNotEmpty ? visibleSales.length : null,
                  onSubmit: _applySaleSearch,
                  onOpenKeyboard: _openSaleKeyboard,
                  onClear: () {
                    _saleSearchCtrl.clear();
                    setState(() => _expandedSaleId = null);
                    _applySaleSearch();
                  },
                ),
                Expanded(
                  child: state.loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.grey))
                      : state.error != null
                          ? ErrorBlock(
                              message: state.error!,
                              onRetry: () {
                                final key = context
                                        .read<AuthTokenProvider>()
                                        .posKey
                                        ?.trim() ??
                                    '';
                                if (key.isNotEmpty) _cubit.loadFirst(key: key);
                              },
                            )
                          : ScrollConfiguration(
                              behavior: AppScrollBehavior(),
                              child: Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                trackVisibility: true,
                                interactive: true,
                                thickness: 10,
                                radius: const Radius.circular(12),
                                child: ListView.separated(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 4),
                                  itemCount: visibleSales.length +
                                      (showLoadMoreTile ? 1 : 0),
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, index) {
                                    if (showLoadMoreTile &&
                                        index >= visibleSales.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    }

                                    final sale = visibleSales[index];
                                    final expanded =
                                        _expandedSaleId == sale.localId;
                                    final saleId = sale.localId;

                                    return SaleCard(
                                      sale: sale,
                                      cashierName: savedCashierName,
                                      expanded: expanded,
                                      refundLoading:
                                          _controller.isRefundLoading(saleId),
                                      selectedCount: _controller
                                          .selectedItemsCount(saleId),
                                      selectedTotal:
                                          _controller.selectedTotal(saleId),
                                      onSubmitRefund: () =>
                                          _submitRefund(context, sale),
                                      onPrintReceipt: () =>
                                          _printSaleReceipt(sale),
                                      onToggle: () => setState(() {
                                        _expandedSaleId =
                                            expanded ? null : sale.localId;
                                      }),
                                      picks: _controller.salePickMap(saleId),
                                      onToggleItem: (item, checked) =>
                                          setState(() {
                                        _controller.toggleItem(
                                          saleId: saleId,
                                          item: item,
                                          checked: checked,
                                          notify: () {},
                                        );
                                      }),
                                      onQtyChanged: (item, q) => setState(() {
                                        _controller.changeQty(
                                          saleId: saleId,
                                          item: item,
                                          newQty: q,
                                          notify: () {},
                                        );
                                      }),
                                      refundedQtyOf: _controller.refundedQtyOf,
                                      availableQtyOf:
                                          _controller.availableQtyOf,
                                    );
                                  },
                                ),
                              ),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
