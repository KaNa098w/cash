import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;

  /// Base selling price (before any discount).
  final double price;
  final double vat;
  final double quantity;
  final String measurementUnit;
  final double? conversionValue;

  /// "automatic" | "fixed" | "forbidden" | null
  final String? discountType;
  final double discountPercent;

  /// Unit price after server-computed discount. 0 if no discount.
  final double priceAfterDiscount;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.vat = 0,
    this.quantity = 0,
    this.measurementUnit = 'шт.',
    this.conversionValue,
    this.discountType,
    this.discountPercent = 0,
    this.priceAfterDiscount = 0,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        price: (json['price'] as num?)?.toDouble() ?? 0,
        vat: (json['vat'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        measurementUnit: (json['measurementUnit'] ?? 'шт.').toString(),
        conversionValue: (json['conversionValue'] as num?)?.toDouble(),
        discountType: json['discountType']?.toString(),
        discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0,
        priceAfterDiscount:
            (json['priceAfterDiscount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'vat': vat,
        'quantity': quantity,
        'measurementUnit': measurementUnit,
        'conversionValue': conversionValue,
        'discountType': discountType,
        'discountPercent': discountPercent,
        'priceAfterDiscount': priceAfterDiscount,
      };

  @override
  List<Object?> get props => [
        id,
        name,
        price,
        vat,
        quantity,
        measurementUnit,
        conversionValue,
        discountType,
        discountPercent,
        priceAfterDiscount,
      ];
}
