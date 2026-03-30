import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;
  final double price;
  final double vat; // percent, eg 20
  final double quantity; // stock quantity

  const Product({required this.id, required this.name, required this.price, this.vat = 0, this.quantity = 0});

  @override
  List<Object?> get props => [id, name, price, vat, quantity];
}
