import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/print/cash_drawer_service.dart';
import 'package:leemon_app/core/print/cash_drawer_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cash sale opens once even with a fresh service after restart',
      () async {
    var writes = 0;
    Future<void> writer(String printer, List<int> command) async {
      expect(printer, 'XP-80C');
      expect(command, [27, 112, 0, 50, 250]);
      writes++;
    }

    final service = CashDrawerService(writer: writer);
    expect(
        await service.openAfterSale(
            saleId: 'sale', paymentMethod: 'cash', printerName: 'XP-80C'),
        isTrue);
    expect(
        await service.openAfterSale(
            saleId: 'sale', paymentMethod: 'cash', printerName: 'XP-80C'),
        isFalse);
    expect(
        await CashDrawerService(writer: writer).openAfterSale(
            saleId: 'sale', paymentMethod: 'cash', printerName: 'XP-80C'),
        isFalse);
    expect(writes, 1);
  });

  test('card, debt and disabled drawer do not send a pulse', () async {
    var writes = 0;
    final service = CashDrawerService(writer: (_, __) async {
      writes++;
    });
    for (final method in ['card', 'debt', 'partial_debt']) {
      expect(
          await service.openAfterSale(
              saleId: method, paymentMethod: method, printerName: 'XP-80C'),
          isFalse);
    }
    await const CashDrawerSettings(enabled: false).save();
    expect(
        await service.openAfterSale(
            saleId: 'cash', paymentMethod: 'cash', printerName: 'XP-80C'),
        isFalse);
    expect(writes, 0);
  });

  test(
      'concurrent completion cannot open twice and failure is not saved as success',
      () async {
    final gate = Completer<void>();
    var writes = 0;
    final service = CashDrawerService(writer: (_, __) {
      writes++;
      return gate.future;
    });
    final first = service.openAfterSale(
        saleId: 'sale', paymentMethod: 'cash', printerName: 'XP-80C');
    expect(
        await service.openAfterSale(
            saleId: 'sale', paymentMethod: 'cash', printerName: 'XP-80C'),
        isFalse);
    final failed = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    gate.completeError(StateError('Printer unavailable'));
    await failed;
    expect(writes, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('cashDrawer.openedSales'), isNull);
  });

  test('missing printer never opens a default PDF or unrelated printer',
      () async {
    final service =
        CashDrawerService(writer: (_, __) async => fail('Unexpected write'));
    await expectLater(service.open(printerName: null), throwsStateError);
  });

  test('configured second drawer output is persisted and used for cash sales',
      () async {
    await const CashDrawerSettings(pin: 1).save();
    expect((await CashDrawerSettings.load()).pin, 1);
    final service = CashDrawerService(writer: (printer, command) async {
      expect(printer, 'XP-80C');
      expect(command, [27, 112, 1, 50, 250]);
    });
    expect(
        await service.openAfterSale(
            saleId: 'second-pin', paymentMethod: 'cash', printerName: 'XP-80C'),
        isTrue);
  });

  test(
      'mixed sale opens configured drawer and printer settings stay independent',
      () async {
    await const CashDrawerSettings(
            printerName: 'Drawer printer', pin: 1, pulseMs: 50)
        .save();
    final service = CashDrawerService(writer: (printer, command) async {
      expect(printer, 'Drawer printer');
      expect(command, [27, 112, 1, 25, 250]);
    });
    expect(
        await service.openAfterSale(
            saleId: 'mixed',
            paymentMethod: 'mixed',
            printerName: 'Receipt printer'),
        isTrue);
    expect((await CashDrawerSettings.load()).printerName, 'Drawer printer');
  });

  test('send one opening pulse to the physically connected XP-80C', () async {
    await CashDrawerService.instance.open(
        printerName: 'XP-80C',
        pin: const int.fromEnvironment('TEST_CASH_DRAWER_PIN'));
  }, skip: !const bool.fromEnvironment('TEST_CASH_DRAWER_HARDWARE'));

  test('read real XP-80C diagnostics without opening the drawer', () async {
    final report = await CashDrawerService.instance.diagnose('XP-80C');
    expect(report, contains('XP-80C'));
    expect(report, contains('USB005'));
    expect(report, contains('Заданий в очереди:'));
  }, skip: !const bool.fromEnvironment('TEST_CASH_DRAWER_DIAGNOSTICS'));
}
