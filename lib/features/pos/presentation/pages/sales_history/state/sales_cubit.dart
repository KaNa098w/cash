// lib/features/pos/presentation/pages/sales_history/state/sales_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pos_desktop_clean/features/pos/data/datasources/sale_remote_datesource.dart';
import 'package:pos_desktop_clean/features/pos/presentation/pages/sales_history/state/sales_state.dart';

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

  

  Future<void> loadMore({
    required String key,
    int perPage = 15,
  }) async {
    if (!state.canLoadMore) return;

    emit(state.copyWith(loadingMore: true, error: null));
    final nextPage = state.page + 1;

    try {
      final res = await _remote.getSales(key: key, page: nextPage, perPage: perPage);
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
