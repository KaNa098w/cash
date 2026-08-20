import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/marking/gs1_datamatrix_validator.dart';

void main() {
  const gtin = '04601234567893';
  const suppliedGtin = '05995327133461';
  const humanReadable =
      '(01)05995327133461(21)6179677981535(91)KZF0(92)eFRRb4rDhg+1W6T8MwquzFYdZg861rYpsQdbCmu5Uk8=';
  const compact =
      '010599532713346121617967798153591KZF092eFRRb4rDhg+1W6T8MwquzFYdZg861rYpsQdbCmu5Uk8=';
  const secondScannerCode =
      '(01)04870004336063(21)NJowzqSJRCuFH(91)KZF0(92)SlRQN3x9NuYICI5rcXnpr8cJt5y5BdEc4h1F9coalOI=';
  const secondScannerCanonical =
      '010487000433606321NJowzqSJRCuFH91KZF092SlRQN3x9NuYICI5rcXnpr8cJt5y5BdEc4h1F9coalOI=';

  group('Gs1DataMatrixValidator', () {
    test('normalizes supplied human-readable and compact forms identically',
        () {
      expect(Gs1DataMatrixValidator.canonicalCode(humanReadable), compact);
      expect(Gs1DataMatrixValidator.canonicalCode(compact), compact);

      for (final code in [humanReadable, compact]) {
        final result = Gs1DataMatrixValidator.validate(
          code,
          expectedGtin: suppliedGtin,
        );
        expect(result.isValid, isTrue);
        expect(result.canonical, compact);
        expect(result.gtin, suppliedGtin);
      }
    });

    test('accepts the same GS1 structure as backend', () {
      final result = Gs1DataMatrixValidator.validate(
        ']d2\x1D01${gtin}21SERIAL-1\r\n',
        expectedGtin: '4601234567893',
      );

      expect(result.isValid, isTrue);
      expect(result.message, isNull);
      expect(result.canonical, '01${gtin}21SERIAL-1');
      expect(result.gtin, gtin);
    });

    test('accepts the human-readable code from the second scanner', () {
      final result = Gs1DataMatrixValidator.validate(secondScannerCode);

      expect(result.isValid, isTrue);
      expect(result.canonical, secondScannerCanonical);
      expect(result.gtin, '04870004336063');
    });

    test('rejects website QR codes including www', () {
      final result = Gs1DataMatrixValidator.validate('WWW.example.com/code');

      expect(result.isValid, isFalse);
      expect(result.message, contains('ссылка на сайт'));
    });

    test('rejects another AIM symbology', () {
      final result = Gs1DataMatrixValidator.validate(']Q301${gtin}21ABC');

      expect(result.isValid, isFalse);
      expect(result.message, contains('не является кодом маркировки'));
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
      expect(result.message, contains('код другого товара'));
    });

    test('canonical removes suffix line breaks, AIM prefix and leading GS', () {
      expect(
        Gs1DataMatrixValidator.canonicalCode(']d2\x1D01${gtin}21ABC\n'),
        '01${gtin}21ABC',
      );
    });

    test('preserves internal GS separators and crypto tail byte-for-byte', () {
      const tail = 'SERIAL91inside\x1D91AbC+92xYz=';
      const code = '01${gtin}21$tail\r\n';

      final result = Gs1DataMatrixValidator.validate(code);

      expect(result.isValid, isTrue);
      expect(result.canonical, '01${gtin}21$tail');
    });

    test('removes only one leading GS separator', () {
      final result = Gs1DataMatrixValidator.validate(
        ']d2\x1D\x1D01${gtin}21ABC',
      );

      expect(result.isValid, isFalse);
      expect(
        Gs1DataMatrixValidator.canonicalCode(
          ']d2\x1D\x1D01${gtin}21ABC',
        ),
        '\x1D01${gtin}21ABC',
      );
    });

    test('does not transliterate Cyrillic scanner output', () {
      const scannerOutput = 'АБВгд';
      expect(
        MarkingKeyboardInputFormatter.normalize(scannerOutput),
        scannerOutput,
      );
    });

    test('keeps parentheses emitted as Shift+9 and Shift+0', () {
      const openingParenthesis = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit9,
        logicalKey: LogicalKeyboardKey.parenthesisLeft,
        character: '(',
        timeStamp: Duration.zero,
      );
      const closingParenthesis = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit0,
        logicalKey: LogicalKeyboardKey.parenthesisRight,
        character: ')',
        timeStamp: Duration.zero,
      );

      expect(
        MarkingKeyboardInputFormatter.scannerCharacter(
          openingParenthesis,
          shiftPressed: true,
        ),
        '(',
      );
      expect(
        MarkingKeyboardInputFormatter.scannerCharacter(
          closingParenthesis,
          shiftPressed: true,
        ),
        ')',
      );
    });

    test('uses US letters for scanner keys on a Cyrillic layout', () {
      const event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        character: 'ф',
        timeStamp: Duration.zero,
      );

      expect(
        MarkingKeyboardInputFormatter.scannerCharacter(
          event,
          shiftPressed: false,
        ),
        'a',
      );
      expect(
        MarkingKeyboardInputFormatter.scannerCharacter(
          event,
          shiftPressed: true,
        ),
        'A',
      );
    });

    test('normalizes only supported product barcode lengths to GTIN-14', () {
      expect(
          Gs1DataMatrixValidator.normalizeGtin14('12345670'), '00000012345670');
      expect(Gs1DataMatrixValidator.normalizeGtin14('123456789012'),
          '00123456789012');
      expect(Gs1DataMatrixValidator.normalizeGtin14('1234567890123'),
          '01234567890123');
      expect(Gs1DataMatrixValidator.normalizeGtin14('12345678901234'),
          '12345678901234');
      expect(Gs1DataMatrixValidator.normalizeGtin14('123456789'), isNull);
    });
  });
}
