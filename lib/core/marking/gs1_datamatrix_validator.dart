import 'package:flutter/services.dart';

class MarkingKeyboardInputFormatter extends TextInputFormatter {
  const MarkingKeyboardInputFormatter();

  static const _russianToEnglish = <String, String>{
    'й': 'q',
    'ц': 'w',
    'у': 'e',
    'к': 'r',
    'е': 't',
    'н': 'y',
    'г': 'u',
    'ш': 'i',
    'щ': 'o',
    'з': 'p',
    'х': '[',
    'ъ': ']',
    'ф': 'a',
    'ы': 's',
    'в': 'd',
    'а': 'f',
    'п': 'g',
    'р': 'h',
    'о': 'j',
    'л': 'k',
    'д': 'l',
    'ж': ';',
    'э': "'",
    'я': 'z',
    'ч': 'x',
    'с': 'c',
    'м': 'v',
    'и': 'b',
    'т': 'n',
    'ь': 'm',
    'б': ',',
    'ю': '.',
    'Й': 'Q',
    'Ц': 'W',
    'У': 'E',
    'К': 'R',
    'Е': 'T',
    'Н': 'Y',
    'Г': 'U',
    'Ш': 'I',
    'Щ': 'O',
    'З': 'P',
    'Х': '{',
    'Ъ': '}',
    'Ф': 'A',
    'Ы': 'S',
    'В': 'D',
    'А': 'F',
    'П': 'G',
    'Р': 'H',
    'О': 'J',
    'Л': 'K',
    'Д': 'L',
    'Ж': ':',
    'Э': '"',
    'Я': 'Z',
    'Ч': 'X',
    'С': 'C',
    'М': 'V',
    'И': 'B',
    'Т': 'N',
    'Ь': 'M',
    'Б': '<',
    'Ю': '>',
  };

  static String normalize(String value) => value
      .split('')
      .map((character) => _russianToEnglish[character] ?? character)
      .join();

  /// Returns the character for the physical key as if the US English layout
  /// were active. Hardware scanners emulate a keyboard, so this prevents the
  /// current Russian/Kazakh system layout from changing barcode characters.
  static String? englishCharacter(KeyEvent event) {
    if (event.character == '\x1D') return event.character;

    final shift = HardwareKeyboard.instance.isShiftPressed;
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
  const Gs1DataMatrixValidation._(this.isValid, this.message);

  final bool isValid;
  final String? message;

  factory Gs1DataMatrixValidation.valid() =>
      const Gs1DataMatrixValidation._(true, null);

  factory Gs1DataMatrixValidation.invalid(String message) =>
      Gs1DataMatrixValidation._(false, message);
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
    return value.startsWith(_groupSeparator) ? value.substring(1) : value;
  }

  static String? normalizeGtin14(String? value) {
    final raw = value?.trim();
    if (raw == null || !RegExp(r'^\d{1,14}$').hasMatch(raw)) return null;
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
      );
    }

    final normalizedExpected = normalizeGtin14(expectedGtin);
    if (normalizedExpected != null && normalizedExpected != gtin) {
      return Gs1DataMatrixValidation.invalid(
        'Отсканирован код другого товара. Выберите код с нужной упаковки.',
      );
    }
    return Gs1DataMatrixValidation.valid();
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
