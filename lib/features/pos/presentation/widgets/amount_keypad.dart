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
  });

  final String text; // текущее значение (то, что в TextField)
  final AmountChanged onChanged;

  final List<List<String>> rows;
  final bool showQuickRows;

  String _applyToken(String current, String token) {
    var t = current;

    if (token == '⌫') {
      if (t.isNotEmpty) t = t.substring(0, t.length - 1);
      return t;
    }

    if (token == '.') {
      if (!t.contains('.')) {
        t = t.isEmpty ? '0.' : '$t.';
      }
      return t;
    }

    // цифра
    t = t == '0' ? token : '$t$token';

    // нормализуем ведущие нули
    t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return t;
  }

  String _applyQuick(String current, String v) {
    final inc = int.parse(v.replaceAll(RegExp(r'[^0-9]'), ''));
    final curr = double.tryParse(current.replaceAll(',', '.')) ?? 0;
    final next = curr + inc;

    // аккуратное форматирование
    var s = next.toStringAsFixed(2);
    if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
    else if (s.endsWith('0')) s = s.substring(0, s.length - 1);

    return s;
  }

  @override
  Widget build(BuildContext context) {
    const keyGrey = Color(0xFF999999);

    const keys = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // цифровая клавиатура
        Column(
          children: [
            for (final r in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (int i = 0; i < r.length; i++) ...[
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextButton(
                            onPressed: () {
                              final next = _applyToken(text, r[i]);
                              onChanged(next);
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: keyGrey,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              r[i],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
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
                      height: 40,
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
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
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
