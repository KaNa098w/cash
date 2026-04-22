import 'package:equatable/equatable.dart';
import 'product.dart';

class CartItem extends Equatable {
  final Product product;
  final double qty;
  final double discount; // legacy percent discount, usually 0

  /// Applied server discount for this line item.
  final bool discountApplied;

  const CartItem({
    required this.product,
    this.qty = 1,
    this.discount = 0,
    this.discountApplied = false,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(
          json['product'] is Map
              ? Map<String, dynamic>.from(json['product'] as Map)
              : const <String, dynamic>{},
        ),
        qty: (json['qty'] as num?)?.toDouble() ?? 1,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        discountApplied: json['discountApplied'] == true,
      );

  /// Effective unit price: uses priceAfterDiscount when discount is applied.
  double get effectiveUnitPrice {
    if (product.isUniversal) return product.price;
    if (discountApplied && product.priceAfterDiscount > 0) {
      return product.priceAfterDiscount;
    }
    return product.price;
  }

  double get effectiveDiscountPercent {
    if (product.isUniversal) return 0;
    if (discountApplied && product.discountPercent > 0) {
      return product.discountPercent;
    }
    return discount;
  }

  double get sum {
    if (product.isUniversal) return effectiveUnitPrice * qty;
    return effectiveUnitPrice * qty * (1 - discount / 100);
  }

  CartItem copyWith({
    Product? product,
    double? qty,
    double? discount,
    bool? discountApplied,
  }) =>
      CartItem(
        product: product ?? this.product,
        qty: qty ?? this.qty,
        discount: discount ?? this.discount,
        discountApplied: discountApplied ?? this.discountApplied,
      );

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'qty': qty,
        'discount': discount,
        'discountApplied': discountApplied,
      };

  @override
  List<Object?> get props => [product, qty, discount, discountApplied];
}
