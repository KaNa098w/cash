import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/features/data/utils/money.dart';

class _Printing extends PrintingPlatform {
  PdfPageFormat? sentFormat;
  bool? sentPrinterSettings;
  Uint8List? bytes;
  bool success = true;
  bool available = true;
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
    original = PrintingPlatform.instance;
    printing = _Printing();
    PrintingPlatform.instance = printing;
  });
  tearDown(() => PrintingPlatform.instance = original);

  for (final paperMm in [57, 80]) {
    test('long $paperMm mm receipt sends full finite PDF height to driver',
        () async {
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
            100,
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
      final actual = document.document.pdfPageList.pages.single.pageFormat;
      expect(actual.height, greaterThan(1000));
      expect(actual.height.isFinite, isTrue);
      expect(printing.sentFormat!.height, actual.height);
      expect(printing.sentFormat!.width,
          closeTo(paperMm * PdfPageFormat.mm, 0.001));
      expect(printing.sentPrinterSettings, isFalse);
      expect(printing.bytes!.length, greaterThan(1000));
      final output = Platform.environment['RECEIPT_QA_OUTPUT'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        await File('$output/receipt-$paperMm.pdf')
            .writeAsBytes(printing.bytes!);
      }
    });
  }
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
