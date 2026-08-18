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
  static String removeAimPrefix(String value) =>
      value.startsWith(']d2') ? value.substring(3) : value;

  static String canonicalCode(String rawValue) => removeAimPrefix(rawValue);

  static String? normalizeGtin14(String? value) {
    final raw = value?.trim();
    if (raw == null || !RegExp(r'^\d{1,14}$').hasMatch(raw)) return null;
    return raw.padLeft(14, '0');
  }

  static Gs1DataMatrixValidation validate(
    String raw, {
    String? expectedGtin,
  }) {
    if (raw.isEmpty) {
      return Gs1DataMatrixValidation.invalid('Сканируйте DataMatrix');
    }
    if (raw.startsWith(']') && !raw.startsWith(']d2')) {
      return Gs1DataMatrixValidation.invalid(
        'Нужен GS1 DataMatrix (AIM-префикс ]d2). QR Code не принимается',
      );
    }

    final data = removeAimPrefix(raw);
    if (data.startsWith('http://') || data.startsWith('https://')) {
      return Gs1DataMatrixValidation.invalid(
        'Это QR-код. Отсканируйте Data Matrix маркировки товара.',
      );
    }
    if (!data.startsWith('01') || data.length < 18) {
      return Gs1DataMatrixValidation.invalid(
        'Код не содержит обязательный идентификатор GTIN (01).',
      );
    }

    final gtin = data.substring(2, 16);
    if (!RegExp(r'^\d{14}$').hasMatch(gtin) || !_hasValidCheckDigit(gtin)) {
      return Gs1DataMatrixValidation.invalid(
        'Контрольная цифра GTIN некорректна.',
      );
    }

    if (data.length < 18 || data.substring(16, 18) != '21') {
      return Gs1DataMatrixValidation.invalid(
        'Код не содержит серийный номер (21).',
      );
    }
    final serial = data.substring(18);
    final serialValue = serial.split(String.fromCharCode(29)).first;
    if (serialValue.isEmpty) {
      return Gs1DataMatrixValidation.invalid(
        'Код не содержит серийный номер (21).',
      );
    }

    if ((expectedGtin ?? '').trim().isNotEmpty) {
      final normalizedExpected = normalizeGtin14(expectedGtin);
      if (normalizedExpected == null) {
        return Gs1DataMatrixValidation.invalid(
          'Некорректный GTIN в карточке товара.',
        );
      }
      if (normalizedExpected != gtin) {
        return Gs1DataMatrixValidation.invalid(
          'GTIN маркировки не совпадает с выбранным товаром.',
        );
      }
    }
    return Gs1DataMatrixValidation.valid();
  }

  static bool _hasValidCheckDigit(String gtin) {
    var sum = 0;
    for (var index = 0; index < 13; index++) {
      final digit = int.parse(gtin[index]);
      sum += digit * (index.isEven ? 3 : 1);
    }
    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(gtin[13]);
  }
}
