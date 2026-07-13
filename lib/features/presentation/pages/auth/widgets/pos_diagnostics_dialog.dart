import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/service/pos_diagnostics_service.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';

Future<void> showPosDiagnosticsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _PosDiagnosticsDialog(),
  );
}

class _PosDiagnosticsDialog extends StatefulWidget {
  const _PosDiagnosticsDialog();

  @override
  State<_PosDiagnosticsDialog> createState() => _PosDiagnosticsDialogState();
}

class _PosDiagnosticsDialogState extends State<_PosDiagnosticsDialog> {
  late Future<Map<String, dynamic>> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _loadReport();
  }

  Future<Map<String, dynamic>> _loadReport() async {
    final diagnostics = sl<PosDiagnosticsService>();
    final auth = context.read<AuthTokenProvider>();
    final key = auth.posKey?.trim() ?? '';
    final localState = key.isEmpty
        ? <String, dynamic>{'message': 'posKey is empty'}
        : await sl<PosSyncService>().loadDiagnosticsState(key);
    final localProducts = await sl<PosSyncService>().loadProductsRaw();
    return diagnostics.buildReport(
      localState: localState,
      localProducts: localProducts,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Диагностика загрузки товаров',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Обновить',
                    onPressed: () {
                      setState(() => _reportFuture = _loadReport());
                    },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _reportFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Не удалось собрать диагностику: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    );
                  }

                  return _DiagnosticsReportView(
                    report: snapshot.data ?? const <String, dynamic>{},
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsReportView extends StatelessWidget {
  const _DiagnosticsReportView({required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final entries = _asListOfMaps(report['http_entries']);
    final errorEntries = entries.where(_isErrorEntry).toList(growable: false);
    final lastError = (report['last_error_message'] ?? '').toString().trim();
    final bootstrapSummary = _asMap(report['last_bootstrap_summary']);
    final localState = _asMap(report['local_state']);
    final localProducts = _asListOfMaps(
      report['local_products_saved_from_snapshot'],
    );
    final snapshotProducts = _asListOfMaps(report['last_snapshot_products']);
    final localStorageIssues = _asListOfMaps(report['local_storage_issues']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryPanel(
          lastError: lastError,
          errorCount: errorEntries.length,
          requestCount: entries.length,
          snapshotProductsCount: snapshotProducts.length,
          localProductsCount: localProducts.length,
          bootstrapSummary: bootstrapSummary,
          localState: localState,
        ),
        if (localStorageIssues.isNotEmpty) ...[
          const SizedBox(height: 14),
          _DataSection(
            title: 'Поврежденные локальные JSON',
            subtitle: '${localStorageIssues.length} записей',
            data: localStorageIssues,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Очередь сервисов',
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const _EmptyPanel(
            text:
                'HTTP-запросов пока нет. Повтори загрузку товаров и открой диагностику снова.',
          )
        else
          for (var i = 0; i < entries.length; i++)
            _HttpEntryTile(
              index: i + 1,
              entry: entries[i],
            ),
        const SizedBox(height: 14),
        _DataSection(
          title: 'Snapshot: товары, которые пришли с сервера',
          subtitle: '${snapshotProducts.length} записей',
          data: snapshotProducts,
        ),
        _DataSection(
          title: 'Локально сохранённые товары',
          subtitle: '${localProducts.length} записей',
          data: localProducts,
        ),
        _DataSection(
          title: 'Полный отчёт без сокращений',
          subtitle: 'request/response/snapshot/local state',
          data: report,
        ),
      ],
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.lastError,
    required this.errorCount,
    required this.requestCount,
    required this.snapshotProductsCount,
    required this.localProductsCount,
    required this.bootstrapSummary,
    required this.localState,
  });

  final String lastError;
  final int errorCount;
  final int requestCount;
  final int snapshotProductsCount;
  final int localProductsCount;
  final Map<String, dynamic> bootstrapSummary;
  final Map<String, dynamic> localState;

  @override
  Widget build(BuildContext context) {
    final counts = _asMap(bootstrapSummary['saved_counts']);
    final syncState = _asMap(localState['sync_state']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                errorCount > 0
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                color: errorCount > 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lastError.isEmpty
                      ? 'Последняя ошибка не записана. Смотри очередь сервисов ниже.'
                      : lastError,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'HTTP шагов', value: '$requestCount'),
              _MetricChip(label: 'Ошибок', value: '$errorCount'),
              _MetricChip(
                label: 'Товаров в snapshot',
                value: '$snapshotProductsCount',
              ),
              _MetricChip(
                label: 'Товаров локально',
                value: '$localProductsCount',
              ),
              if (counts.isNotEmpty)
                _MetricChip(
                  label: 'Bootstrap products',
                  value: '${counts['products'] ?? 0}',
                ),
              if (syncState.isNotEmpty)
                _MetricChip(
                  label: 'Cursor',
                  value: '${syncState['cursor'] ?? 0}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

class _HttpEntryTile extends StatelessWidget {
  const _HttpEntryTile({
    required this.index,
    required this.entry,
  });

  final int index;
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final phase = (entry['phase'] ?? '').toString();
    final request = _asMap(entry['request']);
    final response = _asMap(entry['response']);
    final method = (request['method'] ?? '').toString();
    final uri = (request['uri'] ?? request['url'] ?? entry['path'] ?? '')
        .toString()
        .trim();
    final status = response['status_code'];
    final isError = _isErrorEntry(entry);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isError ? const Color(0xFFFCA5A5) : const Color(0xFFE5E7EB),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor:
              isError ? const Color(0xFFFEE2E2) : const Color(0xFFEFF6FF),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color:
                  isError ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8),
            ),
          ),
        ),
        title: Text(
          '${method.isEmpty ? 'HTTP' : method} $uri',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            'phase: $phase',
            if (status != null) 'status: $status',
            if ((entry['message'] ?? '').toString().trim().isNotEmpty)
              'message: ${entry['message']}',
          ].join(' | '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusPill(
          text: isError ? 'Ошибка' : (status == null ? 'Запрос' : 'Ответ'),
          isError: isError,
        ),
        children: [
          _JsonBlock(title: 'Что отправили на backend', data: request),
          const SizedBox(height: 10),
          _JsonBlock(
            title: 'Что backend вернул',
            data: response.isEmpty ? entry : response,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: isError ? const Color(0xFFB91C1C) : const Color(0xFF166534),
        ),
      ),
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection({
    required this.title,
    required this.subtitle,
    required this.data,
  });

  final String title;
  final String subtitle;
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          _JsonBlock(title: 'Данные', data: data),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({
    required this.title,
    required this.data,
  });

  final String title;
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    final json = const JsonEncoder.withIndent('  ').convert(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

bool _isErrorEntry(Map<String, dynamic> entry) {
  final phase = (entry['phase'] ?? '').toString().toLowerCase();
  final response = _asMap(entry['response']);
  final status = int.tryParse((response['status_code'] ?? '').toString());
  return phase == 'error' || (status != null && status >= 400);
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
