import 'package:flutter/material.dart';
import 'package:leemon_app/core/service/pos_maintenance_service.dart';

Future<void> showPosMaintenanceDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const PosMaintenanceDialog(),
    );

class PosMaintenanceDialog extends StatefulWidget {
  const PosMaintenanceDialog({super.key, this.service});
  final PosMaintenanceService? service;
  @override
  State<PosMaintenanceDialog> createState() => _PosMaintenanceDialogState();
}

class _PosMaintenanceDialogState extends State<PosMaintenanceDialog> {
  static const green = Color(0xFF15966A);
  static const ink = Color(0xFF172B27);
  late Future<PosMaintenanceResult> _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    _result = (widget.service ?? PosMaintenanceService.instance).optimize();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: FutureBuilder<PosMaintenanceResult>(
            future: _result,
            builder: (context, snapshot) {
              final busy = snapshot.connectionState != ConnectionState.done;
              final result = snapshot.data;
              final warning = snapshot.hasError || result?.diskError != null;
              final accent = warning ? const Color(0xFFB66A13) : green;
              final memory = result == null
                  ? '—'
                  : '${(result.memoryBytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              color: const Color(0xFFE9F6F0),
                              borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: green, size: 26),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('ОБСЛУЖИВАНИЕ',
                                  style: TextStyle(
                                      color: green,
                                      fontSize: 10,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w800)),
                              SizedBox(height: 4),
                              Text('Оптимизация кассы',
                                  style: TextStyle(
                                      color: ink,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800)),
                            ])),
                        IconButton(
                            tooltip: 'Закрыть',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded,
                                color: Color(0xFF87938F))),
                      ]),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: warning
                                ? const Color(0xFFFFF7E9)
                                : const Color(0xFFF0F8F4),
                            borderRadius: BorderRadius.circular(20)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                if (busy)
                                  const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5, color: green))
                                else
                                  Icon(
                                      warning
                                          ? Icons.info_outline_rounded
                                          : Icons.check_circle_rounded,
                                      color: accent,
                                      size: 26),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(
                                        busy
                                            ? 'Наводим порядок'
                                            : snapshot.hasError
                                                ? 'Очистка не завершена'
                                                : warning
                                                    ? 'Очищено частично'
                                                    : 'Всё готово',
                                        style: TextStyle(
                                            color: accent,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800))),
                              ]),
                              const SizedBox(height: 10),
                              Text(
                                  busy
                                      ? 'Очищаем временный кэш изображений. Можно закрыть окно — очистка продолжится.'
                                      : snapshot.hasError
                                          ? 'Не удалось завершить очистку. Попробуйте позднее.'
                                          : warning
                                              ? 'Кэш в памяти очищен. Часть файлов на диске сейчас недоступна. Повторите очистку позднее.'
                                              : 'Временный кэш изображений очищен. Можно продолжать работу.',
                                  style: const TextStyle(
                                      color: Color(0xFF52665D),
                                      fontSize: 14,
                                      height: 1.5)),
                            ]),
                      ),
                      const SizedBox(height: 16),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: _Metric(
                                    icon: Icons.memory_rounded,
                                    label: 'Кэш в памяти до очистки',
                                    value: memory)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _Metric(
                                    icon: Icons.image_outlined,
                                    label: 'Кэш изображений на диске',
                                    value: busy
                                        ? 'Очистка…'
                                        : warning
                                            ? 'Не завершено'
                                            : 'Очищен')),
                          ]),
                      const SizedBox(height: 24),
                      const Row(children: [
                        Icon(Icons.verified_user_outlined,
                            size: 18, color: green),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text('Рабочие данные сохранены',
                                style: TextStyle(
                                    color: ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final label in [
                          'Продажи',
                          'Очередь отправки',
                          'Товары',
                          'Настройки'
                        ])
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFF4F6F5),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(label,
                                  style: const TextStyle(
                                      color: Color(0xFF5D6D65), fontSize: 12))),
                      ]),
                      const SizedBox(height: 20),
                      const Text(
                          'Изображения загрузятся заново при необходимости. Для обновления товаров используйте «Синхронизация» в меню кассы.',
                          style: TextStyle(
                              color: Color(0xFF77867E),
                              fontSize: 12,
                              height: 1.5)),
                      const SizedBox(height: 24),
                      if (warning) ...[
                        OutlinedButton.icon(
                            onPressed: () => setState(_run),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Повторить очистку'),
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: green)),
                        const SizedBox(height: 10),
                      ],
                      FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                          child: Text(busy ? 'Закрыть' : 'Продолжить работу',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE8EDEA)),
            borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: const Color(0xFF87938F), size: 20),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF172B27),
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF77867E), fontSize: 12, height: 1.4)),
        ]),
      );
}
