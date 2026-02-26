import 'package:leemon_app/core/models/sale_model.dart';

List<SaleModel> filterSales(List<SaleModel> sales, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sales;

  return sales.where((s) {
    final n = s.number.trim().toLowerCase();
    final id = s.localId.trim().toLowerCase();
    return n.contains(q) || id.contains(q);
  }).toList();
}

String saleNumber(SaleModel s) {
  final n = s.number.trim();
  if (n.isNotEmpty) return n;

  if (s.localId.isEmpty) return '—';
  return s.localId.length > 8
      ? s.localId.substring(s.localId.length - 8)
      : s.localId;
}

String cashierLabel(SaleModel s) {
  if (s.userId.isEmpty) return '—';
  return s.userId.length > 12 ? '${s.userId.substring(0, 12)}…' : s.userId;
}
