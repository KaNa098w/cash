import 'package:flutter/services.dart';

class MarkingKeyboardInputFormatter extends TextInputFormatter {
  const MarkingKeyboardInputFormatter();

  // Do not transliterate scanner data. A Cyrillic payload is not byte-for-byte
  // identical to the marking and must be fixed in the scanner HID settings.
  static String normalize(String value) => value;

  /// Reads scanner key presses using a fixed US layout, independently of the
  /// active Russian/Kazakh system layout.
  static String? scannerCharacter(
    KeyEvent event, {
    bool? shiftPressed,
  }) {
    if (event.character == '\x1D') return event.character;

    final shift = shiftPressed ?? HardwareKeyboard.instance.isShiftPressed;
    final letters = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.keyA: 'a',
      PhysicalKeyboardKey.keyB: 'b',
      PhysicalKeyboardKey.keyC: 'c',
      PhysicalKeyboardKey.keyD: 'd',
      PhysicalKeyboardKey.keyE: 'e',
      PhysicalKeyboardKey.keyF: 'f',
      PhysicalKeyboardKey.keyG: 'g',
      PhysicalKeyboardKey.keyH: 'h',
      PhysicalKeyboardKey.keyI: 'i',
      PhysicalKeyboardKey.keyJ: 'j',
      PhysicalKeyboardKey.keyK: 'k',
      PhysicalKeyboardKey.keyL: 'l',
      PhysicalKeyboardKey.keyM: 'm',
      PhysicalKeyboardKey.keyN: 'n',
      PhysicalKeyboardKey.keyO: 'o',
      PhysicalKeyboardKey.keyP: 'p',
      PhysicalKeyboardKey.keyQ: 'q',
      PhysicalKeyboardKey.keyR: 'r',
      PhysicalKeyboardKey.keyS: 's',
      PhysicalKeyboardKey.keyT: 't',
      PhysicalKeyboardKey.keyU: 'u',
      PhysicalKeyboardKey.keyV: 'v',
      PhysicalKeyboardKey.keyW: 'w',
      PhysicalKeyboardKey.keyX: 'x',
      PhysicalKeyboardKey.keyY: 'y',
      PhysicalKeyboardKey.keyZ: 'z',
    };
    final letter = letters[event.physicalKey];
    if (letter != null) return shift ? letter.toUpperCase() : letter;

    final plain = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.digit0: '0',
      PhysicalKeyboardKey.digit1: '1',
      PhysicalKeyboardKey.digit2: '2',
      PhysicalKeyboardKey.digit3: '3',
      PhysicalKeyboardKey.digit4: '4',
      PhysicalKeyboardKey.digit5: '5',
      PhysicalKeyboardKey.digit6: '6',
      PhysicalKeyboardKey.digit7: '7',
      PhysicalKeyboardKey.digit8: '8',
      PhysicalKeyboardKey.digit9: '9',
      PhysicalKeyboardKey.numpad0: '0',
      PhysicalKeyboardKey.numpad1: '1',
      PhysicalKeyboardKey.numpad2: '2',
      PhysicalKeyboardKey.numpad3: '3',
      PhysicalKeyboardKey.numpad4: '4',
      PhysicalKeyboardKey.numpad5: '5',
      PhysicalKeyboardKey.numpad6: '6',
      PhysicalKeyboardKey.numpad7: '7',
      PhysicalKeyboardKey.numpad8: '8',
      PhysicalKeyboardKey.numpad9: '9',
      PhysicalKeyboardKey.bracketLeft: '[',
      PhysicalKeyboardKey.bracketRight: ']',
      PhysicalKeyboardKey.semicolon: ';',
      PhysicalKeyboardKey.quote: "'",
      PhysicalKeyboardKey.comma: ',',
      PhysicalKeyboardKey.period: '.',
      PhysicalKeyboardKey.slash: '/',
      PhysicalKeyboardKey.backslash: r'\',
      PhysicalKeyboardKey.minus: '-',
      PhysicalKeyboardKey.equal: '=',
      PhysicalKeyboardKey.backquote: '`',
      PhysicalKeyboardKey.space: ' ',
    };
    final shifted = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.digit0: ')',
      PhysicalKeyboardKey.digit1: '!',
      PhysicalKeyboardKey.digit2: '@',
      PhysicalKeyboardKey.digit3: '#',
      PhysicalKeyboardKey.digit4: r'$',
      PhysicalKeyboardKey.digit5: '%',
      PhysicalKeyboardKey.digit6: '^',
      PhysicalKeyboardKey.digit7: '&',
      PhysicalKeyboardKey.digit8: '*',
      PhysicalKeyboardKey.digit9: '(',
      PhysicalKeyboardKey.bracketLeft: '{',
      PhysicalKeyboardKey.bracketRight: '}',
      PhysicalKeyboardKey.semicolon: ':',
      PhysicalKeyboardKey.quote: '"',
      PhysicalKeyboardKey.comma: '<',
      PhysicalKeyboardKey.period: '>',
      PhysicalKeyboardKey.slash: '?',
      PhysicalKeyboardKey.backslash: '|',
      PhysicalKeyboardKey.minus: '_',
      PhysicalKeyboardKey.equal: '+',
      PhysicalKeyboardKey.backquote: '~',
    };
    return shift
        ? shifted[event.physicalKey] ?? plain[event.physicalKey]
        : plain[event.physicalKey];
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalize(newValue.text);
    if (normalized == newValue.text) return newValue;
    return newValue.copyWith(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
      composing: TextRange.empty,
    );
  }
}

