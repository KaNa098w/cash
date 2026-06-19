import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';

class SalesHistoryState {
  final bool loading;
  final bool loadingMore;
  final bool printing;
  final String? error;

  final List<SaleModel> sales;
  final List<RefundModel> refunds;
  final List<LocalSession> sessions;
  final int page;
  final int lastPage;

  const SalesHistoryState({
    required this.loading,
    required this.loadingMore,
    required this.printing,
    required this.sales,
    required this.refunds,
    required this.sessions,
    required this.page,
    required this.lastPage,
    this.error,
  });

  factory SalesHistoryState.initial() => const SalesHistoryState(
        loading: true,
        loadingMore: false,
        printing: false,
        sales: [],
        refunds: [],
        sessions: [],
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
    Object? error = _keep,
    List<SaleModel>? sales,
    List<RefundModel>? refunds,
    List<LocalSession>? sessions,
    int? page,
    int? lastPage,
  }) {
    return SalesHistoryState(
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      printing: printing ?? this.printing,
      error: identical(error, _keep) ? this.error : error as String?,
      sales: sales ?? this.sales,
      refunds: refunds ?? this.refunds,
      sessions: sessions ?? this.sessions,
      page: page ?? this.page,
      lastPage: lastPage ?? this.lastPage,
    );
  }
}
