import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/models/fiscal_receipt.dart';
import 'package:leemon_app/features/presentation/widgets/payment_panel.dart';

void main() {
  testWidgets('declining fiscal receipt printing closes the dialog',
      (tester) async {
    var dialogClosed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const FiscalReceiptDialog(
                    initial: FiscalReceipt(
                      id: 'fiscal-receipt-id',
                      status: 'succeeded',
                      printable: true,
                    ),
                    posKey: 'pos-key',
                    deviceId: 'device-id',
                    paperMm: 80,
                  ),
                );
                dialogClosed = true;
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('Распечатать фискальный чек?'), findsOneWidget);
    await tester.tap(find.text('Не печатать'));
    await tester.pumpAndSettle();

    expect(find.text('Фискальный чек готов'), findsNothing);
    expect(dialogClosed, isTrue);
  });

  testWidgets('disabled automatic printing does not ask to print',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FiscalReceiptDialog(
            initial: FiscalReceipt(
              id: 'fiscal-receipt-id',
              status: 'succeeded',
              printable: true,
            ),
            posKey: 'pos-key',
            deviceId: 'device-id',
            paperMm: 80,
            autoPrintEnabled: false,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Фискальный чек готов'), findsOneWidget);
    expect(find.text('Распечатать фискальный чек?'), findsNothing);
  });
  testWidgets('needs_review never polls or asks for printing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: FiscalReceiptDialog(
      initial: FiscalReceipt(
          id: 'RECEIPT', status: 'needs_review', printable: false),
      posKey: 'KEY',
      deviceId: 'DEVICE',
      paperMm: 80,
    ))));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Требуется проверка'), findsOneWidget);
    expect(
        find.textContaining('Автоматический повтор запрещён'), findsOneWidget);
    expect(find.text('Распечатать фискальный чек?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
      'fiscal statuses, check number and poll interval survive cache roundtrip',
      () {
    final receipt = FiscalReceipt.fromJson({
      'id': 'RECEIPT',
      'status': 'processing',
      'printable': false,
      'poll_after_seconds': 45,
      'check_number': '000123',
    });
    expect(receipt.isPending, isTrue);
    expect(receipt.canPrint, isFalse);
    final cached = FiscalReceipt.fromJson(receipt.toJson());
    expect(cached.pollAfterSeconds, 45);
    expect(cached.checkNumber, '000123');
    for (final status in ['pending', 'processing', 'failed', 'needs_review']) {
      expect(FiscalReceipt(id: 'R', status: status, printable: true).canPrint,
          isFalse);
    }
    expect(
        const FiscalReceipt(id: 'R', status: 'succeeded', printable: false)
            .canPrint,
        isFalse);
    expect(
        const FiscalReceipt(id: 'R', status: 'succeeded', printable: true)
            .canPrint,
        isTrue);
  });
}
