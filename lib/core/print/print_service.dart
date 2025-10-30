// lib/core/print/print_service.dart
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PrintService {
  Printer? _defaultPrinter;

  /// Находим системный принтер по умолчанию и кэшируем.
  Future<Printer?> _ensureDefault() async {
    if (_defaultPrinter != null) return _defaultPrinter;
    final printers = await Printing.listPrinters(); // может вернуть пусто
    _defaultPrinter = printers.isEmpty
        ? null
        : printers.firstWhere(
            (p) => p.isDefault == true,
            orElse: () => printers.first,
          );
    return _defaultPrinter;
  }

  /// Печать без диалога, портрет, ширина 80 мм (ролик).
  Future<void> print80mmSilently(
    Future<pw.Document> Function() buildDoc,
  ) async {
    final printer = await _ensureDefault();
    if (printer == null) {
      // Нет доступных принтеров — тихо выходим или кинь исключение под свою логику
      return;
    }
    final doc = await buildDoc();

    // прямой вывод на принтер без диалога
    await Printing.directPrintPdf(
      printer: printer,
      onLayout: (PdfPageFormat _) async => doc.save(),
    );
  }
}
