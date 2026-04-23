import 'package:flutter/material.dart';

typedef AmountChanged = void Function(String text);

class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.text,
    required this.onChanged,
    this.rows = const [
      ['+200', '+500', '+1 000'],
      ['+2 000', '+5 000', '+10 000'],
    ],
    this.showQuickRows = true,
    this.allowDecimal = true,
    this.maxLength,
    this.keyColor = const Color(0xFF999999),
    this.keyTextColor = Colors.white,
    this.disabledKeyColor,
    this.keyHeight = 58,
    this.keyRadius = 10,
    this.keySpacing = 8,
  });

  final String text;
  final AmountChanged onChanged;

  final List<List<String>> rows;
  final bool showQuickRows;

  /// Для PIN ставь false
  final bool allowDecimal;

  /// Для PIN ставь 4 (или сколько нужно)
  final int? maxLength;
  final Color keyColor;
  final Color keyTextColor;
  final Color? disabledKeyColor;
  final double keyHeight;
  final double keyRadius;
  final double keySpacing;

  String _applyToken(String current, String token) {
    var t = current;

    if (token.isEmpty) return t;

    if (token == '⌫') {
      if (t.isNotEmpty) t = t.substring(0, t.length - 1);
      return t;
    }

    if (token == '.') {
      if (!allowDecimal) return t;
      if (!t.contains('.')) {
        t = t.isEmpty ? '0.' : '$t.';
      }
      return t;
    }

    // цифра
    if (maxLength != null && t.length >= maxLength!) return t;

    t = t == '0' ? token : '$t$token';

    // нормализуем ведущие нули
    t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return t;
  }

  String _applyQuick(String current, String v) {
    final inc = int.parse(v.replaceAll(RegExp(r'[^0-9]'), ''));
    final curr = double.tryParse(current.replaceAll(',', '.')) ?? 0;
    final next = curr + inc;

    var s = next.toStringAsFixed(2);
    if (s.endsWith('.00')) {
      s = s.substring(0, s.length - 3);
    } else if (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }

    return s;
  }

  @override
  Widget build(BuildContext context) {
    final keys = <List<String>>[
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      [allowDecimal ? '.' : '', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            for (final r in keys)
              Padding(
                padding: EdgeInsets.only(bottom: keySpacing),
                child: Row(
                  children: [
                    for (int i = 0; i < r.length; i++) ...[
                      Expanded(
                        child: SizedBox(
                          height: keyHeight,
                          child: TextButton(
                            onPressed: r[i].isEmpty
                                ? null
                                : () {
                                    final next = _applyToken(text, r[i]);
                                    onChanged(next);
                                  },
                            style: TextButton.styleFrom(
                              backgroundColor: r[i].isEmpty
                                  ? disabledKeyColor ??
                                      keyColor.withValues(alpha: 0.35)
                                  : keyColor,
                              foregroundColor: keyTextColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(keyRadius),
                              ),
                            ),
                            child: Text(
                              r[i].isEmpty ? '' : r[i],
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ).copyWith(color: keyTextColor),
                            ),
                          ),
                        ),
                      ),
                      if (i != r.length - 1) SizedBox(width: keySpacing),
                    ],
                  ],
                ),
              ),
          ],
        ),
        if (showQuickRows) ...[
          const SizedBox(height: 6),
          _QuickRows(
            rows: rows,
            onTap: (v) {
              final next = _applyQuick(text, v);
              onChanged(next);
            },
          ),
        ],
      ],
    );
  }
}

class _QuickRows extends StatelessWidget {
  const _QuickRows({required this.rows, required this.onTap});

  final List<List<String>> rows;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (int i = 0; i < r.length; i++) ...[
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => onTap(r[i]),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9D9D9),
                          side: const BorderSide(color: Colors.transparent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          r[i],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i != r.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
