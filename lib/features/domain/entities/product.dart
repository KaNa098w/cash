import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;
  final double price;
  final double vat; // percent, eg 20
  final double quantity; // stock quantity (in product's measurement unit)
  final String measurementUnit;

  /// Сколько штук в 1 единице измерения товара.
  /// null — если товар продаётся в штуках (конвертация не нужна).
  final double? conversionValue;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.vat = 0,
    this.quantity = 0,
    this.measurementUnit = 'шт.',
    this.conversionValue,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        price: (json['price'] as num?)?.toDouble() ?? 0,
        vat: (json['vat'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        measurementUnit: (json['measurementUnit'] ?? 'шт.').toString(),
        conversionValue: (json['conversionValue'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'vat': vat,
        'quantity': quantity,
        'measurementUnit': measurementUnit,
        'conversionValue': conversionValue,
      };

  @override
  List<Object?> get props =>
      [id, name, price, vat, quantity, measurementUnit, conversionValue];
}
