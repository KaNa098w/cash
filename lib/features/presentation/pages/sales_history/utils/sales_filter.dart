import 'package:leemon_app/core/models/sale_model.dart';

List<SaleModel> filterSales(
  List<SaleModel> sales,
  String query, {
  DateTime? date,
}) {
  var result = sales;

  if (date != null) {
    result = result.where((s) {
      final d = s.date.toLocal();
      return d.year == date.year && d.month == date.month && d.day == date.day;
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

String saleNumber(SaleModel s) {
  final isLocalOnly = s.items.any((item) => item.id.trim().isEmpty);
  final n = s.number.trim();
  if (n.isNotEmpty && !isLocalOnly) return n;

  return 'Без номера';
}

String cashierLabel(SaleModel s) {
  if (s.userId.isEmpty) return '—';
  return s.userId.length > 12 ? '${s.userId.substring(0, 12)}…' : s.userId;
}
