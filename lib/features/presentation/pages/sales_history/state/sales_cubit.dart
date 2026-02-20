// lib/features/pos/presentation/pages/sales_history/state/sales_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/models/refund_model.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';
import 'package:pos_desktop_clean/features/data/datasources/sale_remote_datesource.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/state/sales_state.dart';

class SalesHistoryCubit extends Cubit<SalesHistoryState> {
  SalesHistoryCubit(this._remote) : super(SalesHistoryState.initial());

  final SaleRemoteDataSource _remote;

  void _safeEmit(SalesHistoryState s) {
    if (isClosed) return;
    emit(s);
  }

  void showError(String message) {
    _safeEmit(
        state.copyWith(loading: false, loadingMore: false, error: message));
  }

  Future<void> loadFirst({required String key, int perPage = 15}) async {
    _safeEmit(SalesHistoryState.initial());

    try {
      final res = await _remote.getSales(key: key, page: 1, perPage: perPage);
      _safeEmit(
        state.copyWith(
          loading: false,
          sales: res.items,
          page: res.currentPage,
          lastPage: res.lastPage,
          error: null,
        ),
      );
    } catch (e) {
      _safeEmit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> loadMore({required String key, int perPage = 15}) async {
    if (!state.canLoadMore) return;

    _safeEmit(state.copyWith(loadingMore: true, error: null));
    final nextPage = state.page + 1;

    try {
      final res =
          await _remote.getSales(key: key, page: nextPage, perPage: perPage);
      _safeEmit(
        state.copyWith(
          loadingMore: false,
          sales: [...state.sales, ...res.items],
          page: res.currentPage,
          lastPage: res.lastPage,
          error: null,
        ),
      );
    } catch (e) {
      _safeEmit(state.copyWith(loadingMore: false, error: e.toString()));
    }
  }

  Future<void> refreshSaleById(
      {required String key, required String saleId}) async {
    try {
      final updated = await _remote.fetchSaleById(key: key, saleId: saleId);
      final idx = state.sales.indexWhere((s) => s.localId == saleId);
      if (idx == -1) return;

      final next = List<SaleModel>.from(state.sales);
      next[idx] = updated;

      _safeEmit(state.copyWith(sales: next));
    } catch (_) {
      // ок
    }
  }

  void applyRefundOptimistic({
    required String saleId,
    required String refundId,
    required Map<String, int> pickedBySaleItemId,
  }) {
    final idx = state.sales.indexWhere((s) => s.localId == saleId);
    if (idx == -1) return;

    final oldSale = state.sales[idx];

    final newItems = oldSale.items.map((it) {
      final picked = pickedBySaleItemId[it.id] ?? 0;
      if (picked <= 0) return it;

      final oldRefunded = it.refund_quantity ?? 0;
      final nextRefunded = (oldRefunded + picked).clamp(0, it.quantity);

      return it.copyWith(refund_quantity: nextRefunded);
    }).toList();

    final nextSale = oldSale.copyWith(
      items: newItems,
      refund: (oldSale.refund == null)
          ? RefundModel(id: refundId, items: [])
          : oldSale.refund!.copyWith(id: refundId),
    );

    final next = List<SaleModel>.from(state.sales);
    next[idx] = nextSale;

    _safeEmit(state.copyWith(sales: next));
  }
}
