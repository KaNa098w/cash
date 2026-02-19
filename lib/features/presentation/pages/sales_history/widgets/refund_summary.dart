import 'package:flutter/material.dart';
import '../utils/formatters.dart';

class RefundSummary extends StatelessWidget {
  const RefundSummary({super.key, required this.count, required this.total});

  final int count;
  final num total;

  @override
  Widget build(BuildContext context) {
    final t = money0(total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text('Выбрано: $count', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 18),
          Text('Итого: $t', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
