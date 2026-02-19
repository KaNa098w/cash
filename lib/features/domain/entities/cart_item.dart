import 'package:equatable/equatable.dart';
import 'product.dart';

class CartItem extends Equatable {
  final Product product;
  final double qty;
  final double discount; // percent

  const CartItem({required this.product, this.qty = 1, this.discount = 0});

  double get sum => (product.price * qty) * (1 - discount / 100);

  CartItem copyWith({Product? product, double? qty, double? discount}) =>
      CartItem(product: product ?? this.product, qty: qty ?? this.qty, discount: discount ?? this.discount);

  @override
  List<Object?> get props => [product, qty, discount];
}
