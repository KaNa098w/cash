// lib/core/print/print_service.dart
import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  // Чеки и Z-отчёт — маленький термопринтер
  Future<void> print80mmSilently(
    Future<pw.Document> Function() buildDoc, {
    PdfPageFormat format = PdfPageFormat.roll80,
    String? printerName,
  }) async {
    final printer = await _resolvePrinter(printerName);
    if (printer == null) return;

    final doc = await buildDoc();

    await Printing.directPrintPdf(
      printer: printer,
      format: format,
      usePrinterSettings: true,
      dynamicLayout: false,
      onLayout: (PdfPageFormat _) async => doc.save(),
    );
  }

  // Накладные — большой принтер (A4)
  Future<void> printPdfBytesSilently(
    Uint8List pdfBytes, {
    String? printerName,
  }) async {
    final printer = await _resolvePrinter(printerName);
    if (printer == null) return;

    await Printing.directPrintPdf(
      printer: printer,
      usePrinterSettings: true,
      dynamicLayout: false,
      onLayout: (PdfPageFormat _) async => pdfBytes,
    );
  }
}
