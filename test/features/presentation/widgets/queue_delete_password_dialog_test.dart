import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/features/presentation/widgets/queue_delete_password_dialog.dart';

void main() {
  testWidgets('touch PIN stays hidden and only 2020 authorizes deletion',
      (tester) async {
    bool? authorized;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          authorized = await confirmQueueDeletion(context);
        },
        child: const Text('Open'),
      ),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final digit in ['1', '1', '1', '1']) {
      await tester.tap(find.widgetWithText(OutlinedButton, digit));
      await tester.pump();
    }
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.readOnly, isTrue);
    expect(field.enableInteractiveSelection, isFalse);
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Неверный пароль'), findsOneWidget);
    expect(authorized, isNull);
    for (final digit in ['2', '0', '2', '0']) {
      await tester.tap(find.widgetWithText(OutlinedButton, digit));
      await tester.pump();
    }
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(authorized, isTrue);
  });
}
