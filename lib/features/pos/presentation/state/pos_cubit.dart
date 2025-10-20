import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/pos_repository.dart';

part 'pos_state.dart';

class PosCubit extends Cubit<PosState> {
  final PosRepository repo;
  PosCubit(this.repo) : super(const PosState());

  void seedDemo() {
    final demo = List.generate(6, (i) => CartItem(product: Product(id: '$i', name: 'Типа товаргой', price: 2000, vat: 20), qty: 4, discount: 20));
    emit(state.copyWith(items: demo));
  }

  Future<void> search(String q) async {
    emit(state.copyWith(searching: true));
    final results = await repo.searchProducts(q);
    emit(state.copyWith(searching: false, searchResults: results));
  }

  void add(Product p) {
    final idx = state.items.indexWhere((e) => e.product.id == p.id);
    final items = List<CartItem>.from(state.items);
    if (idx >= 0) {
      final it = items[idx];
      items[idx] = it.copyWith(qty: it.qty + 1);
    } else {
      items.add(CartItem(product: p, qty: 1));
    }
    emit(state.copyWith(items: items));
  }

  void removeAt(int index) {
    final items = List<CartItem>.from(state.items)..removeAt(index);
    emit(state.copyWith(items: items));
  }

  void setQty(int index, double qty) {
    final items = List<CartItem>.from(state.items);
    items[index] = items[index].copyWith(qty: qty);
    emit(state.copyWith(items: items));
  }

  double get total =>
      state.items.fold(0, (p, e) => p + e.sum);

  double get discountSum =>
      state.items.fold(0, (p, e) => p + (e.product.price * e.qty) * (e.discount / 100));

  void setPaymentKind(PaymentKind kind) {
    emit(state.copyWith(paymentKind: kind));
  }

  void setReceived(double value) {
    emit(state.copyWith(received: value));
  }

  double get change => state.received - total;
}
