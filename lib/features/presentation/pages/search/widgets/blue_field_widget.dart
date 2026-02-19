import 'package:flutter/material.dart';

class BlueField extends StatefulWidget {
  const BlueField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputType? keyboardType;

  @override
  State<BlueField> createState() => _BlueFieldState();
}

class _BlueFieldState extends State<BlueField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant BlueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      _focused = widget.focusNode.hasFocus;
      widget.focusNode.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused ? const Color(0xFF2F80ED) : const Color(0xFF93C5FD);
    final glow = _focused ? const Color(0x662F80ED) : Colors.transparent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.focusNode.requestFocus(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F8FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: _focused ? 2 : 1),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: glow,
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: widget.hint,
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
