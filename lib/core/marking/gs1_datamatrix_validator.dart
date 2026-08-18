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

    final data = raw.startsWith(']d2') ? raw.substring(3) : raw;
    if (data.startsWith('http://') || data.startsWith('https://')) {
      return Gs1DataMatrixValidation.invalid(
        'Ссылка или QR Code не является кодом маркировки',
      );
    }
    if (!data.startsWith('01') || data.length < 18) {
      return Gs1DataMatrixValidation.invalid(
        'В DataMatrix отсутствует обязательное поле (01) GTIN',
      );
    }

    final gtin = data.substring(2, 16);
    if (!RegExp(r'^\d{14}$').hasMatch(gtin) || !_hasValidCheckDigit(gtin)) {
      return Gs1DataMatrixValidation.invalid(
        'Некорректный GTIN или его контрольная цифра',
      );
    }

    final remainder = data.substring(16);
    final serialStart = remainder.startsWith('21')
        ? 0
        : remainder.indexOf('${String.fromCharCode(29)}21');
    if (serialStart < 0) {
      return Gs1DataMatrixValidation.invalid(
        'В DataMatrix отсутствует обязательное поле (21) серийного номера',
      );
    }
    final serial =
        remainder.substring(serialStart + (serialStart == 0 ? 2 : 3));
    final serialValue = serial.split(String.fromCharCode(29)).first;
    if (serialValue.isEmpty) {
      return Gs1DataMatrixValidation.invalid('Серийный номер (21) пуст');
    }

    var expected = (expectedGtin ?? '').replaceAll(RegExp(r'\D'), '');
    if (expected.length == 16 && expected.startsWith('01')) {
      expected = expected.substring(2);
    }
    if (expected.isNotEmpty) {
      if (expected.length > 14) {
        return Gs1DataMatrixValidation.invalid(
          'Некорректный GTIN в карточке товара',
        );
      }
      final normalizedExpected = expected.padLeft(14, '0');
      if (normalizedExpected != gtin) {
        return Gs1DataMatrixValidation.invalid(
          'GTIN кода не совпадает с карточкой товара',
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
