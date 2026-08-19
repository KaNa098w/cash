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
        'Отсканируйте код маркировки GS1 DataMatrix.',
      );
    }

    if (RegExp(r'^(?:https?://|www\.)', caseSensitive: false).hasMatch(value)) {
      return Gs1DataMatrixValidation.invalid(
        'Отсканирована ссылка на сайт, а не код маркировки товара.',
      );
    }

    if (value.startsWith(']') && !value.startsWith(gs1DataMatrixSymbology)) {
      return Gs1DataMatrixValidation.invalid(
        'Отсканирован не GS1 DataMatrix. Ожидается символика ]d2.',
      );
    }

    final content = canonicalCode(value);
    final match =
        RegExp(r'^01(\d{14})21(.+)$', dotAll: true).firstMatch(content);
    if (match == null) {
      return Gs1DataMatrixValidation.invalid(
        'Код маркировки должен содержать GS1-поля (01) GTIN и (21) серийный номер.',
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
        'GTIN $gtin из DataMatrix не совпадает с GTIN $normalizedExpected товара.',
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
