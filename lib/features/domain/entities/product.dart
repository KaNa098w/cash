import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;

  /// Base selling price (before any discount).
  final double price;
  final double arrivalCost;
  final double vat;
  final double quantity;
  final String measurementUnit;
  final double? conversionValue;
  final bool isUniversal;

  /// "automatic" | "fixed" | "forbidden" | null
  final String? discountType;
  final double discountPercent;

  /// Unit price after server-computed discount. 0 if no discount.
  final double priceAfterDiscount;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.arrivalCost = 0,
    this.vat = 0,
    this.quantity = 0,
    this.measurementUnit = 'шт.',
    this.conversionValue,
    this.isUniversal = false,
    this.discountType,
    this.discountPercent = 0,
    this.priceAfterDiscount = 0,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        price: (json['price'] as num?)?.toDouble() ?? 0,
        arrivalCost: (json['arrivalCost'] as num?)?.toDouble() ??
            (json['arrival_cost'] as num?)?.toDouble() ??
            0,
        vat: (json['vat'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        measurementUnit: (json['measurementUnit'] ?? 'шт.').toString(),
        conversionValue: (json['conversionValue'] as num?)?.toDouble(),
        isUniversal: json['isUniversal'] == true,
        discountType: json['discountType']?.toString(),
        discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0,
        priceAfterDiscount:
            (json['priceAfterDiscount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'arrivalCost': arrivalCost,
        'vat': vat,
        'quantity': quantity,
        'measurementUnit': measurementUnit,
        'conversionValue': conversionValue,
        'isUniversal': isUniversal,
        'discountType': discountType,
        'discountPercent': discountPercent,
        'priceAfterDiscount': priceAfterDiscount,
      };

  @override
  List<Object?> get props => [
        id,
        name,
        price,
        arrivalCost,
        vat,
        quantity,
        measurementUnit,
        conversionValue,
        isUniversal,
        discountType,
        discountPercent,
        priceAfterDiscount,
      ];

  Product copyWith({
    String? id,
    String? name,
    double? price,
    double? arrivalCost,
    double? vat,
    double? quantity,
    String? measurementUnit,
    double? conversionValue,
    bool clearConversionValue = false,
    bool? isUniversal,
    String? discountType,
    double? discountPercent,
    double? priceAfterDiscount,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      arrivalCost: arrivalCost ?? this.arrivalCost,
      vat: vat ?? this.vat,
      quantity: quantity ?? this.quantity,
      measurementUnit: measurementUnit ?? this.measurementUnit,
      conversionValue: clearConversionValue
          ? null
          : (conversionValue ?? this.conversionValue),
      isUniversal: isUniversal ?? this.isUniversal,
      discountType: discountType ?? this.discountType,
      discountPercent: discountPercent ?? this.discountPercent,
      priceAfterDiscount: priceAfterDiscount ?? this.priceAfterDiscount,
    );
  }
}
