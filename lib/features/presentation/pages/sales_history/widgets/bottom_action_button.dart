import 'package:flutter/material.dart';

class BottomActionButton extends StatelessWidget {
  const BottomActionButton({
    super.key,
    required this.label,
    required this.bg,
    required this.onTap,
    this.width = 190,
    this.height = 49,
    this.fontSize = 18,
    this.loading = false,
  });

  final String label;
  final Color bg;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final double fontSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: bg,
          foregroundColor: Colors.white,
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
