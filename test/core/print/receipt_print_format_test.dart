import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:leemon_app/features/presentation/widgets/printer_settings_dialog.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leemon_app/core/models/fiscal_receipt.dart';
import 'package:leemon_app/core/service/fiscal_receipt_service.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_printer_settings.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/features/data/utils/money.dart';

class _Printing extends PrintingPlatform {
  PdfPageFormat? sentFormat;
  bool? sentPrinterSettings;
  Uint8List? bytes;
  bool success = true;
  bool available = true;
  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: true, directPrint: true);

  @override
  Future<List<Printer>> listPrinters() async =>
      available ? [const Printer(url: 'test', name: 'Thermal')] : [];
  @override
  Future<bool> layoutPdf(
      Printer? printer,
      LayoutCallback onLayout,
      String name,
      PdfPageFormat format,
      bool dynamicLayout,
      bool usePrinterSettings,
      OutputType outputType,
      bool forceCustomPrintPaper) async {
    sentFormat = format;
    sentPrinterSettings = usePrinterSettings;
    bytes = await onLayout(format);
    return success;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',
        (message) async {
      final asset = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (asset == 'AssetManifest.json') {
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
          'google_fonts/Roboto-Regular.ttf': [],
          'google_fonts/Roboto-Bold.ttf': [],
        }))));
      }
      final fileName = switch (asset) {
        'google_fonts/Roboto-Regular.ttf' =>
          'assets/fonts/NotoSans-Regular.ttf',
        'google_fonts/Roboto-Bold.ttf' => 'assets/fonts/NotoSans-Bold.ttf',
        _ => asset,
      };
      final file = File(fileName);
      return file.existsSync()
          ? ByteData.sublistView(await file.readAsBytes())
          : null;
    });
  });
  tearDownAll(() => binding.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', null));
  late _Printing printing;
  late PrintingPlatform original;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = PrintingPlatform.instance;
    printing = _Printing();
    PrintingPlatform.instance = printing;
  });
  tearDown(() => PrintingPlatform.instance = original);

  for (final paperMm in [57, 80]) {
    for (final itemCount in [1, 100]) {
      test('$itemCount items on $paperMm mm uses driver-safe pages', () async {
        final format =
            paperMm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
        final data = ReceiptPdfData(
          pageFormat: format,
          money: money,
          receiptDate: DateTime(2026, 10, 5),
          receiptNumber: 'TEST-100',
          cashierName: 'Кассир',
          storeName: 'Магазин',
          items: List.generate(
              itemCount,
              (i) => ReceiptPdfItem(
                  name: 'Товар ${i + 1} с длинным наименованием',
                  quantity: 2,
                  unitPrice: 100,
                  lineTotal: 200)),
          total: 20000,
          paymentMethodLabel: 'Наличные',
          isCashPayment: true,
          received: 20000,
          change: 0,
          footerText: 'КОНЕЦ ЧЕКА — Спасибо за покупку!',
        );
        final document = await buildReceiptPdf(data);
        await PrintService().print80mmSilently(() async => document,
            format: format, printerName: 'Thermal');
        final actual = document.document.pdfPageList.pages.first.pageFormat;
        if (itemCount == 100) {
          expect(actual.height, closeTo(200 * PdfPageFormat.mm, 0.001));
          expect(document.document.pdfPageList.pages.length, greaterThan(1));
        } else {
          expect(actual.height, lessThan(200 * PdfPageFormat.mm));
          expect(document.document.pdfPageList.pages.length, 1);
        }
        expect(actual.height.isFinite, isTrue);
        expect(printing.sentFormat!.height, actual.height);
        expect(printing.sentFormat!.width,
            closeTo(paperMm * PdfPageFormat.mm, 0.001));
        expect(printing.sentPrinterSettings, isFalse);
        expect(printing.bytes!.length, greaterThan(1000));
        final output = Platform.environment['RECEIPT_QA_OUTPUT'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File('$output/receipt-$paperMm-$itemCount.pdf')
              .writeAsBytes(printing.bytes!);
        }
      });
    }
  }
  for (final paperMm in [57, 80]) {
    test('long fiscal $paperMm mm PrintFormat uses bounded pages', () async {
      SharedPreferences.setMockInitialValues({});
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.path, endsWith('/fiscal-receipts/TEST/print-format'));
        expect(options.queryParameters['paper_kind'], paperMm == 80 ? 0 : 3);
        handler.resolve(Response(requestOptions: options, data: {
          'data': {
            'lines': [
              for (var i = 0; i < 200; i++)
                {'Type': 0, 'Value': 'Товар $i с длинным наименованием'},
              {'Type': 2, 'Value': 'https://example.com/receipt/TEST'},
              {'Type': 0, 'Value': 'КОНЕЦ ФИСКАЛЬНОГО ЧЕКА'},
            ],
          },
        }));
      }));
      final service = FiscalReceiptService(dio, PrintService());
      const receipt =
          FiscalReceipt(id: 'TEST', status: 'succeeded', printable: true);
      await service.save(receipt);
      await service.printTicket(receipt,
          key: 'KEY', deviceId: 'DEVICE', paperMm: paperMm);
      expect(printing.sentFormat!.height.isFinite, isTrue);
      expect(
          printing.sentFormat!.height, closeTo(200 * PdfPageFormat.mm, 0.001));
      // Page dictionaries are uncompressed even when content streams are not.
      final pdf = latin1.decode(printing.bytes!);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length, greaterThan(1));
      expect(printing.sentFormat!.width,
          closeTo(paperMm * PdfPageFormat.mm, 0.001));
      expect(printing.sentPrinterSettings, isFalse);
      expect(await service.wasPrinted(receipt.id), isTrue);
      final output = Platform.environment['RECEIPT_QA_OUTPUT'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        await File('$output/fiscal-$paperMm.pdf').writeAsBytes(printing.bytes!);
      }
      dio.close();
    });
  }
  test('settings persist and selected paper survives restart', () async {
    final provider = AuthTokenProvider();
    await provider.init();
    await provider.setReceiptPaperMm(80);
    const options = ReceiptPrinterSettings(
        localLengthMm: 100,
        fiscalLengthMm: 150,
        fixedLength: true,
        usePrinterSettings: true,
        leftMarginMm: 2,
        rightMarginMm: 3,
        feedMm: 5);
    await options.save();
    final loaded = await ReceiptPrinterSettings.load();
    expect(loaded.localLengthMm, 100);
    expect(loaded.fiscalLengthMm, 150);
    expect(loaded.fixedLength, isTrue);
    expect(loaded.leftMarginMm, 2);
    expect(loaded.feedMm, 5);
    final restarted = AuthTokenProvider();
    await restarted.init();
    expect(restarted.receiptPaperMm, 80);
    await PrintService().printPdfBytesSilently(Uint8List(1),
        format: const PdfPageFormat(160, 280));
    expect(printing.sentPrinterSettings, isTrue);
    provider.dispose();
    restarted.dispose();
  });
  test('local test overrides page length without saving settings', () async {
    final doc = await buildReceiptPdf(
        ReceiptPdfData(
          pageFormat: PdfPageFormat.roll57,
          money: money,
          receiptDate: DateTime(2026),
          receiptNumber: 'TEST',
          cashierName: 'Test',
          storeName: 'Test',
          items: const [],
          total: 0,
          paymentMethodLabel: 'Test',
          isCashPayment: false,
        ),
        options: const ReceiptPrinterSettings(
            localLengthMm: 100, fixedLength: true));
    await doc.save();
    expect(doc.document.pdfPageList.pages.first.pageFormat.height,
        closeTo(100 * PdfPageFormat.mm, 0.001));
    expect((await ReceiptPrinterSettings.load()).localLengthMm, 200);
  });
  test('fiscal page length can be changed independently', () async {
    const settings = ReceiptPrinterSettings(
        localLengthMm: 100, fiscalLengthMm: 150, fixedLength: true);
    await settings.save();
    final doc =
        await buildFiscalPrintDocument(paperMm: 80, widgets: [pw.Text('TEST')]);
    await doc.save();
    expect(doc.document.pdfPageList.pages.first.pageFormat.height,
        closeTo(150 * PdfPageFormat.mm, 0.001));
  });
  testWidgets('printer settings renders and rejects invalid paper length',
      (tester) async {
    final provider = AuthTokenProvider();
    await tester.pumpWidget(MaterialApp(
        home: PrinterSettingsDialog(
            provider: provider, openSystemSettings: () async {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Настройки и диагностика принтера'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = find.widgetWithText(
        TextFormField, 'Длина страницы локального чека / отчёта');
    await tester.ensureVisible(field);
    await tester.enterText(field, '0');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Укажите число от 80.0 до 500.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(field);
    await tester.enterText(field, '100');
    final localTest = find.text('Длинный локальный');
    await tester.ensureVisible(localTest);
    final localButton = tester.widget<OutlinedButton>(
        find.ancestor(of: localTest, matching: find.byType(OutlinedButton)));
    await tester.runAsync(() async {
      await Function.apply(localButton.onPressed!, []);
    });
    await tester.pumpAndSettle();
    expect(printing.sentFormat!.height, closeTo(100 * PdfPageFormat.mm, 0.001));
    expect(printing.bytes, isNotNull);
    expect((await ReceiptPrinterSettings.load()).localLengthMm, 200);
    final fiscalTest = find.text('Длинный фискальный');
    await tester.ensureVisible(fiscalTest);
    final fiscalButton = tester.widget<OutlinedButton>(
        find.ancestor(of: fiscalTest, matching: find.byType(OutlinedButton)));
    await tester.runAsync(() async {
      await Function.apply(fiscalButton.onPressed!, []);
    });
    await tester.pumpAndSettle();
    expect(printing.sentFormat!.height, closeTo(200 * PdfPageFormat.mm, 0.001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  test('explicit unavailable printer fails rather than selecting another',
      () async {
    await expectLater(
        PrintService()
            .printPdfBytesSilently(Uint8List(1), printerName: 'Missing'),
        throwsStateError);
  });
  test('fiscal PDF uses explicit thermal size while A4 keeps printer settings',
      () async {
    const format = PdfPageFormat(80 * PdfPageFormat.mm, 1600);
    await PrintService().printPdfBytesSilently(Uint8List(1), format: format);
    expect(printing.sentFormat, format);
    expect(printing.sentPrinterSettings, isFalse);
    await PrintService().printPdfBytesSilently(Uint8List(1));
    expect(printing.sentPrinterSettings, isTrue);
  });
  test(
      'failed or unavailable printing is reported instead of marked successful',
      () async {
    printing.success = false;
    await expectLater(
        PrintService().printPdfBytesSilently(Uint8List(1)), throwsStateError);
    printing.available = false;
    await expectLater(
        PrintService().printPdfBytesSilently(Uint8List(1)), throwsStateError);
  });
}
