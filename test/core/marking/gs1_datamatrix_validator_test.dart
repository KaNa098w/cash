import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/marking/gs1_datamatrix_validator.dart';

void main() {
  const gtin = '04601234567893';

  group('Gs1DataMatrixValidator', () {
    test('accepts the same GS1 structure as backend', () {
      final result = Gs1DataMatrixValidator.validate(
        ']d2\x1D01${gtin}21SERIAL-1\r\n',
        expectedGtin: '4601234567893',
      );

      expect(result.isValid, isTrue);
      expect(result.message, isNull);
    });

    test('rejects website QR codes including www', () {
      final result = Gs1DataMatrixValidator.validate('WWW.example.com/code');

      expect(result.isValid, isFalse);
      expect(result.message, contains('ссылка на сайт'));
    });

    test('rejects another AIM symbology', () {
      final result = Gs1DataMatrixValidator.validate(']Q301${gtin}21ABC');

      expect(result.isValid, isFalse);
      expect(result.message, contains('символика ]d2'));
    });

    test('rejects invalid GTIN check digit', () {
      final result =
          Gs1DataMatrixValidator.validate('01${gtin.substring(0, 13)}021ABC');

      expect(result.isValid, isFalse);
      expect(result.message, contains('контрольную цифру'));
    });

    test('rejects a code belonging to another product', () {
      final result = Gs1DataMatrixValidator.validate(
        '01${gtin}21ABC',
        expectedGtin: '12345670',
      );

      expect(result.isValid, isFalse);
      expect(result.message, contains('не совпадает'));
    });

    test('canonical removes suffix line breaks, AIM prefix and leading GS', () {
      expect(
        Gs1DataMatrixValidator.canonicalCode(']d2\x1D01${gtin}21ABC\n'),
        '01${gtin}21ABC',
      );
    });
  });
}
