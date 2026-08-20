import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/models/sale_model.dart';

enum SalesStatusFilter {
  all,
  cash,
  card,
  debt,
  mixed,
  refunded,
}

num refundAmount(RefundModel refund) {
  final total = refund.totalAmount;
  if (total != null) return total;
  return refund.items.fold<num>(
    0,
    (sum, item) => sum + (item.price * item.quantity),
  );
}

num netSalesTotal(
  List<SaleModel> sales,
  List<RefundModel> refunds,
) {
  var total = sales.fold<num>(0, (sum, sale) => sum + sale.totalAmount);

  for (final sale in sales) {
    final saleId = sale.localId.trim();
    final embeddedRefundId = sale.refund?.id.trim() ?? '';
    final matchedRefundIds = <String>{};
    num matchedRefundTotal = 0;

    for (final refund in refunds) {
      final refundSaleId = (refund.saleId ?? '').trim();
      final matchesSale = saleId.isNotEmpty && refundSaleId == saleId;
      final matchesEmbeddedRefund =
          embeddedRefundId.isNotEmpty && refund.id.trim() == embeddedRefundId;
      if (!matchesSale && !matchesEmbeddedRefund) continue;

      final refundId = refund.id.trim();
      if (refundId.isNotEmpty && !matchedRefundIds.add(refundId)) continue;
      matchedRefundTotal += refundAmount(refund);
    }

    total -= matchedRefundIds.isNotEmpty || matchedRefundTotal != 0
        ? matchedRefundTotal
        : sale.refund == null
            ? 0
            : refundAmount(sale.refund!);
  }

  return total;
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

List<RefundModel> filterRefunds(
  List<RefundModel> refunds,
  String query, {
  DateTime? date,
}) {
  var result = refunds;

  if (date != null) {
    result = result.where((refund) {
      final refundDate = refund.date;
      if (refundDate == null) return false;
      final d = refundDate.toLocal();
      return d.year == date.year && d.month == date.month && d.day == date.day;
    }).toList();
  }

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return result;

  return result.where((refund) {
    final number = (refund.number ?? '').trim().toLowerCase();
    final id = refund.id.trim().toLowerCase();
    final saleId = (refund.saleId ?? '').trim().toLowerCase();
    final customerId = (refund.customerId ?? '').trim().toLowerCase();
    return number.contains(q) ||
        id.contains(q) ||
        saleId.contains(q) ||
        customerId.contains(q);
  }).toList();
}

String refundNumber(RefundModel refund) {
  final n = (refund.number ?? '').trim();
  if (n.isNotEmpty) return n;

  return 'Без номера';
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
