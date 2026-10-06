import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:leemon_app/core/service/customer_display_service.dart';
import 'package:leemon_app/core/service/scale_service.dart';

Future<void> showCustomerDisplaySettingsDialog(
  BuildContext context, {
  Future<ScaleHardwareDiagnostics> Function()? diagnoseHardware,
}) =>
    showDialog<void>(
        context: context,
        builder: (_) => _CustomerDisplaySettingsDialog(
            diagnoseHardware:
                diagnoseHardware ?? ScaleService.diagnoseHardware));

class _CustomerDisplaySettingsDialog extends StatefulWidget {
  const _CustomerDisplaySettingsDialog({required this.diagnoseHardware});
  final Future<ScaleHardwareDiagnostics> Function() diagnoseHardware;
  @override
  State<_CustomerDisplaySettingsDialog> createState() =>
      _DisplaySettingsState();
}

class _DisplaySettingsState extends State<_CustomerDisplaySettingsDialog> {
  static const ink = Color(0xFF17243B),
      muted = Color(0xFF66758B),
      green = Color(0xFF15966A);
  bool enabled = false,
      loading = true,
      diagnosing = false,
      testing = false,
      saving = false;
  String port = '';
  int baud = 9600, columns = 8;
  CustomerDisplayProtocol protocol = CustomerDisplayProtocol.asciiLine;
  ScaleHardwareDiagnostics? hardware;
  String? result, error;
  bool? visible;

