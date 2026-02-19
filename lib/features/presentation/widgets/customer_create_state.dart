// lib/features/pos/presentation/pages/customers/state/customer_create_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';

class CustomerCreateState {
  final bool loading;
  final String? error;

  const CustomerCreateState({required this.loading, this.error});

  factory CustomerCreateState.initial() => const CustomerCreateState(loading: false);

  CustomerCreateState copyWith({bool? loading, String? error}) {
    return CustomerCreateState(
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class CustomerCreateCubit extends Cubit<CustomerCreateState> {
  CustomerCreateCubit() : super(CustomerCreateState.initial());

  Future<void> createCustomer({
    required String fullName,
    String? phone,
    String? iin,
    String? comment,
  }) async {
    emit(state.copyWith(loading: true, error: null));
    try {
      // TODO: тут подключишь свой репозиторий/remote datasource
      // final created = await repo.createCustomer(...);

      await Future.delayed(const Duration(milliseconds: 400)); // заглушка
      emit(state.copyWith(loading: false));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }
}
