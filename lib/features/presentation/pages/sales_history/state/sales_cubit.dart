// lib/features/pos/presentation/pages/sales_history/state/sales_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/datasources/refunds_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/state/sales_state.dart';

class SalesHistoryCubit extends Cubit<SalesHistoryState> {
  SalesHistoryCubit(this._sync, this._refundsRemote)
      : super(SalesHistoryState.initial());

  final PosSyncService _sync;
  final RefundsRemoteDatasource _refundsRemote;

  void _safeEmit(SalesHistoryState s) {
    if (isClosed) return;
    emit(s);
  }

  void showError(String message) {
    _safeEmit(
        state.copyWith(loading: false, loadingMore: false, error: message));
  }

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
      if (preferredNumber.isNotEmpty) {
        numberIndex[preferredNumber] = existingIndex;
      }
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
      total +=
          sale.items.where((item) => (item.refund_quantity ?? 0) > 0).length;
      return total;
    }

    final currentScore = score(current);
    final candidateScore = score(candidate);
    if (candidateScore > currentScore) return candidate;
    if (candidateScore < currentScore) return current;

    return candidate.date.isAfter(current.date) ? candidate : current;
  }

  Future<void> loadFirst({String? key}) async {
    final history = await _sync.loadAllSalesHistory();
    final pending = await _sync.loadPendingSales();
    final sessions = await _sync.loadSessions();
    var refunds = await _sync.loadAllRefundsHistory();
    final safeKey = key?.trim() ?? '';

    if (safeKey.isNotEmpty) {
      try {
        refunds = await _refundsRemote.fetchAllRefunds(key: safeKey);
      } catch (_) {
        // Keep the locally loaded snapshot/pull refunds.
      }
    }

    _safeEmit(SalesHistoryState.initial().copyWith(
      loading: false,
      sales: _mergeWithPending(history, pending),
      refunds: refunds,
      sessions: sessions,
      page: 1,
      lastPage: 1,
      error: null,
    ));
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
      final maxRefundable = it.quantity.floor();
      final nextRefunded = (oldRefunded + picked).clamp(0, maxRefundable);

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
