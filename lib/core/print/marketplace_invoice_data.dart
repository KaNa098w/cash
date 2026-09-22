import 'package:leemon_app/core/models/marketplace_order_models.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/features/data/utils/money.dart';

InvoicePdfData marketplaceInvoiceData(
  MarketplaceOrder order, {
  required String cashierName,
  required String storeName,
}) {
  final items = order.groupedItems.map((item) {
    if (item.requestedQuantity <= 0) {
      throw StateError('Не указано количество товара «${item.name}»');
    }
    final total = (item.lineTotal * 100).round() / 100;
    final price =
        item.unitPrice > 0 ? item.unitPrice : total / item.requestedQuantity;
    final originalTotal = price * item.requestedQuantity;
    final discount = originalTotal > total && originalTotal > 0
        ? (originalTotal - total) / originalTotal * 100
        : 0;
    return ReceiptPdfItem(
      name: item.name.isEmpty ? item.productId : item.name,
      quantity: item.requestedQuantity,
      unitPrice: price,
      baseUnitPrice: price,
      lineTotal: total,
      discountPercent: discount,
    );
  }).toList();
  if (items.isEmpty) throw StateError('В заказе нет товаров для накладной');
  final total =
      items.fold<int>(0, (sum, item) => sum + (item.lineTotal * 100).round()) /
          100;
  return InvoicePdfData(
    money: money,
    invoiceDate: order.createdAt ?? DateTime.now(),
    invoiceNumber: order.displayNumber,
    cashierName: cashierName,
    storeName: storeName,
    buyerName: order.customer.name,
    items: items,
    total: total,
    orderTotal: order.hasExplicitTotal || order.total > 0 ? order.total : null,
    paymentMethodLabel: 'Онлайн-заказ',
  );
}
