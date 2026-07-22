import 'package:flutter/material.dart';

class OnScreenKeyboardSheet extends StatelessWidget {
  const OnScreenKeyboardSheet({
    super.key,
    required this.controllerGetter,
    required this.onEnter,
    required this.onClose,
    this.appendOnFullSelection = false,
  });

  final TextEditingController Function() controllerGetter;
  final VoidCallback onEnter;
  final VoidCallback onClose;
  final bool appendOnFullSelection;

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
            color: Color(0xFFE2E6EF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Grabber(), 
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
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Keyboard(
                controllerGetter: controllerGetter,
                onEnter: onEnter,
                appendOnFullSelection: appendOnFullSelection,
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
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _Keyboard extends StatefulWidget {
  const _Keyboard({
    required this.controllerGetter,
    required this.onEnter,
    required this.appendOnFullSelection,
  });

  final TextEditingController Function() controllerGetter;
  final VoidCallback onEnter;
  final bool appendOnFullSelection;

  @override
  State<_Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<_Keyboard> {
  bool _shift = false;
  _KeyboardLanguage _language = _KeyboardLanguage.ru;

  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _kzTopRow = ['ә', 'і', 'ң', 'ғ', 'ү', 'ұ', 'қ', 'ө', 'һ'];

  static const _ruRow1 = [
    'й',
    'ц',
    'у',
    'к',
    'е',
    'н',
    'г',
    'ш',
    'щ',
    'з',
    'х',
    'ъ',
  ];
  static const _ruRow2 = [
    'ф',
    'ы',
    'в',
    'а',
    'п',
    'р',
    'о',
    'л',
    'д',
    'ж',
    'э',
  ];
  static const _ruRow3 = ['я', 'ч', 'с', 'м', 'и', 'т', 'ь', 'б', 'ю'];

  static const _enRow1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _enRow2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _enRow3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  TextEditingController get _ctrl => widget.controllerGetter();

  List<String> get _lettersRow1 => switch (_language) {
        _KeyboardLanguage.ru => _ruRow1,
        _KeyboardLanguage.kz => _ruRow1,
        _KeyboardLanguage.en => _enRow1,
      };

  List<String> get _lettersRow2 => switch (_language) {
        _KeyboardLanguage.ru => _ruRow2,
        _KeyboardLanguage.kz => _ruRow2,
        _KeyboardLanguage.en => _enRow2,
      };

  List<String> get _lettersRow3 => switch (_language) {
        _KeyboardLanguage.ru => _ruRow3,
        _KeyboardLanguage.kz => _ruRow3,
        _KeyboardLanguage.en => _enRow3,
      };

  String get _languageLabel => switch (_language) {
        _KeyboardLanguage.ru => 'RU',
        _KeyboardLanguage.kz => 'KZ',
        _KeyboardLanguage.en => 'EN',
      };

  void _nextLanguage() {
    setState(() {
      _language = switch (_language) {
        _KeyboardLanguage.ru => _KeyboardLanguage.kz,
        _KeyboardLanguage.kz => _KeyboardLanguage.en,
        _KeyboardLanguage.en => _KeyboardLanguage.ru,
      };
    });
  }

  void _insert(String text) {
    final ctrl = _ctrl;
    final value = ctrl.value;
    final selection = value.selection;

    var start = selection.start < 0 ? value.text.length : selection.start;
    var end = selection.end < 0 ? value.text.length : selection.end;
    final fullSelection =
        start == 0 && end == value.text.length && value.text.isNotEmpty;
    if (widget.appendOnFullSelection && fullSelection) {
      start = value.text.length;
      end = value.text.length;
    }

    final newText = value.text.replaceRange(start, end, text);
    final newOffset = start + text.length;

    ctrl.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
  }

  void _backspace() {
    final ctrl = _ctrl;
    final value = ctrl.value;
    final selection = value.selection;

    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;

    if (start != end) {
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

  Widget _textKey(String label, {VoidCallback? onTap, int flex = 1}) {
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

  Widget _actionKey(
    Widget child, {
    required VoidCallback onTap,
    int flex = 1,
    Color backgroundColor = const Color(0xFF111827),
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(child: child),
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
        if (_language == _KeyboardLanguage.kz)
          Row(children: _kzTopRow.map((k) => _textKey(k)).toList()),
        Row(
          children: [
            ..._digits.map((k) => _textKey(k)),
            _textKey('+'),
          ],
        ),
        Row(children: _lettersRow1.map((k) => _textKey(k)).toList()),
        Row(
          children: [
            _actionKey(
              Icon(
                _shift ? Icons.keyboard_capslock : Icons.keyboard_arrow_up,
                color: Colors.white,
              ),
              onTap: () => setState(() => _shift = !_shift),
              flex: 2,
            ),
            ..._lettersRow2.map((k) => _textKey(k)),
            _actionKey(
              const Icon(Icons.backspace_outlined, color: Colors.white),
              onTap: _backspace,
              flex: 2,
            ),
          ],
        ),
        Row(children: _lettersRow3.map((k) => _textKey(k)).toList()),
        Row(
          children: [
            _actionKey(
              Text(
                _languageLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: _nextLanguage,
              flex: 2,
              backgroundColor: const Color(0xFF2563EB),
            ),
            _textKey('-', flex: 1),
            _textKey('Пробел', onTap: () => _insert(' '), flex: 5),
            _actionKey(
              const Icon(Icons.subdirectory_arrow_left, color: Colors.white),
              onTap: widget.onEnter,
              flex: 2,
              backgroundColor: const Color(0xFF0F766E),
            ),
          ],
        ),
      ],
    );
  }
}

enum _KeyboardLanguage { ru, kz, en }
