import 'package:intl/intl.dart';

String fmtSaleDate(DateTime d) {
  return DateFormat('d MMMM y   HH:mm', 'ru').format(d.toLocal());
}

String money0(dynamic value) {
  final num v = toNum(value);
  final fmt = NumberFormat('#,##0', 'ru');
  return '${fmt.format(v)} ₸';
}

num toNum(dynamic v) {
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}

int toIntQty(dynamic v) {
  final n = toNum(v).round();
  return n < 0 ? 0 : n;
}

int toIntRefunded(dynamic v) {
  final n = toNum(v).round();
  return n < 0 ? 0 : n;
}

String returnedTextRu(int refunded) {
  final abs = refunded.abs();
  final n = abs % 100;
  final n1 = abs % 10;

  String noun;
  if (n > 10 && n < 20) {
    noun = 'товаров';
  } else if (n1 == 1) {
    noun = 'товар';
  } else if (n1 >= 2 && n1 <= 4) {
    noun = 'товара';
  } else {
    noun = 'товаров';
  }

  final verb = abs == 1 ? 'возвращен' : 'возвращено';
  return '$refunded $noun $verb';
}
