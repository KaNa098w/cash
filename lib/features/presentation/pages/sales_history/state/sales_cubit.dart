// lib/features/pos/presentation/pages/sales_history/state/sales_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/core/models/refund_model.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';
import 'package:pos_desktop_clean/features/data/datasources/sale_remote_datesource.dart';
import 'package:pos_desktop_clean/features/presentation/pages/sales_history/state/sales_state.dart';

class SalesHistoryCubit extends Cubit<SalesHistoryState> {
  SalesHistoryCubit(this._remote) : super(SalesHistoryState.initial());

  final SaleRemoteDataSource _remote;

  void showError(String message) {
    emit(state.copyWith(loading: false, loadingMore: false, error: message));
  }

  Future<void> loadFirst({
    required String key,
    int perPage = 15,
  }) async {
    emit(SalesHistoryState.initial());

    try {
      final res = await _remote.getSales(key: key, page: 1, perPage: perPage);
      emit(
        state.copyWith(
          loading: false,
          sales: res.items,
          page: res.currentPage,
          lastPage: res.lastPage,
          error: null,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void applyRefundOptimistic({
    required String saleId,
    required String refundId,
    required Map<String, int>
        pickedBySaleItemId, // saleItemId -> picked (доп. возврат)
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

    emit(state.copyWith(sales: next));
  }

  Future<void> refreshSaleById({
    required String key,
    required String saleId,
  }) async {
    try {
      final updated = await _remote.fetchSaleById(key: key, saleId: saleId);

      final cur = state.sales;
      final idx = cur.indexWhere((s) => s.localId == saleId);

      if (idx == -1) return;

      final next = List<SaleModel>.from(cur);
      next[idx] = updated;

      emit(state.copyWith(sales: next));
    } catch (e) {
      // можно молча или показать ошибку
      // showError('Не удалось обновить продажу: $e');
    }
  }

  Future<void> loadMore({
    required String key,
    int perPage = 15,
  }) async {
    if (!state.canLoadMore) return;

    emit(state.copyWith(loadingMore: true, error: null));
    final nextPage = state.page + 1;

    try {
      final res =
          await _remote.getSales(key: key, page: nextPage, perPage: perPage);
      emit(
        state.copyWith(
          loadingMore: false,
          sales: [...state.sales, ...res.items],
          page: res.currentPage,
          lastPage: res.lastPage,
          error: null,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loadingMore: false, error: e.toString()));
    }
  }
}
