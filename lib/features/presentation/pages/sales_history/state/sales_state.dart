// lib/features/pos/presentation/pages/sales_history/state/sales_state.dart
import 'package:leemon_app/core/models/sale_model.dart';

class SalesHistoryState {
  final bool loading;
  final bool loadingMore;
  final bool printing; // ✅ NEW
  final String? error;

  final List<SaleModel> sales;
  final int page;
  final int lastPage;

  const SalesHistoryState({
    required this.loading,
    required this.loadingMore,
    required this.printing,
    required this.sales,
    required this.page,
    required this.lastPage,
    this.error,
  });

  factory SalesHistoryState.initial() => const SalesHistoryState(
        loading: true,
        loadingMore: false,
        printing: false, // ✅
        sales: [],
        page: 1,
        lastPage: 1,
        error: null,
      );

  bool get canLoadMore => !loading && !loadingMore && page < lastPage;

  static const _keep = Object();

  SalesHistoryState copyWith({
    bool? loading,
    bool? loadingMore,
    bool? printing,
    // Pass error: null to clear, omit to keep current value.
    Object? error = _keep,
    List<SaleModel>? sales,
    int? page,
    int? lastPage,
  }) {
    return SalesHistoryState(
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      printing: printing ?? this.printing,
      error: identical(error, _keep) ? this.error : error as String?,
      sales: sales ?? this.sales,
      page: page ?? this.page,
      lastPage: lastPage ?? this.lastPage,
    );
  }
}
