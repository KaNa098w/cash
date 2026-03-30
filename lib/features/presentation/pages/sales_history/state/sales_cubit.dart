// lib/features/pos/presentation/pages/sales_history/state/sales_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/state/sales_state.dart';

class SalesHistoryCubit extends Cubit<SalesHistoryState> {
  SalesHistoryCubit(this._remote, this._sync) : super(SalesHistoryState.initial());

  final SaleRemoteDataSource _remote;
  final PosSyncService _sync;

  void _safeEmit(SalesHistoryState s) {
    if (isClosed) return;
    emit(s);
  }

  void showError(String message) {
    _safeEmit(
        state.copyWith(loading: false, loadingMore: false, error: message));
  }

  /// Merges API/local history with unsynced pending outbox sales.
  /// Pending sales not yet in [history] are prepended and sorted by date DESC.
  List<SaleModel> _mergeWithPending(
    List<SaleModel> history,
    List<SaleModel> pending,
  ) {
    return _mergeUniqueSales([...pending, ...history]);
  }

  List<SaleModel> _mergeUniqueSales(List<SaleModel> sales) {
    if (sales.isEmpty) return const [];

    final merged = <SaleModel>[];
    final idIndex = <String, int>{};
    final numberIndex = <String, int>{};

    for (final sale in sales) {
      final saleId = sale.localId.trim();
      final saleNumber = sale.number.trim();

      int? existingIndex;
      if (saleId.isNotEmpty) {
        existingIndex = idIndex[saleId];
      }
      existingIndex ??= saleNumber.isEmpty ? null : numberIndex[saleNumber];

      if (existingIndex == null) {
        final nextIndex = merged.length;
        merged.add(sale);
        if (saleId.isNotEmpty) idIndex[saleId] = nextIndex;
        if (saleNumber.isNotEmpty) numberIndex[saleNumber] = nextIndex;
        continue;
      }

      final preferred = _preferSale(
        current: merged[existingIndex],
        candidate: sale,
      );
      merged[existingIndex] = preferred;

      final preferredId = preferred.localId.trim();
      final preferredNumber = preferred.number.trim();
      if (preferredId.isNotEmpty) idIndex[preferredId] = existingIndex;
      if (preferredNumber.isNotEmpty) numberIndex[preferredNumber] = existingIndex;
    }

    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  SaleModel _preferSale({
    required SaleModel current,
    required SaleModel candidate,
  }) {
    int score(SaleModel sale) {
      var total = 0;
      if (sale.number.trim().isNotEmpty) total += 2;
      if (sale.refund != null) total += 4;
      total += sale.items.length;
      total += sale.items.where((item) => item.id.trim().isNotEmpty).length * 2;
      total += sale.items
          .where((item) => (item.refund_quantity ?? 0) > 0)
          .length;
      return total;
    }

    final currentScore = score(current);
    final candidateScore = score(candidate);
    if (candidateScore > currentScore) return candidate;
    if (candidateScore < currentScore) return current;

    return candidate.date.isAfter(current.date) ? candidate : current;
  }

  Future<void> loadFirst({required String key, int perPage = 15}) async {
    // 1. Show local data immediately — no spinner
    //    Include unsynced pending outbox sales so offline sales are visible.
    final local = await _sync.loadSalesHistoryPage(page: 1, perPage: perPage);
    final pending = await _sync.loadPendingSales();
    final localLastPage = local.total <= 0
        ? 1
        : ((local.total + perPage - 1) ~/ perPage);

    _safeEmit(SalesHistoryState.initial().copyWith(
      loading: false,
      sales: _mergeWithPending(local.items, pending),
      page: 1,
      lastPage: localLastPage,
      error: null,
    ));

    // 2. Refresh from API silently in background
    try {
      final res = await _remote.getSales(key: key, page: 1, perPage: perPage);
      await _sync.upsertSalesHistory(res.items);
      // Re-load pending after API refresh (some may have been acked)
      final pendingAfter = await _sync.loadPendingSales();
      _safeEmit(state.copyWith(
        loading: false,
        sales: _mergeWithPending(res.items, pendingAfter),
        page: res.currentPage,
        lastPage: res.lastPage,
        error: null,
      ));
    } catch (_) {
      // Keep local data visible, no error shown
    }
  }

  Future<void> loadMore({required String key, int perPage = 15}) async {
    if (!state.canLoadMore) return;

    _safeEmit(state.copyWith(loadingMore: true, error: null));
    final nextPage = state.page + 1;

    try {
      final res =
          await _remote.getSales(key: key, page: nextPage, perPage: perPage);
      await _sync.upsertSalesHistory(res.items);
      _safeEmit(state.copyWith(
        loadingMore: false,
        sales: _mergeUniqueSales([...state.sales, ...res.items]),
        page: res.currentPage,
        lastPage: res.lastPage,
        error: null,
      ));
    } catch (_) {
      // Fallback to local next page
      final local =
          await _sync.loadSalesHistoryPage(page: nextPage, perPage: perPage);
      if (local.items.isEmpty) {
        _safeEmit(state.copyWith(loadingMore: false));
        return;
      }
      final localLastPage = local.total <= 0
          ? nextPage
          : ((local.total + perPage - 1) ~/ perPage);
      _safeEmit(state.copyWith(
        loadingMore: false,
        sales: _mergeUniqueSales([...state.sales, ...local.items]),
        page: nextPage,
        lastPage: localLastPage,
        error: null,
      ));
    }
  }

  Future<void> refreshSaleById(
      {required String key, required String saleId}) async {
    try {
      final updated = await _remote.fetchSaleById(key: key, saleId: saleId);
      await _sync.upsertSalesHistory([updated]);
      final idx = state.sales.indexWhere((s) => s.localId == saleId);
      if (idx == -1) return;
      final next = List<SaleModel>.from(state.sales);
      next[idx] = updated;
      _safeEmit(state.copyWith(sales: next));
    } catch (_) {
      // Offline or error — keep current state as-is
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
      // Match by server id when available; fall back to productId for offline sales.
      final lookupKey = it.id.isNotEmpty ? it.id : it.productId;
      final picked = pickedBySaleItemId[lookupKey] ?? 0;
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
