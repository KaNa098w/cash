
import 'package:flutter/material.dart';

class BottomBtn extends StatelessWidget {
  const BottomBtn({
    required this.text,
    required this.bg,
    required this.onTap,
    this.enabled = true,
  });

  final String text;
  final Color bg;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          text,
          style:
              const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
      ),
    );
  }
}