class Gs1DataMatrixValidation {
  const Gs1DataMatrixValidation._(
    this.isValid,
    this.message, {
    this.canonical,
    this.gtin,
  });

  final bool isValid;
  final String? message;
  final String? canonical;
  final String? gtin;

  factory Gs1DataMatrixValidation.valid({
    required String canonical,
    required String gtin,
  }) =>
      Gs1DataMatrixValidation._(
        true,
        null,
        canonical: canonical,
        gtin: gtin,
      );

  factory Gs1DataMatrixValidation.invalid(
    String message, {
    String? canonical,
    String? gtin,
  }) =>
      Gs1DataMatrixValidation._(
        false,
        message,
        canonical: canonical,
        gtin: gtin,
      );
}

class Gs1DataMatrixValidator {
  static const gs1DataMatrixSymbology = ']d2';
  static const _groupSeparator = '\x1D';

  static String _trimTrailingLineBreaks(String value) =>
      value.replaceFirst(RegExp(r'[\r\n]+$'), '');

  static String canonicalCode(String rawValue) {
    var value = _trimTrailingLineBreaks(rawValue);
    if (value.startsWith(gs1DataMatrixSymbology)) {
      value = value.substring(gs1DataMatrixSymbology.length);
    }
    if (value.startsWith(_groupSeparator)) {
      value = value.substring(1);
    }
    if (value.startsWith('(01)')) {
      value = value.replaceAllMapped(
        RegExp(r'\((\d{2,4})\)'),
        (match) => match.group(1)!,
      );
    }
    return value;
  }

  static String? normalizeGtin14(String? value) {
    final raw = value?.trim();
    if (raw == null || !RegExp(r'^\d+$').hasMatch(raw)) return null;
    if (!const {8, 12, 13, 14}.contains(raw.length)) return null;
    return raw.padLeft(14, '0');
  }

  static Gs1DataMatrixValidation validate(
    String raw, {
    String? expectedGtin,
  }) {
    final value = _trimTrailingLineBreaks(raw);
    if (value.isEmpty) {
      return Gs1DataMatrixValidation.invalid(
        'Отсканируйте код маркировки с упаковки.',
      );
    }

    if (RegExp(r'^(?:https?://|www\.)', caseSensitive: false).hasMatch(value)) {
      return Gs1DataMatrixValidation.invalid(
        'Отсканирована ссылка на сайт, а не код маркировки товара.',
      );
    }

    if (value.startsWith(']') && !value.startsWith(gs1DataMatrixSymbology)) {
      return Gs1DataMatrixValidation.invalid(
        'Этот код не является кодом маркировки товара. Попробуйте ещё раз.',
      );
    }

    final content = canonicalCode(value);
    final match =
        RegExp(r'^01(\d{14})21(.+)$', dotAll: true).firstMatch(content);
    if (match == null) {
      return Gs1DataMatrixValidation.invalid(
        'Код маркировки не распознан. Попробуйте отсканировать ещё раз.',
      );
    }

    final gtin = match.group(1)!;
    if (!hasValidGtinCheckDigit(gtin)) {
      return Gs1DataMatrixValidation.invalid(
        'GTIN в коде маркировки имеет неверную контрольную цифру.',
        canonical: content,
        gtin: gtin,
      );
    }

    final normalizedExpected = normalizeGtin14(expectedGtin);
    if (normalizedExpected != null && normalizedExpected != gtin) {
      return Gs1DataMatrixValidation.invalid(
        'Отсканирован код другого товара. Выберите код с нужной упаковки.',
        canonical: content,
        gtin: gtin,
      );
    }
    return Gs1DataMatrixValidation.valid(canonical: content, gtin: gtin);
  }

  static String? gtin(String value) => RegExp(r'^01(\d{14})21', dotAll: true)
      .firstMatch(canonicalCode(value))
      ?.group(1);

  static bool hasValidGtinCheckDigit(String gtin) {
    if (!RegExp(r'^\d{14}$').hasMatch(gtin)) return false;
    var sum = 0;
    for (var index = 0; index < 13; index++) {
      final digit = int.parse(gtin[index]);
      sum += digit * (index.isEven ? 3 : 1);
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(gtin[13]);
  }
}
