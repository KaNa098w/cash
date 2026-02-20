import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get_it/get_it.dart';

import 'package:pos_desktop_clean/core/models/sale_model.dart';
import 'package:pos_desktop_clean/core/provider/auth_provider.dart';
import 'package:pos_desktop_clean/features/data/datasources/sale_remote_datesource.dart';
import 'package:pos_desktop_clean/features/data/datasources/refunds_remote_datasource.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/widgets/error_bloc.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/widgets/sales_history_controller.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/widgets/sales_search_bar.dart';
import 'package:pos_desktop_clean/features/presentation/widgets/onscreen_keyboar_widget.dart';

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
    _cubit = SalesHistoryCubit(remote);

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
    final posId = auth.posId?.trim() ?? '';
    final storeId = auth.storeId?.trim() ?? '';
    final accountId = auth.users.isNotEmpty ? (auth.users.first.id ?? '') : '';

    if (key.isEmpty) return _snack('Нет posKey');
    if (posId.isEmpty) return _snack('Нет posId');
    if (storeId.isEmpty) return _snack('Нет storeId');
    if (accountId.trim().isEmpty) return _snack('Нет accountId пользователя');

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
      final q = (e.refundedQuantity + e.quantity).clamp(0, e.totalQuantity);
      return RefundItemPayload(
        productId: e.productId,
        saleItemId: e.saleItemId,
        quantity: q,
        price: e.price,
      );
    }).toList();

    final totalAmount =
        items.fold<num>(0, (s, it) => s + it.price * it.quantity);

    final refundsRemote = GetIt.I<RefundsRemoteDatasource>();
    final refundId = (sale.refund?.id ?? '').trim();

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
                  await refundsRemote.updateRefundV2(
                    key: key,
                    refundId: refundId,
                    saleId: saleId,
                    customerId: sale.customerId,
                    totalAmount: totalAmount,
                    items: items,
                    date: DateTime.now(),
                    returnAccessKey: accessKey, // <— добавить в datasource
                  );
                } else {
                  await refundsRemote.createRefundV2(
                    key: key,
                    saleId: saleId,
                    customerId: sale.customerId,
                    totalAmount: totalAmount,
                    items: items,
                    date: DateTime.now(),
                    returnAccessKey: accessKey,
                  );
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
      _snack(refundId.isNotEmpty ? 'Возврат обновлён' : 'Возврат создан');

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
                                      expanded: expanded,
                                      refundLoading:
                                          _controller.isRefundLoading(saleId),
                                      selectedCount: _controller
                                          .selectedItemsCount(saleId),
                                      selectedTotal:
                                          _controller.selectedTotal(saleId),
                                      onSubmitRefund: () =>
                                          _submitRefund(context, sale),
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
