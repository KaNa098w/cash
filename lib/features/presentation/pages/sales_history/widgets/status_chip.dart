import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(
      {super.key, required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 16,
          height: 1.4,
          letterSpacing: 0.34,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
