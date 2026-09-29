import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leemon_app/core/service/scale_service.dart';

Future<void> showScaleSettingsDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ScaleSettingsDialog(),
    );

class _ScaleSettingsDialog extends StatefulWidget {
  const _ScaleSettingsDialog();

  @override
  State<_ScaleSettingsDialog> createState() => _ScaleSettingsDialogState();
}

class _ScaleSettingsDialogState extends State<_ScaleSettingsDialog> {
  static const ink = Color(0xFF17243B);
  static const muted = Color(0xFF66758B);
  static const green = Color(0xFF15966A);

  bool loading = true,
      diagnosing = false,
      testing = false,
      enabled = true,
      dirty = false;
  String port = '';
  int baudRate = 9600;
  ScaleProtocol protocol = ScaleProtocol.auto;
  ScaleHardwareDiagnostics? hardware;
  ScaleReading? reading;
  String? testError;
  ScaleConnection? connection;
  StreamSubscription<ScaleReading>? readingSubscription;
  StreamSubscription<String>? errorSubscription;
  Timer? timeout;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final settings = await ScaleSettings.load();
    if (!mounted) return;
    setState(() {
      enabled = settings.enabled;
      port = settings.port;
      baudRate = settings.baudRate;
      protocol = settings.protocol;
      loading = false;
    });
    await refresh();
  }

  Future<void> refresh() async {
    setState(() => diagnosing = true);
    final result = await ScaleService.diagnoseHardware();
    if (mounted) {
      setState(() {
        hardware = result;
        diagnosing = false;
      });
    }
  }

  void stopTest() {
    timeout?.cancel();
    readingSubscription?.cancel();
    errorSubscription?.cancel();
    connection?.close();
    connection = null;
    testing = false;
  }

  void change(VoidCallback update) {
    stopTest();
    setState(() {
      update();
      dirty = true;
      reading = null;
      testError = null;
    });
  }

  Future<void> test() async {
    stopTest();
    setState(() {
      testing = true;
      reading = null;
      testError = null;
    });
    try {
      final scale = await ScaleService(
        baudRate: baudRate,
        portCandidates: port.isEmpty ? (hardware?.ports ?? []) : [port],
        protocol: protocol,
      ).connect();
      if (!mounted) {
        scale.close();
        return;
      }
      connection = scale;
      readingSubscription = scale.readings.listen((value) {
        if (!mounted) return;
        timeout?.cancel();
        setState(() {
          reading = value;
          testing = false;
          testError = null;
        });
      });
      errorSubscription = scale.errors.listen((error) {
        if (!mounted) return;
        stopTest();
        setState(() => testError = error);
      });
      timeout = Timer(const Duration(seconds: 12), () {
        if (!mounted || reading != null) return;
        stopTest();
        setState(() => testError =
            'Вес не получен за 12 секунд. Проверьте порт, скорость и протокол.');
      });
    } catch (error) {
      if (!mounted) return;
      stopTest();
      setState(() => testError = 'Не удалось открыть порт: $error');
    }
  }

  Future<void> save() async {
    await ScaleSettings(
            enabled: enabled,
            port: port,
            baudRate: baudRate,
            protocol: protocol)
        .save();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    stopTest();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ports = {...?hardware?.ports, if (port.isNotEmpty) port}.toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: const Color(0xFFF5F7FA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(children: [
          Container(
            color: ink,
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
            child: Row(children: [
              const Icon(Icons.scale_rounded, color: Colors.white, size: 30),
              const SizedBox(width: 14),
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Весы',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800)),
                    Text('Настройки и диагностика подключения',
                        style:
                            TextStyle(color: Color(0xFFB9C5D4), fontSize: 13)),
                  ])),
              IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, size) {
                        final settings = settingsCard(ports);
                        final diagnostics = diagnosticsCard();
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: size.maxWidth >= 720
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      Expanded(child: settings),
                                      const SizedBox(width: 16),
                                      Expanded(child: diagnostics),
                                    ])
                              : Column(children: [
                                  settings,
                                  const SizedBox(height: 16),
                                  diagnostics
                                ]),
                        );
                      },
                    )),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            color: Colors.white,
            child: Row(children: [
              Expanded(
                  child: Text(
                      dirty
                          ? 'Есть несохранённые изменения'
                          : 'Настройки сохранены на этом устройстве',
                      style: const TextStyle(color: muted, fontSize: 12))),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть')),
              const SizedBox(width: 8),
              FilledButton.icon(
                  onPressed: loading ? null : save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Сохранить')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget settingsCard(List<String> ports) =>
      card('Настройки', Icons.tune_rounded, [
        Container(
          decoration: BoxDecoration(
              color:
                  enabled ? const Color(0xFFE9F8F1) : const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(14)),
          child: SwitchListTile.adaptive(
            value: enabled,
            activeTrackColor: green,
            title: const Text('Использовать весы',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(enabled
                ? 'Вес считывается автоматически'
                : 'Количество вводится вручную'),
            onChanged: (value) => change(() => enabled = value),
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey('$port:${ports.join(',')}'),
          initialValue: port,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Порт подключения', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(
                value: '', child: Text('Автоматический выбор')),
            for (final value in ports)
              DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged:
              enabled ? (value) => change(() => port = value ?? '') : null,
        ),
        const SizedBox(height: 8),
        const Text('Если подключено несколько устройств, выберите порт весов.',
            style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 18),
        DropdownButtonFormField<int>(
          initialValue: baudRate,
          decoration: const InputDecoration(
              labelText: 'Скорость, бод', border: OutlineInputBorder()),
          items: [2400, 4800, 9600, 19200, 38400, 57600, 115200]
              .map((value) =>
                  DropdownMenuItem(value: value, child: Text('$value')))
              .toList(),
          onChanged: enabled
              ? (value) => change(() => baudRate = value ?? 9600)
              : null,
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<ScaleProtocol>(
          initialValue: protocol,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Протокол весов', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(
                value: ScaleProtocol.auto, child: Text('Автоматически')),
            DropdownMenuItem(value: ScaleProtocol.cas, child: Text('CAS-M')),
            DropdownMenuItem(value: ScaleProtocol.pos2, child: Text('POS2-M')),
            DropdownMenuItem(
                value: ScaleProtocol.continuous,
                child: Text('Непрерывная передача')),
          ],
          onChanged: enabled
              ? (value) => change(() => protocol = value ?? ScaleProtocol.auto)
              : null,
        ),
        const SizedBox(height: 8),
        const Text('Оставьте «Автоматически», если протокол неизвестен.',
            style: TextStyle(color: muted, fontSize: 12)),
      ]);

  Widget diagnosticsCard() {
    final current = hardware;
    return card('Диагностика', Icons.monitor_heart_outlined, [
      diagnosticRow(
          Icons.usb_rounded,
          'USB-адаптер',
          current?.usbSerialAdapter ??
              (current == null ? 'Проверяем…' : 'Не обнаружен'),
          current?.usbSerialAdapter != null),
      const Divider(height: 24),
      diagnosticRow(
          Icons.settings_input_component_rounded,
          'Последовательные порты',
          current == null
              ? 'Проверяем…'
              : current.ports.isEmpty
                  ? 'Не найдены'
                  : current.ports.join(', '),
          current?.ports.isNotEmpty == true),
      const SizedBox(height: 16),
      if (current?.needsDriver == true)
        notice(
            'Адаптер подключён, но macOS не создала порт. Установите и включите драйвер USB–Serial, затем обновите диагностику.',
            const Color(0xFFB45309),
            const Color(0xFFFFF6E8)),
      if (current != null && current.ports.isEmpty && !current.needsDriver)
        notice(
            'Порт весов не найден. Проверьте USB-кабель, переходник и питание весов.',
            const Color(0xFFB45309),
            const Color(0xFFFFF6E8)),
      if (current?.ports.isNotEmpty == true)
        notice(
            'Порт доступен. Нажмите «Проверить связь», чтобы получить показание веса.',
            const Color(0xFF166D50),
            const Color(0xFFE9F8F1)),
      if (port.isNotEmpty && current != null && !current.ports.contains(port))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: notice(
              'Выбранный порт $port сейчас недоступен. Подключите устройство или выберите автоматический поиск.',
              const Color(0xFFB45309),
              const Color(0xFFFFF6E8)),
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: diagnosing ? null : refresh,
        icon: diagnosing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded),
        label: const Text('Обновить диагностику'),
      ),
      const SizedBox(height: 18),
      const Divider(),
      const SizedBox(height: 8),
      const Text('Проверка связи',
          style:
              TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 10),
      if (reading != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: const Color(0xFFE9F8F1),
              borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Вес получен',
                style: TextStyle(color: green, fontWeight: FontWeight.w700)),
            Text('${reading!.grams.toStringAsFixed(1)} г',
                style: const TextStyle(
                    color: ink, fontSize: 32, fontWeight: FontWeight.w800)),
            Text(reading!.portName,
                style: const TextStyle(color: muted, fontSize: 12)),
          ]),
        )
      else if (testError != null)
        notice(testError!, const Color(0xFFB42318), const Color(0xFFFEF0EF))
      else
        const Text('Положите товар на весы и запустите проверку.',
            style: TextStyle(color: muted)),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: !enabled || testing ? null : test,
        icon: testing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.play_arrow_rounded),
        label: Text(testing ? 'Ожидание веса…' : 'Проверить связь'),
      ),
      if (reading != null)
        TextButton(
          onPressed: () {
            stopTest();
            setState(() => reading = null);
          },
          child: const Text('Остановить проверку'),
        ),
    ]);
  }

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
          ...children,
        ]),
      );

  Widget diagnosticRow(IconData icon, String label, String value, bool ok) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ok ? green : muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                        color: ok ? ink : muted, fontWeight: FontWeight.w700)),
              ])),
          Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: ok ? green : muted, size: 19),
        ],
      );

  Widget notice(String message, Color foreground, Color background) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(12)),
        child: Text(message,
            style: TextStyle(
                color: foreground, height: 1.35, fontWeight: FontWeight.w600)),
      );
}
