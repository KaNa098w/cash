import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leemon_app/core/service/kaspi_payment_service.dart';
import 'package:leemon_app/core/service/kaspi_terminal.dart';
import 'package:leemon_app/features/presentation/widgets/kaspi_payment_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/kaspi_settings_dialog.dart';

class FakeTerminal implements KaspiTerminal {
  @override
  String host = '192.168.18.208';
  @override
  bool registered = true;
  final registration = Completer<void>();
  final payment = Completer<Map<String, dynamic>>();
  int registrations = 0;
  int checks = 0;
  String? requestedHost;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> register(String address) async {
    registrations++;
    requestedHost = address;
    await registration.future;
    host = address;
    registered = true;
  }

  @override
  Future<void> checkConnection() async {
    checks++;
  }

  @override
  Future<Map<String, dynamic>> pay(
          {required String saleId,
          required double amount,
          void Function(String)? onProgress}) =>
      payment.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openDialog(WidgetTester tester, Widget dialog, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: const Key('kaspi-preview'),
      child: MaterialApp(
          theme: ThemeData(fontFamily: 'NotoSans', useMaterial3: true),
          home: Builder(
              builder: (context) => Scaffold(
                  backgroundColor: const Color(0xFFE9EEF3),
                  body: Center(
                      child: FilledButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => dialog),
                          child: const Text('Open'))))))));
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('KASPI_PREVIEWS')) return;
  await tester.pump(const Duration(milliseconds: 300));
  final folder = Directory('${Directory.current.path}/build/kaspi_previews');
  folder.createSync(recursive: true);
  await expectLater(find.byKey(const Key('kaspi-preview')),
      matchesGoldenFile(Uri.file('${folder.path}/$name.png')));
}

void main() {
  setUpAll(() async {
    final font = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await font.load();
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  for (final size in [
    const Size(1024, 768),
    const Size(800, 600),
    const Size(500, 900)
  ]) {
    testWidgets('settings fit touchscreen ${size.width} x ${size.height}',
        (tester) async {
      await openDialog(
          tester, KaspiSettingsDialog(terminal: FakeTerminal()), size);
      expect(tester.takeException(), isNull);
      expect(find.text('Проверить связь'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('kaspi-key-1'))).height,
          greaterThanOrEqualTo(size.height < 680 ? 48 : 60));
      expect(find.byKey(const ValueKey('kaspi-key-.')).hitTestable(),
          findsOneWidget);
      await preview(tester, 'settings-${size.width.toInt()}');
    });
  }

  testWidgets(
      'touch keypad enters a full IP with three dots and edits selection',
      (tester) async {
    final terminal = FakeTerminal();
    await openDialog(
        tester, KaspiSettingsDialog(terminal: terminal), const Size(1024, 768));
    await tester.tap(find.text('Очистить адрес'));
    await tester.pump();
    for (final digit in '192.168.18.208'.split('')) {
      await tester.tap(find.byKey(ValueKey('kaspi-key-$digit')));
      await tester.pump();
    }
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '192.168.18.208');
    expect(field.readOnly, isTrue);
    expect(field.keyboardType, TextInputType.none);
    field.controller!.selection =
        const TextSelection(baseOffset: 12, extentOffset: 14);
    await tester.tap(find.byKey(const ValueKey('kaspi-key-1')));
    await tester.pump();
    expect(field.controller!.text, '192.168.18.21');
    await tester.tap(find.byKey(const ValueKey('kaspi-key-backspace')));
    await tester.pump();
    expect(field.controller!.text, '192.168.18.2');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid IP cannot connect and pending registration disables repeated taps',
      (tester) async {
    final terminal = FakeTerminal();
    await openDialog(
        tester, KaspiSettingsDialog(terminal: terminal), const Size(1024, 768));
    await tester.tap(find.text('Очистить адрес'));
    await tester.pump();
    for (final digit in '999.1.1.1'.split('')) {
      await tester.tap(find.byKey(ValueKey('kaspi-key-$digit')));
      await tester.pump();
    }
    final connect = find.byKey(const ValueKey('kaspi-connect'));
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    await tester.tap(find.text('Очистить адрес'));
    await tester.pump();
    for (final digit in '192.168.18.209'.split('')) {
      await tester.tap(find.byKey(ValueKey('kaspi-key-$digit')));
      await tester.pump();
    }
    // Checking a changed address must not silently check the old terminal.
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('kaspi-check')))
            .onPressed,
        isNull);
    await tester.tap(connect);
    await tester.pump();
    expect(terminal.registrations, 1);
    expect(terminal.requestedHost, '192.168.18.209');
    expect(find.text('Подтвердите доступ на терминале'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('kaspi-key-1')))
            .onPressed,
        isNull);
    await preview(tester, 'registration-waiting');
    terminal.registration.complete();
    await tester.pumpAndSettle();
    expect(find.text('Терминал готов к оплате'), findsOneWidget);
    expect(terminal.checks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'payment waiting and error fit and retain confirmed failure result',
      (tester) async {
    final terminal = FakeTerminal();
    await openDialog(
        tester,
        KaspiPaymentDialog(
            terminal: terminal, saleId: 'test-sale', amount: 12500),
        const Size(1024, 768));
    expect(find.text('12 500 ₸'), findsOneWidget);
    expect(find.text('Kaspi QR'), findsOneWidget);
    expect(find.text('Вернуться к продаже'), findsNothing);
    expect(tester.takeException(), isNull);
    await preview(tester, 'payment-waiting');
    terminal.payment.completeError(const KaspiPaymentException(
        'Покупатель отменил оплату на терминале.',
        confirmedFailure: true));
    await tester.pumpAndSettle();
    expect(find.text('Оплата не выполнена'), findsOneWidget);
    expect(find.text('Вернуться к продаже'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await preview(tester, 'payment-error');
    await tester.tap(find.text('Вернуться к продаже'));
    await tester.pumpAndSettle();
    expect(find.text('Оплата не выполнена'), findsNothing);
  });
}
