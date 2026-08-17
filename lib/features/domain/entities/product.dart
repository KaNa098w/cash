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
  final String? conversionUnit;
  bool get hasConversion =>
      conversionValue != null && conversionValue! > 0 && conversionUnit != null;
  bool get allowsPartialPackages {
    String normalize(String value) =>
        value.toLowerCase().replaceAll('.', '').trim();
    const discreteBaseUnits = {'шт', 'уп', 'кор'};
    const packageUnits = {'уп', 'кор'};
    return hasConversion &&
        discreteBaseUnits.contains(normalize(measurementUnit)) &&
        packageUnits.contains(normalize(conversionUnit!));
  }

  final bool isUniversal;
  final bool requiresMarking;
  final String? gtin;
  final String? ntin;

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
    this.conversionUnit,
    this.isUniversal = false,
    this.requiresMarking = false,
    this.gtin,
    this.ntin,
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
        conversionUnit: json['conversionUnit']?.toString(),
        isUniversal: json['isUniversal'] == true,
        requiresMarking: json['requiresMarking'] == true,
        gtin: json['gtin']?.toString(),
        ntin: json['ntin']?.toString(),
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
        'conversionUnit': conversionUnit,
        'isUniversal': isUniversal,
        'requiresMarking': requiresMarking,
        'gtin': gtin,
        'ntin': ntin,
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
        conversionUnit,
        isUniversal,
        requiresMarking,
        gtin,
        ntin,
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
    String? conversionUnit,
    bool clearConversionValue = false,
    bool clearConversionUnit = false,
    bool? isUniversal,
    bool? requiresMarking,
    String? gtin,
    String? ntin,
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
      conversionUnit:
          clearConversionUnit ? null : (conversionUnit ?? this.conversionUnit),
      isUniversal: isUniversal ?? this.isUniversal,
      requiresMarking: requiresMarking ?? this.requiresMarking,
      gtin: gtin ?? this.gtin,
      ntin: ntin ?? this.ntin,
      discountType: discountType ?? this.discountType,
      discountPercent: discountPercent ?? this.discountPercent,
      priceAfterDiscount: priceAfterDiscount ?? this.priceAfterDiscount,
    );
  }
}
