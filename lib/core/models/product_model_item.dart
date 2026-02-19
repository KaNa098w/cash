// lib/core/models/sale_item_model.dart
import 'package:pos_desktop_clean/core/models/sale_model.dart';

class SaleItemModel {
  final String id;
  final String saleId;
  final String productId;

  final int quantity;
  final int price;
  final int totalPrice;

  final int refundQuantity;

  final ProductModel? product;

  const SaleItemModel({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.price,
    required this.totalPrice,
    required this.refundQuantity,
    this.product,
  });

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    return SaleItemModel(
      id: (json['id'] ?? '').toString(),
      saleId: (json['sale_id'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asInt(json['quantity']),
      price: _asInt(json['price']),
      totalPrice: _asInt(json['total_price']),
      refundQuantity: _asInt(json['refund_quantity']),
      product: json['product'] is Map<String, dynamic>
          ? ProductModel.fromJson(
              (json['product'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'quantity': quantity,
        'price': price,
        'total_price': totalPrice,
        'refund_quantity': refundQuantity,
        'product': product?.toJson(),
      };
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
