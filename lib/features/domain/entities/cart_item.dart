import 'package:equatable/equatable.dart';
import 'product.dart';

class CartItem extends Equatable {
  final Product product;
  final double qty;
  final double discount; // percent

  const CartItem({required this.product, this.qty = 1, this.discount = 0});

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(
          json['product'] is Map
              ? Map<String, dynamic>.from(json['product'] as Map)
              : const <String, dynamic>{},
        ),
        qty: (json['qty'] as num?)?.toDouble() ?? 1,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
      );

  double get sum => (product.price * qty) * (1 - discount / 100);

  CartItem copyWith({Product? product, double? qty, double? discount}) =>
      CartItem(product: product ?? this.product, qty: qty ?? this.qty, discount: discount ?? this.discount);

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'qty': qty,
        'discount': discount,
      };

  @override
  List<Object?> get props => [product, qty, discount];
}
