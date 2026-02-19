import 'package:flutter/material.dart';

class QtyBtn extends StatelessWidget {
  const QtyBtn({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: disabled ? Colors.black.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Icon(
          icon,
          size: 18,
          color: disabled ? Colors.black.withOpacity(0.25) : Colors.black87,
        ),
      ),
    );
  }
}
