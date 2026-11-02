import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/print/cash_drawer_service.dart';
import 'package:leemon_app/core/print/cash_drawer_settings.dart';

Future<void> showCashDrawerSettingsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => CashDrawerSettingsDialog(
        receiptPrinterName:
            context.read<AuthTokenProvider>().receiptPrinterName,
      ),
    );

class CashDrawerSettingsDialog extends StatefulWidget {
  const CashDrawerSettingsDialog(
      {super.key, this.receiptPrinterName, this.loadPrinters, this.service});
  final String? receiptPrinterName;
  final Future<List<Printer>> Function()? loadPrinters;
  final CashDrawerService? service;
  @override
  State<CashDrawerSettingsDialog> createState() => _DrawerSettingsState();
}

class _DrawerSettingsState extends State<CashDrawerSettingsDialog> {
  static const green = Color(0xFF15966A);
  CashDrawerService get service => widget.service ?? CashDrawerService.instance;
  bool enabled = true, busy = true;
  String? printer;
  int pin = 0, pulse = 100;
  List<Printer> printers = [];
  String? report, error, result;
  bool? opened;
  String? get effectivePrinter => printer ?? widget.receiptPrinterName;
  CashDrawerSettings get draft => CashDrawerSettings(
        enabled: enabled,
        printerName: printer,
        pin: pin,
        pulseMs: pulse,
      );

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final settings = await CashDrawerSettings.load();
      final available = await (widget.loadPrinters ?? Printing.listPrinters)();
      if (!mounted) return;
      setState(() {
        enabled = settings.enabled;
        printer = settings.printerName;
        pin = settings.pin;
        pulse = settings.pulseMs;
        printers = available;
        busy = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = 'Не удалось загрузить список принтеров.';
        });
    }
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final available = await (widget.loadPrinters ?? Printing.listPrinters)();
      final text = await service.diagnose(effectivePrinter);
      if (mounted)
        setState(() {
          printers = available;
          report = text;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> test() async {
    setState(() {
      busy = true;
      error = null;
      result = null;
      opened = null;
    });
    try {
      await service.open(
          printerName: effectivePrinter, pin: pin, pulseMs: pulse);
      if (mounted)
        setState(() =>
            result = 'Команда передана принтеру. Денежный ящик открылся?');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (enabled && !printers.any((p) => p.name == effectivePrinter)) {
      setState(() => error = 'Выберите доступный принтер денежного ящика.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await draft.save();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = 'Не удалось сохранить настройки.';
        });
    }
  }

  void confirmOpened(bool value) {
    service.record(value
        ? 'Пользователь подтвердил открытие ящика.'
        : 'Пользователь сообщил: ящик не открылся.');
    setState(() => opened = value);
  }

  @override
  Widget build(BuildContext context) {
    final names = printers.map((p) => p.name).toSet().toList();
    if (printer != null && !names.contains(printer)) names.add(printer!);
    return Dialog(
      backgroundColor: const Color(0xFFF8FAFC),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 740),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Денежный ящик',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                    'Подключите ящик к разъёму DK / DRAWER принтера. Ключ должен стоять в положении автоматического открытия.'),
                const SizedBox(height: 16),
                Flexible(
                    child: SingleChildScrollView(
                        child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Автоматическое открытие'),
                      subtitle: const Text(
                          'После наличной и смешанной оплаты. При безналичной оплате ящик не открывается.'),
                      value: enabled,
                      onChanged:
                          busy ? null : (v) => setState(() => enabled = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('printer:$printer:${names.join(',')}'),
                      initialValue: printer ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Принтер денежного ящика',
                          border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(
                            value: '',
                            child: Text(
                                'Как чековый принтер (${widget.receiptPrinterName ?? 'не выбран'})',
                                overflow: TextOverflow.ellipsis)),
                        for (final name in names)
                          DropdownMenuItem(
                              value: name,
                              child: Text(
                                  printers.any((p) => p.name == name)
                                      ? name
                                      : '$name — недоступен',
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                                printer = v == '' ? null : v;
                                report = null;
                                result = null;
                              }),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: pin,
                      key: ValueKey('pin:$pin'),
                      decoration: const InputDecoration(
                          labelText: 'Выход денежного ящика',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 0,
                            child: Text('Выход 1 — контакт 2 (стандартный)')),
                        DropdownMenuItem(
                            value: 1, child: Text('Выход 2 — контакт 5')),
                      ],
                      onChanged:
                          busy ? null : (v) => setState(() => pin = v ?? 0),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: pulse,
                      key: ValueKey('pulse:$pulse'),
                      decoration: const InputDecoration(
                          labelText: 'Длительность импульса',
                          border: OutlineInputBorder()),
                      items: [
                        for (final ms in [50, 100, 120])
                          DropdownMenuItem(value: ms, child: Text('$ms мс'))
                      ],
                      onChanged:
                          busy ? null : (v) => setState(() => pulse = v ?? 100),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                        'Открытие не зависит от печати чека. Изменённые параметры можно проверить до сохранения.'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: green),
                          onPressed: busy ? null : test,
                          icon: const Icon(Icons.lock_open_outlined),
                          label: const Text('Открыть ящик — тест')),
                      OutlinedButton.icon(
                          onPressed: busy ? null : refresh,
                          icon: const Icon(Icons.monitor_heart_outlined),
                          label: const Text('Диагностика')),
                    ]),
                    if (busy)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator()),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: const TextStyle(color: Colors.red))),
                    if (result != null) ...[
                      const SizedBox(height: 12),
                      Text(result!),
                      Wrap(spacing: 12, children: [
                        ChoiceChip(
                            label: const Text('Открылся'),
                            selected: opened == true,
                            onSelected:
                                busy ? null : (_) => confirmOpened(true)),
                        ChoiceChip(
                            label: const Text('Не открылся'),
                            selected: opened == false,
                            onSelected:
                                busy ? null : (_) => confirmOpened(false)),
                      ]),
                      if (opened == false)
                        const Text(
                            'Проверьте ключ, кабель и разъём DK / DRAWER. При совместимом подключении можно проверить другой выход.'),
                    ],
                    if (report != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SelectableText(report!)),
                    ExpansionTile(
                        title: const Text('Журнал диагностики'),
                        children: [
                          SelectableText(service.diagnostics.isEmpty
                              ? 'Проверок пока нет.'
                              : service.diagnostics.reversed.join('\n')),
                          TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(
                                    text:
                                        '${report ?? ''}\nПринтер: $effectivePrinter\nВыход: ${pin + 1}; импульс: $pulse мс\n${service.diagnostics.join('\n')}'));
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Диагностика скопирована')));
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Копировать диагностику')),
                        ]),
                  ],
                ))),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed:
                          busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Отмена')),
                  const SizedBox(width: 12),
                  FilledButton(
                      onPressed: busy ? null : save,
                      child: const Text('Сохранить')),
                ]),
              ],
            )),
      ),
    );
  }
}
