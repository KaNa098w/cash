import 'package:leemon_app/core/models/sale_model.dart';

enum SalesStatusFilter {
  all,
  cash,
  card,
  debt,
  mixed,
  refunded,
}

List<SaleModel> filterSales(
  List<SaleModel> sales,
  String query, {
  DateTime? date,
  SalesStatusFilter status = SalesStatusFilter.all,
}) {
  var result = sales;

  if (date != null) {
    result = result.where((s) {
      final d = s.date.toLocal();
      return d.year == date.year && d.month == date.month && d.day == date.day;
    }).toList();
  }

  if (status != SalesStatusFilter.all) {
    result = result.where((sale) {
      final method = sale.paymentMethod.trim().toLowerCase();
      return switch (status) {
        SalesStatusFilter.cash => method == 'cash',
        SalesStatusFilter.card => method == 'card',
        SalesStatusFilter.debt =>
          method == 'debt' || method == 'credit' || method == 'partial_debt',
        SalesStatusFilter.mixed => method == 'mixed',
        SalesStatusFilter.refunded => _hasRefund(sale),
        SalesStatusFilter.all => true,
      };
    }).toList();
  }

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return result;

  return result.where((s) {
    final n = s.number.trim().toLowerCase();
    final id = s.localId.trim().toLowerCase();
    return n.contains(q) || id.contains(q);
  }).toList();
}

bool _hasRefund(SaleModel sale) {
  final refund = sale.refund;
  if (refund != null) {
    return refund.id.trim().isNotEmpty ||
        (refund.totalAmount ?? 0) > 0 ||
        refund.items.isNotEmpty;
  }
  return sale.items.any((item) => (item.refund_quantity ?? 0) > 0);
}

String saleNumber(SaleModel s) {
  final n = s.number.trim();
  if (n.isNotEmpty) return n;

  return 'Без номера';
}

String cashierLabel(SaleModel s) {
  if (s.userId.isEmpty) return '—';
  return s.userId.length > 12 ? '${s.userId.substring(0, 12)}…' : s.userId;
}
