import 'package:equatable/equatable.dart';
import 'package:leemon_app/core/models/marking_check.dart';
import 'product.dart';

class CartItem extends Equatable {
  final Product product;
  final double qty;
  final double discount; // legacy percent discount, usually 0
  final double? customUnitPrice;

  /// Applied server discount for this line item.
  final bool discountApplied;
  final List<String> markCodes;
  final MarkingCheckItem? markingCheck;

  const CartItem({
    required this.product,
    this.qty = 1,
    this.discount = 0,
    this.customUnitPrice,
    this.discountApplied = false,
    this.markCodes = const <String>[],
    this.markingCheck,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromJson(
          json['product'] is Map
              ? Map<String, dynamic>.from(json['product'] as Map)
              : const <String, dynamic>{},
        ),
        qty: (json['qty'] as num?)?.toDouble() ?? 1,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        customUnitPrice: (json['customUnitPrice'] as num?)?.toDouble(),
        discountApplied: json['discountApplied'] == true,
        markCodes: (json['markCodes'] as List?)
                ?.map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
      );

  /// Effective unit price: uses priceAfterDiscount when discount is applied.
  double get effectiveUnitPrice {
    if (product.isUniversal) return product.price;
    final custom = customUnitPrice;
    if (custom != null && custom > 0) return custom;
    if (discountApplied && product.priceAfterDiscount > 0) {
      return product.priceAfterDiscount;
    }
    return product.price;
  }

  double get effectiveDiscountPercent {
    if (product.isUniversal) return 0;
    final custom = customUnitPrice;
    if (custom != null && product.price > 0 && custom < product.price) {
      return ((product.price - custom) / product.price) * 100;
    }
    if (discountApplied && product.discountPercent > 0) {
      return product.discountPercent;
    }
    return discount;
  }

  /// Quantity in the product's primary measurement unit. The API price is also
  /// expressed per this unit; conversion is only an input/display aid.
  double get billableQuantity => qty;

  double get sum {
    if (product.isUniversal) return effectiveUnitPrice * billableQuantity;
    return effectiveUnitPrice * billableQuantity * (1 - discount / 100);
  }

  CartItem copyWith({
    Product? product,
    double? qty,
    double? discount,
    double? customUnitPrice,
    bool clearCustomUnitPrice = false,
    bool? discountApplied,
    List<String>? markCodes,
    MarkingCheckItem? markingCheck,
    bool clearMarkingCheck = false,
  }) =>
      CartItem(
        product: product ?? this.product,
        qty: qty ?? this.qty,
        discount: discount ?? this.discount,
        customUnitPrice: clearCustomUnitPrice
            ? null
            : (customUnitPrice ?? this.customUnitPrice),
        discountApplied: discountApplied ?? this.discountApplied,
        markCodes: markCodes ?? this.markCodes,
        markingCheck:
            clearMarkingCheck ? null : markingCheck ?? this.markingCheck,
      );

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'qty': qty,
        'discount': discount,
        'customUnitPrice': customUnitPrice,
        'discountApplied': discountApplied,
        'markCodes': markCodes,
      };

  @override
  List<Object?> get props => [
        product,
        qty,
        discount,
        customUnitPrice,
        discountApplied,
        markCodes,
        markingCheck
      ];
}
