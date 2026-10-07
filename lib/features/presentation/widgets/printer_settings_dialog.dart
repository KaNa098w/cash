import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/service/fiscal_receipt_service.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/print/receipt_printer_settings.dart';

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog(
      {super.key, required this.provider, required this.openSystemSettings});
  final AuthTokenProvider provider;
  final Future<void> Function() openSystemSettings;
  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  List<Printer> printers = [];
  String? receipt, invoice;
  int paper = 57;
  bool enabled = true, fixed = false, driver = false, busy = true;
  String status = 'Загрузка настроек…';

  @override
  void initState() {
    super.initState();
    receipt = widget.provider.receiptPrinterName;
    invoice = widget.provider.invoicePrinterName;
    paper = widget.provider.receiptPaperMm;
    enabled = widget.provider.receiptPrintingEnabled;
    load();
  }

  Future<void> load() async {
    try {
      final s = await ReceiptPrinterSettings.load();
      for (final e in {
        'local': s.localLengthMm,
        'fiscal': s.fiscalLengthMm,
        'left': s.leftMarginMm,
        'right': s.rightMarginMm,
        'top': s.topMarginMm,
        'bottom': s.bottomMarginMm,
        'feed': s.feedMm
      }.entries) {
        fields[e.key] = TextEditingController(text: e.value.toString());
      }
      fixed = s.fixedLength;
      driver = s.usePrinterSettings;
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          status = 'Ошибка загрузки: $e';
        });
      }
    }
  }

  Future<void> refresh() async {
    if (mounted) setState(() => busy = true);
    try {
      final found = await Printing.listPrinters();
      final info = await Printing.info();
      final systemReport = await _systemDiagnostics();
      if (!mounted) return;
      setState(() {
        printers = found;
        status = 'ОС: ${Platform.operatingSystem}\n'
            'Принтеров: ${found.length}\n'
            'Печать: ${info.canPrint}; прямая печать: ${info.directPrint}\n'
            '$systemReport\n'
            '${found.map((p) => '${p.name}: ${p.isAvailable == false ? "недоступен" : "обнаружен"}${p.isDefault ? ", по умолчанию" : ""}; ${p.url}').join('\n')}';
      });
      PrintService.record(status);
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка обнаружения принтеров: $e');
      PrintService.record('Ошибка обнаружения: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> _systemDiagnostics() async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'''$ErrorActionPreference = 'Stop';
Get-Printer | ForEach-Object {
  $p = $_;
  [PSCustomObject]@{
    Name = $p.Name; Driver = $p.DriverName; Port = $p.PortName;
    Status = [string]$p.PrinterStatus;
    Jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue |
      Select-Object ID, JobStatus, SubmittedTime, Size)
  }
} | ConvertTo-Json -Depth 5'''
        ]).timeout(const Duration(seconds: 10));
      } else if (Platform.isMacOS || Platform.isLinux) {
        result = await Process.run('lpstat', ['-p', '-d', '-v', '-o'])
            .timeout(const Duration(seconds: 10));
      } else {
        return 'Системная диагностика недоступна на этой ОС.';
      }
      return 'Драйвер, порт и очередь печати:\n${result.stdout}\n${result.stderr}';
    } catch (e) {
      return 'Не удалось прочитать системную очередь: $e';
    }
  }

  ReceiptPrinterSettings options() => ReceiptPrinterSettings(
        localLengthMm: number('local'),
        fiscalLengthMm: number('fiscal'),
        leftMarginMm: number('left'),
        rightMarginMm: number('right'),
        topMarginMm: number('top'),
        bottomMarginMm: number('bottom'),
        feedMm: number('feed'),
        fixedLength: fixed,
        usePrinterSettings: driver,
      );
  double number(String key) =>
      double.parse(fields[key]!.text.replaceAll(',', '.'));

  Future<void> testPrint({bool fiscal = false, bool long = false}) async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final s = options();
      final format = paper == 80 ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
      pw.Document doc;
      if (fiscal) {
        final font = pw.Font.ttf(
            await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
        doc = await buildFiscalPrintDocument(
          paperMm: paper,
          options: s,
          widgets: [
            pw.Text('ТЕСТ ФИСКАЛЬНОГО ФОРМАТА',
                style: pw.TextStyle(font: font, fontSize: 9)),
            pw.Text('Диагностический образец. Не фискальный чек.',
                style: pw.TextStyle(font: font, fontSize: 7)),
            for (var i = 1; i <= (long ? 60 : 3); i++)
              pw.Text('Строка $i: 1234567890 АБВГД — 100 ₸',
                  style: pw.TextStyle(font: font, fontSize: 8)),
            pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: 'PRINTER-DIAGNOSTICS',
                width: 80,
                height: 80),
            pw.Text('КОНЕЦ ТЕСТА',
                style: pw.TextStyle(font: font, fontSize: 9)),
          ],
        );
      } else {
        doc = await buildReceiptPdf(
            ReceiptPdfData(
              pageFormat: format,
              money: (v) => '$v ₸',
              receiptDate: DateTime.now(),
              receiptNumber: 'TEST',
              cashierName: 'Диагностика',
              storeName: 'ТЕСТ ЛОКАЛЬНОГО ЧЕКА',
              items: List.generate(
                  long ? 60 : 3,
                  (i) => ReceiptPdfItem(
                      name: 'Строка ${i + 1}: АБВГД 1234567890',
                      quantity: 1,
                      unitPrice: 100,
                      lineTotal: 100)),
              total: (long ? 60 : 3) * 100,
              paymentMethodLabel: 'Тест',
              isCashPayment: false,
              footerText: 'КОНЕЦ ТЕСТА',
            ),
            options: s);
      }
      final bytes = await doc.save();
      PrintService.record(
          'Тест ${fiscal ? "фискального формата" : "локального чека"}: страниц ${doc.document.pdfPageList.pages.length}');
      await PrintService().printPdfBytesSilently(bytes,
          printerName: receipt,
          format: doc.document.pdfPageList.pages.first.pageFormat,
          settings: s);
      if (mounted) {
        setState(() => status =
            'Тест передан системе печати. Проверьте текст, края, QR и надпись «КОНЕЦ ТЕСТА» на бумаге.');
      }
    } catch (e) {
      PrintService.record('Тест не удался: $e');
      if (mounted) setState(() => status = 'Ошибка теста: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await options().save();
      await widget.provider.setReceiptPaperMm(paper);
      await widget.provider.setReceiptPrinterName(receipt);
      await widget.provider.setInvoicePrinterName(invoice);
      await widget.provider.setReceiptPrintingEnabled(enabled);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          status = 'Не удалось сохранить: $e';
        });
      }
    }
  }

  Widget printerField(
      String label, String? value, ValueChanged<String?> change) {
    final names = {...printers.map((p) => p.name), if (value != null) value};
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: fieldDecoration(label),
      items: [
        const DropdownMenuItem(value: null, child: Text('По умолчанию')),
        ...names.map((n) => DropdownMenuItem(
            value: n, child: Text(n, overflow: TextOverflow.ellipsis)))
      ],
      onChanged: busy ? null : change,
    );
  }

  Widget numberField(String key, String label, double min, double max) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: fields[key],
          enabled: !busy,
          decoration: fieldDecoration(label)
              .copyWith(suffixText: 'мм', helperText: 'От $min до $max мм'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            final n = double.tryParse((v ?? '').replaceAll(',', '.'));
            return n == null || !n.isFinite || n < min || n > max
                ? 'Укажите число от $min до $max'
                : null;
          },
        ),
      );

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  static const green = Color(0xFF15966A);
  static const muted = Color(0xFF64748B);

  InputDecoration fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: muted),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: green, width: 1.5)),
      );

  Widget section(String title, String subtitle, IconData icon,
          List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Material(
            color: Colors.transparent,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE8F8F2),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, size: 22, color: green)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A))),
                          const SizedBox(height: 4),
                          Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 12, height: 1.4, color: muted)),
                        ])),
                  ]),
                  const SizedBox(height: 18),
                  ...children,
                ])),
      );

  Widget pair(Widget left, Widget right) =>
      LayoutBuilder(builder: (_, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 10), right]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right)
        ]);
      });

  Widget toggle(String title, String subtitle, bool value,
          ValueChanged<bool> change) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: green,
        activeThumbColor: Colors.white,
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155))),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, height: 1.4, color: muted)),
        value: value,
        onChanged: busy ? null : change,
      );

  Widget paperOption(int mm, String description) {
    final selected = paper == mm;
    return InkWell(
      onTap: busy ? null : () => setState(() => paper = mm),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: selected ? const Color(0xFFE8F8F2) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? green : const Color(0xFFE2E8F0),
                width: selected ? 1.5 : 1)),
        child: Row(children: [
          Icon(Icons.receipt_long_outlined,
              color: selected ? green : muted, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('$mm мм',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A))),
                Text(description,
                    style: const TextStyle(fontSize: 12, color: muted)),
              ])),
          Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? green : const Color(0xFFCBD5E1)),
        ]),
      ),
    );
  }

  Future<void> copyReport() async {
    await Clipboard.setData(ClipboardData(
        text:
            '$status\nБумага: $paper мм; принтер: ${receipt ?? "по умолчанию"}\n'
            '${fields.entries.map((e) => '${e.key}: ${e.value.text} мм').join('; ')}\nФиксированная длина: $fixed; настройки драйвера: $driver\n${PrintService.diagnostics.join('\n')}'));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Отчёт скопирован')));
    }
  }

  Future<void> openSystemSettings() async {
    try {
      await widget.openSystemSettings();
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Не удалось открыть системные настройки: $e');
      }
    }
  }

  Widget testCard(bool fiscal) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(fiscal ? Icons.qr_code_rounded : Icons.receipt_outlined,
                size: 20, color: green),
            const SizedBox(width: 8),
            Expanded(
                child: Text(fiscal ? 'Фискальный формат' : 'Локальный чек',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)))
          ]),
          const SizedBox(height: 8),
          Text(
              fiscal
                  ? 'Текст и QR без регистрации продажи'
                  : 'Проверка текста, полей и подачи бумаги',
              style: const TextStyle(fontSize: 12, height: 1.4, color: muted)),
          const SizedBox(height: 14),
          OutlinedButton(
              onPressed: busy ? null : () => testPrint(fiscal: fiscal),
              child: Text(fiscal ? 'Фискальный тест' : 'Локальный тест')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed:
                  busy ? null : () => testPrint(fiscal: fiscal, long: true),
              child: Text(fiscal ? 'Длинный фискальный' : 'Длинный локальный')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final selected = printers
        .where((p) => receipt == null ? p.isDefault : p.name == receipt);
    final missing =
        !busy && (printers.isEmpty || (receipt != null && selected.isEmpty));
    final available = !missing && selected.every((p) => p.isAvailable);
    return Dialog(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme:
                  Theme.of(context).colorScheme.copyWith(primary: green),
              outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: green,
                      side: const BorderSide(color: Color(0xFFB8DFD0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)))),
            ),
            child: Column(children: [
              Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                  child: Row(children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE8F8F2),
                            borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.print_rounded,
                            color: green, size: 26)),
                    const SizedBox(width: 14),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Настройки и диагностика принтера',
                              style: TextStyle(
                                  fontSize: 20,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A))),
                          SizedBox(height: 4),
                          Text('Бумага, печать чеков и проверка подключения',
                              style: TextStyle(fontSize: 12, color: muted)),
                        ])),
                    IconButton(
                        tooltip: 'Закрыть',
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: muted)),
                  ])),
              if (busy)
                const LinearProgressIndicator(
                    minHeight: 3,
                    color: green,
                    backgroundColor: Color(0xFFE8F8F2)),
              Expanded(
                  child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                    key: form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          section(
                              'Подключение принтеров',
                              'Выберите устройство для каждого вида документов.',
                              Icons.cable_rounded, [
                            pair(
                                printerField('Принтер чеков и отчётов', receipt,
                                    (v) => setState(() => receipt = v)),
                                printerField('Принтер накладных (A4)', invoice,
                                    (v) => setState(() => invoice = v))),
                            const SizedBox(height: 12),
                            Row(children: [
                              Icon(
                                  busy
                                      ? Icons.sync_rounded
                                      : available
                                          ? Icons.check_circle_outline
                                          : Icons.warning_amber_rounded,
                                  size: 18,
                                  color: busy
                                      ? muted
                                      : available
                                          ? green
                                          : const Color(0xFFB45309)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      busy
                                          ? 'Проверяем подключение…'
                                          : missing
                                              ? 'Принтер не найден. Проверьте подключение.'
                                              : available
                                                  ? 'Принтер обнаружен • устройств: ${printers.length}'
                                                  : 'Выбранный принтер недоступен',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: missing || !available
                                              ? const Color(0xFFB45309)
                                              : muted))),
                            ]),
                            toggle(
                                'Спрашивать о печати после операции',
                                'Подтверждение перед отправкой чека на принтер.',
                                enabled,
                                (v) => setState(() => enabled = v)),
                          ]),
                          section(
                              'Бумага и длина чека',
                              'Ширина должна совпадать с бумагой в принтере.',
                              Icons.receipt_long_outlined, [
                            pair(paperOption(57, 'Узкая лента'),
                                paperOption(80, 'Широкая лента')),
                            if (fields.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              pair(
                                  numberField(
                                      'local',
                                      'Длина страницы локального чека / отчёта',
                                      80,
                                      500),
                                  numberField(
                                      'fiscal',
                                      'Длина страницы фискального чека',
                                      80,
                                      500)),
                              toggle(
                                  'Всегда заданная длина страницы',
                                  'Выключено: короткий чек по содержимому; длинный разбивается на страницы заданной длины.',
                                  fixed,
                                  (v) => setState(() => fixed = v)),
                              toggle(
                                  'Использовать размер бумаги из драйвера',
                                  'Драйвер может заменить размеры приложения. Согласуйте ширину и длину в системных настройках.',
                                  driver,
                                  (v) => setState(() => driver = v)),
                            ],
                          ]),
                          if (fields.isNotEmpty) ...[
                            section(
                                'Поля и подача бумаги',
                                'Настройте отступы, если текст обрезается по краям.',
                                Icons.crop_free_rounded, [
                              pair(numberField('left', 'Поле слева', 0, 10),
                                  numberField('right', 'Поле справа', 0, 15)),
                              pair(numberField('top', 'Поле сверху', 0, 15),
                                  numberField('bottom', 'Поле снизу', 0, 15)),
                              numberField(
                                  'feed',
                                  'Подача после локального чека / отчёта',
                                  0,
                                  50),
                            ]),
                            section(
                                'Тестовая печать',
                                'Тест использует текущие значения без сохранения настроек.',
                                Icons.fact_check_outlined, [
                              pair(testCard(false), testCard(true)),
                            ]),
                          ],
                          section(
                              'Диагностика',
                              'Проверьте очередь печати или скопируйте отчёт для разбора проблемы.',
                              Icons.monitor_heart_outlined, [
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              TextButton(
                                  onPressed: busy ? null : refresh,
                                  child: const Text('Обновить диагностику')),
                              TextButton(
                                  onPressed: busy ? null : openSystemSettings,
                                  child: const Text('Системные настройки')),
                              TextButton.icon(
                                  onPressed: busy ? null : copyReport,
                                  icon:
                                      const Icon(Icons.copy_outlined, size: 18),
                                  label: const Text('Копировать отчёт')),
                            ]),
                            ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                    'Результат проверки и журнал печати',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                children: [
                                  Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: SelectableText(
                                          '$status\n\n${PrintService.diagnostics.reversed.take(8).join('\n')}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.5,
                                              color: Color(0xFF475569))))
                                ]),
                            if (status.startsWith('Ошибка') ||
                                status.startsWith('Не удалось') ||
                                status.startsWith('Тест передан'))
                              Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(status,
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.4,
                                          color:
                                              status.startsWith('Тест передан')
                                                  ? green
                                                  : const Color(0xFFB45309)))),
                            const SizedBox(height: 12),
                            Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.lightbulb_outline_rounded,
                                          size: 20, color: Color(0xFFB45309)),
                                      SizedBox(width: 10),
                                      Expanded(
                                          child: Text(
                                              'Если бумага только сдвигается, проверьте самотест принтера, сторону термобумаги и очередь печати. При обрезании попробуйте длину 100–200 мм. Отрезчик, плотность и скорость настраиваются в драйвере.',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  height: 1.5,
                                                  color: Color(0xFF9A3412)))),
                                    ])),
                          ]),
                        ])),
              )),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
                  child: LayoutBuilder(
                      builder: (_, constraints) => Row(children: [
                            if (constraints.maxWidth >= 540)
                              const Expanded(
                                  child: Text(
                                      'Настройки сохраняются на этом устройстве',
                                      style: TextStyle(
                                          fontSize: 12, color: muted))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: const Text('Отмена',
                                        style: TextStyle(color: muted)))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: FilledButton(
                                    onPressed:
                                        busy || fields.isEmpty ? null : save,
                                    style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF22B982),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(130, 46),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12))),
                                    child: const Text('Сохранить'))),
                          ]))),
            ]),
          ),
        ),
      ),
    );
  }
}
