import 'package:intl/intl.dart';

final _fmt =
    NumberFormat.currency(locale: 'ru_RU', symbol: 'т', decimalDigits: 2);

String money(num v) => _fmt.format(v);
String number(num v) => NumberFormat('#,##0.##', 'ru_RU').format(v);
