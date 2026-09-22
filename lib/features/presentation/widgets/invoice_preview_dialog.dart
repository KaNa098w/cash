import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';

Future<void> showInvoicePreview(
  BuildContext context, {
  required InvoicePdfData data,
  String? printerName,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InvoicePreviewDialog(data: data, printerName: printerName),
    );

class _InvoicePreviewDialog extends StatefulWidget {
  const _InvoicePreviewDialog({required this.data, this.printerName});

  final InvoicePdfData data;
  final String? printerName;

  @override
  State<_InvoicePreviewDialog> createState() => _InvoicePreviewDialogState();
}

class _InvoicePreviewDialogState extends State<_InvoicePreviewDialog> {
  late final Future<Uint8List> _document =
      buildInvoicePdf(widget.data).then((doc) => doc.save());
  String get _title => widget.data.kind == InvoicePdfKind.payment
      ? 'Счёт на оплату'
      : 'Накладная';

  bool _printing = false;
  String? _message;
  bool _failed = false;

  Future<void> _print(Uint8List bytes) async {
    if (_printing) return;
    setState(() {
      _printing = true;
      _message = null;
    });
    try {
      final printers = await Printing.listPrinters();
      if (printers.isEmpty) {
        throw StateError('Не найден принтер. Проверьте подключение.');
      }
      final printer = printers.firstWhere(
        (p) => p.name == widget.printerName,
        orElse: () => printers.firstWhere((p) => p.isDefault,
            orElse: () => printers.first),
      );
      final printed = await Printing.directPrintPdf(
        printer: printer,
        format: PdfPageFormat.a4,
        usePrinterSettings: true,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
      );
      if (!mounted) return;
      setState(() {
        _failed = !printed;
        _message = printed
            ? 'Документ отправлен на печать'
            : 'Печать отменена или не выполнена. Можно повторить.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = 'Не удалось распечатать документ: $e';
      });
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_printing,
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 960,
          height: size.height * .9,
          child: FutureBuilder<Uint8List>(
            future: _document,
            builder: (context, snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                  child: Row(children: [
                    const Icon(Icons.description_outlined,
                        color: Color(0xFF1155BB), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('Предпросмотр • A4 · 210 × 297 мм',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF64748B))),
                      ],
                    )),
                    IconButton(
                        tooltip: 'Закрыть',
                        onPressed:
                            _printing ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFFE9EDF3),
                    child: snapshot.hasError
                        ? const Center(
                            child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                    'Не удалось подготовить документ. Закройте окно и попробуйте снова.',
                                    textAlign: TextAlign.center)))
                        : !snapshot.hasData
                            ? const Center(child: CircularProgressIndicator())
                            : PdfPreview(
                                build: (_) async => snapshot.data!,
                                initialPageFormat: PdfPageFormat.a4,
                                canChangePageFormat: false,
                                canChangeOrientation: false,
                                canDebug: false,
                                allowPrinting: false,
                                allowSharing: false,
                                useActions: false,
                                maxPageWidth: 760,
                                previewPageMargin: const EdgeInsets.all(20),
                                pdfPreviewPageDecoration: const BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Color(0x26000000),
                                          blurRadius: 14,
                                          offset: Offset(0, 4))
                                    ]),
                                onError: (_, __) => const Center(
                                    child: Text(
                                        'Не удалось показать предпросмотр')),
                              ),
                  ),
                ),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Text(_message!,
                          style: TextStyle(
                              color: _failed
                                  ? Colors.red.shade700
                                  : Colors.green.shade700))),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton(
                        onPressed:
                            _printing ? null : () => Navigator.pop(context),
                        child: const Text('Закрыть')),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1155BB),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 16)),
                      onPressed: snapshot.hasData && !_printing
                          ? () => _print(snapshot.data!)
                          : null,
                      icon: _printing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined),
                      label: Text(_printing ? 'Печать…' : 'Распечатать'),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
