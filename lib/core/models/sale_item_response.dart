// lib/core/models/sale_pagination.dart
import 'package:pos_desktop_clean/core/models/sale_model.dart';

class PaginatedSales {
  final List<SaleModel> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;

  const PaginatedSales({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
  });
}


// lib/core/models/sale_item_model.dart
class SaleItemModel {
  final String saleId;
  final String productId;
  final int quantity;
  final String price;
  final String totalPrice;

  const SaleItemModel({
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.price,
    required this.totalPrice,
  });

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      saleId: (json['sale_id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      price: (json['price'] ?? '0').toString(),
      totalPrice: (json['total_price'] ?? '0').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sale_id': saleId,
        'product_id': productId,
        'quantity': quantity,
        'price': price,
        'total_price': totalPrice,
      };
}
