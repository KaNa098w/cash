import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/print/cash_drawer_service.dart';
import 'package:leemon_app/core/print/cash_drawer_settings.dart';
import 'package:leemon_app/features/presentation/widgets/cash_drawer_settings_dialog.dart';

class _Service extends CashDrawerService {
  _Service(DrawerWriter writer) : super(writer: writer);
  @override
  Future<String> diagnose(String? printerName) async =>
      'Принтер: $printerName\nПорт: USB005\nЗаданий в очереди: 0';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(WidgetTester tester, CashDrawerService service) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => CashDrawerSettingsDialog(
                              receiptPrinterName: 'XP-80C',
                              service: service,
                              loadPrinters: () async => [
                                    const Printer(url: 'XP-80C', name: 'XP-80C')
                                  ])),
                      child: const Text('Open')),
                ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'touch settings fit, diagnose and test without changing saved settings',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pulses = 0;
    final service = _Service((printer, command) async {
      expect(printer, 'XP-80C');
      pulses++;
    });
    await open(tester, service);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Открыть ящик — тест'));
    await tester.tap(find.text('Открыть ящик — тест'));
    await tester.pumpAndSettle();
    expect(pulses, 1);
    expect(find.text('Команда передана принтеру. Денежный ящик открылся?'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Открылся'));
    await tester.tap(find.text('Открылся'));
    await tester.pumpAndSettle();
    expect(service.diagnostics.last, contains('подтвердил'));
    await tester.ensureVisible(find.text('Диагностика'));
    await tester.tap(find.text('Диагностика'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Порт: USB005'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled auto-opening is persisted and survives reopening',
      (tester) async {
    final service = _Service((_, __) async {});
    await open(tester, service);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Сохранить'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect((await tester.runAsync(CashDrawerSettings.load))!.enabled, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
  });
}
