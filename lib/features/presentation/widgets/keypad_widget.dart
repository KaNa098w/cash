import 'package:flutter/material.dart';

class Keypad extends StatelessWidget {
  const Keypad({
    required this.onTap,
    this.keyHeight = 58,
    this.fontSize = 22,
  });

  final void Function(String) onTap;
  final double keyHeight;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    const keyGrey = Color(0xFF999999);
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', '⌫'],
    ];
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
                      height: keyHeight,
                      child: TextButton(
                        onPressed: () => onTap(r[i]),
                        style: TextButton.styleFrom(
                          backgroundColor: keyGrey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          r[i],
                          style: TextStyle(
                              fontSize: fontSize, fontWeight: FontWeight.w600),
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
