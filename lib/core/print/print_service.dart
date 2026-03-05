// lib/core/print/print_service.dart
import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PrintService {
  Printer? _defaultPrinter;

  Future<Printer?> _ensureDefault() async {
    if (_defaultPrinter != null) return _defaultPrinter;
    final printers = await Printing.listPrinters();
    _defaultPrinter = printers.isEmpty
        ? null
        : printers.firstWhere(
            (p) => p.isDefault == true,
            orElse: () => printers.first,
          );
    return _defaultPrinter;
  }

  Future<void> print80mmSilently(
    Future<pw.Document> Function() buildDoc, {
    PdfPageFormat format = PdfPageFormat.roll80,
  }) async {
    final printer = await _ensureDefault();
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

  // ✅ НОВОЕ: печать готового PDF, который пришёл с сервера
  Future<void> printPdfBytesSilently(Uint8List pdfBytes) async {
    final printer = await _ensureDefault();
    if (printer == null) return;

    await Printing.directPrintPdf(
      printer: printer,
      usePrinterSettings: true,
      dynamicLayout: false,
      onLayout: (PdfPageFormat _) async => pdfBytes,
    );
  }
}
