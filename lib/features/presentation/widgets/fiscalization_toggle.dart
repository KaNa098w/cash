import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/fiscalization_mode.dart';

class FiscalizationToggle extends StatelessWidget {
  const FiscalizationToggle(
      {super.key,
      required this.enabled,
      required this.hasMarkedProducts,
      required this.mode,
      required this.onChanged,
      this.locked = false});
  final bool enabled;
  final bool hasMarkedProducts;
  final FiscalizationMode mode;
  final bool locked;
  final ValueChanged<FiscalizationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      const Icon(Icons.receipt_long_outlined,
          size: 20, color: Color(0xFF536074)),
      const SizedBox(width: 8),
      const Text('Фискальный чек', style: TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Switch(
          value: mode == FiscalizationMode.fiscal,
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF22A559);
            }
            return null;
          }),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected) ? Colors.white : null;
          }),
          onChanged: locked || hasMarkedProducts
              ? null
              : (value) => onChanged(
                  value ? FiscalizationMode.fiscal : FiscalizationMode.skip)),
      if (hasMarkedProducts)
        const Flexible(
            child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('Обязателен для маркировки',
                    style: TextStyle(fontSize: 11, color: Color(0xFF536074))))),
    ]);
  }
}
