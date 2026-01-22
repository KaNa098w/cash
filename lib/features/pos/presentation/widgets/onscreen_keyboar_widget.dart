import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class OnScreenKeyboardSheet extends StatelessWidget {
  const OnScreenKeyboardSheet({
    required this.controller,
    required this.onEnter,
  });

  final TextEditingController controller;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F7FB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Grabber(),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.keyboard_alt_outlined),
                  const SizedBox(width: 8),
                  const Text(
                    'Клавиатура',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              _Keyboard(
                controller: controller,
                onEnter: onEnter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _Keyboard extends StatefulWidget {
  const _Keyboard({
    required this.controller,
    required this.onEnter,
  });

  final TextEditingController controller;
  final VoidCallback onEnter;

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  bool _shift = false;

  // Можно под себя: кириллица/цифры/скан-коды и т.д.
  static const _row1 = ['1','2','3','4','5','6','7','8','9','0'];
  static const _row2 = ['q','w','e','r','t','y','u','i','o','p'];
  static const _row3 = ['a','s','d','f','g','h','j','k','l'];
  static const _row4 = ['z','x','c','v','b','n','m'];

  void _insert(String text) {
    final ctrl = widget.controller;
    final value = ctrl.value;
    final selection = value.selection;

    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;

    final newText = value.text.replaceRange(start, end, text);
    final newOffset = start + text.length;

    ctrl.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }

  void _backspace() {
    final ctrl = widget.controller;
    final value = ctrl.value;
    final selection = value.selection;

    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;

    if (start != end) {
      // удалить выделение
      ctrl.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
        composing: TextRange.empty,
      );
      return;
    }

    if (start == 0) return;

    final newText = value.text.replaceRange(start - 1, start, '');
    ctrl.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start - 1),
      composing: TextRange.empty,
    );
  }

  Widget _key(String label, {VoidCallback? onTap, int flex = 1}) {
    final display = _shift ? label.toUpperCase() : label;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap ?? () => _insert(display),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  display,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(IconData icon, {required VoidCallback onTap, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Icon(icon, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: _row1.map((k) => _key(k)).toList()),
        Row(children: _row2.map((k) => _key(k)).toList()),
        Row(
          children: [
            _actionKey(
              _shift ? Icons.keyboard_capslock : Icons.keyboard_arrow_up,
              onTap: () => setState(() => _shift = !_shift),
              flex: 2,
            ),
            ..._row3.map((k) => _key(k)).toList(),
            _actionKey(Icons.backspace_outlined, onTap: _backspace, flex: 2),
          ],
        ),
        Row(children: _row4.map((k) => _key(k)).toList()),
        Row(
          children: [
            _key('Пробел', onTap: () => _insert(' '), flex: 6),
            _actionKey(Icons.subdirectory_arrow_left, onTap: widget.onEnter, flex: 2),
          ],
        ),
      ],
    );
  }
}
