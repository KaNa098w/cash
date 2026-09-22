import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/features/presentation/pages/invoices/invoice_text_field.dart';

void main() {
  test('phone normalizes country prefix and domestic prefix', () {
    for (final value in ['7011234567', '+7 (701) 123-45-67', '87011234567']) {
      expect(formatInvoicePhone(value), '+7 (701) 123-45-67');
    }
    expect(formatInvoicePhone(''), '');
  });
  testWidgets('numeric editor preserves zeros, limits BIN and formats phone',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    for (final kind in [InvoiceInputKind.digits, InvoiceInputKind.phone]) {
      controller.clear();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: InvoiceTextField(
                  controller: controller, label: 'Номер', inputKind: kind))));
      await tester.tap(find.byType(InvoiceTextField));
      await tester.pumpAndSettle();
      expect(find.text('Клавиатура'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, '0'));
      await tester.tap(find.widgetWithText(OutlinedButton, '0'));
      final input = find.byType(TextField).last;
      expect(tester.widget<TextField>(input).controller!.text, '00');
      if (kind == InvoiceInputKind.digits) {
        await tester.enterText(input, '001234567890123abc');
        expect(
            tester.widget<TextField>(input).controller!.text, '001234567890');
      } else {
        await tester.enterText(input, '+7 (701) 123-45-67');
        await tester.pump();
        expect(tester.widget<TextField>(input).controller!.text, '7011234567');
        expect(find.text('+7 (701) 123-45-67'), findsOneWidget);
      }
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(
          controller.text,
          kind == InvoiceInputKind.digits
              ? '001234567890'
              : '+7 (701) 123-45-67');
      expect(tester.takeException(), isNull);
    }
  });
}
