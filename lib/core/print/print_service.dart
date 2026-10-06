import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintService {
  Future<Printer?> _resolvePrinter(String? name) async {
    final printers = await Printing.listPrinters();
    if (printers.isEmpty) return null;
    if (name != null && name.isNotEmpty) {
      final found = printers.where((p) => p.name == name).toList();
      if (found.isNotEmpty) return found.first;
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
    final receiptFormat = pages.first.pageFormat;
    if (!receiptFormat.width.isFinite || !receiptFormat.height.isFinite) {
      throw StateError('Не удалось определить размер чека.');
    }

    final printed = await Printing.directPrintPdf(
      printer: printer,
      format: receiptFormat,
      usePrinterSettings: false,
      dynamicLayout: false,
      onLayout: (PdfPageFormat _) async => bytes,
    );
    if (!printed) throw StateError('Чек не отправлен на печать.');
  }

  // Накладные — большой принтер (A4).
  Future<void> printPdfBytesSilently(
    Uint8List pdfBytes, {
    String? printerName,
    PdfPageFormat? format,
  }) async {
    final printer = await _resolvePrinter(printerName);
    if (printer == null) {
      throw StateError(
          'Принтер не найден. Проверьте подключение и настройки печати.');
    }

    if (format != null && (!format.width.isFinite || !format.height.isFinite)) {
      throw StateError('Не удалось определить размер документа.');
    }
    final printed = await Printing.directPrintPdf(
      printer: printer,
      format: format ?? PdfPageFormat.a4,
      usePrinterSettings: format == null,
      dynamicLayout: false,
      onLayout: (PdfPageFormat _) async => pdfBytes,
    );
    if (!printed) throw StateError('Документ не отправлен на печать.');
  }
}
