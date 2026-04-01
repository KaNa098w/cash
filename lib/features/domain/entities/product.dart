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

  @override
  List<Object?> get props =>
      [id, name, price, vat, quantity, measurementUnit, conversionValue];
}
