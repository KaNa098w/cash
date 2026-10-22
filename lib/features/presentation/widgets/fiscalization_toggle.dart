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
      const Text(
          '\u0424\u0438\u0441\u043a\u0430\u043b\u044c\u043d\u044b\u0439 \u0447\u0435\u043a',
          style: TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Switch(
        value: mode == FiscalizationMode.fiscal,
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0xFF22A559)
                : null),
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        onChanged: locked
            ? null
            : (value) => onChanged(value
                ? FiscalizationMode.fiscal
                : (hasMarkedProducts
                    ? FiscalizationMode.automatic
                    : FiscalizationMode.skip)),
      ),
    ]);
  }
}
