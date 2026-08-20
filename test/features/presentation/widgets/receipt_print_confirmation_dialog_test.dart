import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/features/presentation/widgets/receipt_print_confirmation_dialog.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester,
    ValueChanged<bool> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result = await showReceiptPrintConfirmation(context);
                onResult(result);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('returns true when receipt printing is confirmed',
      (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    expect(find.text('Распечатать чек?'), findsOneWidget);
    expect(find.text('Не печатать'), findsOneWidget);
    expect(find.text('Распечатать'), findsOneWidget);

    await tester.tap(find.text('Распечатать'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('returns false when receipt printing is declined',
      (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    await tester.tap(find.text('Не печатать'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
