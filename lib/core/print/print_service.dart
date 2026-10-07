import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'receipt_printer_settings.dart';

class PrintService {
  static final List<String> diagnostics = [];

  static void record(String message) {
    diagnostics.add('${DateTime.now().toLocal().toIso8601String()} $message');
    if (diagnostics.length > 50) diagnostics.removeAt(0);
  }

  Future<Printer?> _resolvePrinter(String? name) async {
    final printers = await Printing.listPrinters();
    record(
        'Найдено принтеров: ${printers.length}; выбран: ${name ?? "по умолчанию"}');
    if (printers.isEmpty) {
      record('Ошибка: принтеры не найдены.');
      return null;
    }
    if (name != null && name.isNotEmpty) {
      final found = printers.where((p) => p.name == name).toList();
      if (found.isNotEmpty) return found.first;
      record('Ошибка: выбранный принтер $name недоступен.');
      throw StateError(
          'Выбранный принтер «$name» недоступен. Выберите его заново в настройках.');
    }
    return printers.firstWhere(
      (p) => p.isDefault == true,
      orElse: () => printers.first,
    );
  }

  // Чеки и Z-отчёт — маленький термопринтер.
  Future<void> print80mmSilently(
    Future<pw.Document> Function() buildDoc, {
    PdfPageFormat format = PdfPageFormat.roll57,
    String? printerName,
  }) async {
    final printer = await _resolvePrinter(printerName);
    if (printer == null) {
      throw StateError(
          'Принтер не найден. Проверьте подключение и настройки печати.');
    }

    final doc = await buildDoc();
    // Saving lays out roll pages and replaces their infinite height with the
    // full content height. Send that finite size to the printer driver.
    final bytes = await doc.save();
    final pages = doc.document.pdfPageList.pages;
    if (pages.isEmpty) throw StateError('Чек не содержит страниц.');
    record('Локальный чек / отчёт: ${pages.length} страниц.');
    final receiptFormat = pages.first.pageFormat;
    if (!receiptFormat.width.isFinite || !receiptFormat.height.isFinite) {
      throw StateError('Не удалось определить размер чека.');
    }

    await _send(bytes, printer, receiptFormat, thermal: true);
  }

  // Накладные — большой принтер (A4).
  Future<void> printPdfBytesSilently(
    Uint8List pdfBytes, {
    String? printerName,
    PdfPageFormat? format,
    ReceiptPrinterSettings? settings,
  }) async {
    final printer = await _resolvePrinter(printerName);
    if (printer == null) {
      throw StateError(
          'Принтер не найден. Проверьте подключение и настройки печати.');
    }

    if (format != null && (!format.width.isFinite || !format.height.isFinite)) {
      throw StateError('Не удалось определить размер документа.');
    }
    await _send(pdfBytes, printer, format ?? PdfPageFormat.a4,
        thermal: format != null, settings: settings);
  }

  Future<void> _send(Uint8List bytes, Printer printer, PdfPageFormat format,
      {required bool thermal, ReceiptPrinterSettings? settings}) async {
    final options = settings ?? await ReceiptPrinterSettings.load();
    final useDriver = !thermal || options.usePrinterSettings;
    record('Отправка: ${printer.name}; '
        '${(format.width / PdfPageFormat.mm).toStringAsFixed(1)} × '
        '${(format.height / PdfPageFormat.mm).toStringAsFixed(1)} мм; '
        '${bytes.length} байт; настройки драйвера: $useDriver');
    try {
      final printed = await Printing.directPrintPdf(
        printer: printer,
        format: format,
        usePrinterSettings: useDriver,
        dynamicLayout: false,
        onLayout: (PdfPageFormat _) async => bytes,
      );
      if (!printed) throw StateError('Документ не отправлен на печать.');
      record(
          'Задание передано системе печати. Выход бумаги требует проверки на принтере.');
    } catch (e) {
      record('Ошибка печати: $e');
      rethrow;
    }
  }
}