  CustomerDisplaySettings get draft => CustomerDisplaySettings(
      enabled: enabled,
      port: port,
      baudRate: baud,
      columns: columns,
      protocol: protocol);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final settings = await CustomerDisplaySettings.load();
    if (!mounted) return;
    setState(() {
      enabled = settings.enabled;
      port = settings.port;
      baud = settings.baudRate;
      columns = settings.columns;
      protocol = settings.protocol;
      loading = false;
    });
    await refresh();
  }

  Future<void> refresh() async {
    setState(() => diagnosing = true);
    try {
      final value = await widget.diagnoseHardware();
      if (mounted) setState(() => hardware = value);
    } catch (e) {
      if (mounted) setState(() => error = 'Диагностика: $e');
    } finally {
      if (mounted) setState(() => diagnosing = false);
    }
  }

  Future<void> test(double amount) async {
    final service = context.read<CustomerDisplayService>();
    setState(() {
      testing = true;
      result = null;
      error = null;
      visible = null;
    });
    try {
      await validatePort();
      await service.test(draft, amount);
      if (mounted) {
        setState(() => result =
            '${amount.toStringAsFixed(2)} отправлено в $port на 2 секунды. Затем восстановлена сумма корзины или 0.00.');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> validatePort() async {
    final scale = await ScaleSettings.load();
    if (scale.enabled && scale.port.isNotEmpty && scale.port == port) {
      throw StateError('Этот порт выбран для весов. Выберите порт дисплея.');
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (enabled) await validatePort();
      if (!mounted) return;
      await context.read<CustomerDisplayService>().configure(draft);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<CustomerDisplayService>();
    final ports = {...?hardware?.ports, if (port.isNotEmpty) port}.toList();
    final busy = testing || saving;
    return Dialog(
        insetPadding: const EdgeInsets.all(18),
        backgroundColor: const Color(0xFFF5F7FA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: Column(children: [
              Container(
                  color: ink,
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                  child: Row(children: [
                    const Icon(Icons.calculate_outlined,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 14),
                    const Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Дисплей покупателя',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800)),
                          Text('Настройки и диагностика подключения',
                              style: TextStyle(
                                  color: Color(0xFFB9C5D4), fontSize: 13)),
                        ])),
                    IconButton(
                        onPressed:
                            busy ? null : () => Navigator.of(context).pop(),
                        tooltip: 'Закрыть',
                        icon: const Icon(Icons.close, color: Colors.white)),
                  ])),
              Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, size) => SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: size.maxWidth >= 720
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                          Expanded(
                                              child: settingsCard(ports, busy)),
                                          const SizedBox(width: 16),
                                          Expanded(
                                              child: diagnosticsCard(
                                                  service, busy))
                                        ])
                                  : Column(children: [
                                      settingsCard(ports, busy),
                                      const SizedBox(height: 16),
                                      diagnosticsCard(service, busy)
                                    ])))),
              Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(children: [
                    const Expanded(
                        child: Text('Настройки применяются после сохранения',
                            style: TextStyle(color: muted, fontSize: 12))),
                    TextButton(
                        onPressed:
                            busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('Закрыть')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                        onPressed: busy || loading ? null : save,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(saving ? 'Сохранение…' : 'Сохранить')),
                  ])),
            ])));
  }

  Widget settingsCard(List<String> ports, bool busy) =>
      card('Настройки', Icons.tune, [
        Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                activeTrackColor: green,
                title: const Text('Использовать дисплей',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Сумма активной корзины обновляется автоматически'),
                onChanged: busy ? null : (v) => setState(() => enabled = v))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            key: ValueKey('$port:${ports.join(',')}'),
            initialValue: port,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Порт дисплея', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('Выберите порт')),
              for (final p in ports)
                DropdownMenuItem(
                    value: p, child: Text(p, overflow: TextOverflow.ellipsis))
            ],
            onChanged: busy ? null : (v) => setState(() => port = v ?? '')),
        const SizedBox(height: 8),
        const Text(
            'Выберите порт встроенного дисплея. Порт весов и принтера должен быть другим.',
            style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 18),
        DropdownButtonFormField<int>(
            initialValue: baud,
            decoration: const InputDecoration(
                labelText: 'Скорость, бод', border: OutlineInputBorder()),
            items: [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => baud = v ?? 9600)),
        const SizedBox(height: 18),
        DropdownButtonFormField<CustomerDisplayProtocol>(
            initialValue: protocol,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Протокол', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: CustomerDisplayProtocol.asciiLine,
                  child: Text('ASCII, строка CR/LF')),
              DropdownMenuItem(
                  value: CustomerDisplayProtocol.epson,
                  child: Text('Epson ESC/POS (DM-D)')),
              DropdownMenuItem(
                  value: CustomerDisplayProtocol.ascii,
                  child: Text('ASCII с возвратом каретки'))
            ],
            onChanged: busy
                ? null
                : (v) => setState(
                    () => protocol = v ?? CustomerDisplayProtocol.asciiLine)),
        const SizedBox(height: 18),
        DropdownButtonFormField<int>(
            initialValue: columns,
            decoration: const InputDecoration(
                labelText: 'Ширина строки, символов',
                border: OutlineInputBorder()),
            items: [8, 10, 12, 16, 20]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => columns = v ?? 8)),
        const SizedBox(height: 12),
        const Text('Формат суммы: 0.00. Для пустой корзины выводится ноль.',
            style: TextStyle(color: muted, fontSize: 12)),
      ]);

  Widget diagnosticsCard(CustomerDisplayService service, bool busy) =>
      card('Диагностика', Icons.monitor_heart_outlined, [
        row(
            'Платформа / порты',
            hardware == null
                ? 'Проверяем…'
                : hardware!.ports.isEmpty
                    ? 'Порты не найдены'
                    : hardware!.ports.join(', ')),
        if (hardware?.usbSerialAdapter != null)
          row('USB–Serial', hardware!.usbSerialAdapter!),
        if (hardware?.needsDriver == true)
          const Text(
              'USB-адаптер найден, но порт не создан. Проверьте драйвер USB–Serial.',
              style: TextStyle(color: Colors.orange)),
        if (port.isNotEmpty &&
            hardware != null &&
            !hardware!.ports.contains(port))
          const Text('Выбранный порт сейчас недоступен.',
              style: TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: diagnosing || busy ? null : refresh,
            icon: const Icon(Icons.refresh),
            label: Text(diagnosing ? 'Проверяем…' : 'Обновить диагностику')),
        const Divider(height: 28),
        row(
            'Рабочий режим',
            service.settings.enabled
                ? 'Включён · ${service.settings.port}'
                : 'Отключён'),
        row('Сумма корзины', service.total.toStringAsFixed(2)),
        row(
            'Последняя отправка',
            service.lastSent == null
                ? 'Ещё не отправлялась'
                : '${service.lastSent} · ${service.sentAt!.toLocal().toString().split('.').first}'),
        if (service.sending) const LinearProgressIndicator(),
        if (service.error != null)
          Text(service.error!, style: const TextStyle(color: Colors.red)),
        const Divider(height: 28),
        const Text('Проверка вывода',
            style: TextStyle(
                color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        const Text(
            'Проверьте цифры на заднем дисплее во время теста. Успешная отправка в порт не подтверждает отображение.',
            style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
              onPressed: busy || port.isEmpty ? null : () => test(123.45),
              icon: const Icon(Icons.play_arrow),
              label: Text(testing ? 'Проверяем…' : 'Тест 123.45')),
          OutlinedButton(
              onPressed: busy || port.isEmpty ? null : () => test(0),
              child: const Text('Вывести 0.00')),
        ]),
        if (result != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(result!, style: const TextStyle(color: green))),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (result != null) ...[
          const SizedBox(height: 12),
          const Text('Цифры были видны на дисплее?'),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: const Text('Да'),
                selected: visible == true,
                onSelected: (_) => setState(() => visible = true)),
            ChoiceChip(
                label: const Text('Нет'),
                selected: visible == false,
                onSelected: (_) => setState(() => visible = false)),
          ]),
          if (visible == false)
            const Text(
                'Проверьте порт, скорость и протокол по документации моноблока.',
                style: TextStyle(color: Colors.orange)),
          if (visible == true)
            const Text('Вывод подтверждён. Сохраните настройки.',
                style: TextStyle(color: green)),
        ],
      ]);

  Widget row(String title, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: muted, fontSize: 12)),
        Text(value,
            style: const TextStyle(color: ink, fontWeight: FontWeight.w700))
      ]));
  Widget card(String title, IconData icon, List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E9F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: green),
          const SizedBox(width: 9),
          Text(title,
              style: const TextStyle(
                  color: ink, fontSize: 18, fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 20),
        ...children
      ]));
}
