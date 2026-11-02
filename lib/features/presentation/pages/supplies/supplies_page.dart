import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/supplies_remote_datasource.dart';
import 'supplies_controller.dart';
import 'supply_editor.dart';
import 'supply_widgets.dart';

class SuppliesPage extends StatefulWidget {
  const SuppliesPage({super.key, this.controller});
  final SuppliesController? controller;
  @override
  State<SuppliesPage> createState() => _SuppliesPageState();
}

class _SuppliesPageState extends State<SuppliesPage> {
  late final SuppliesController c;
  final _number = TextEditingController();
  String? _supplier, _warehouse;
  String _completed = '', _payment = '';
  DateTime? _from, _to;
  bool _filtersOpen = false;
  @override
  void initState() {
    super.initState();
    final auth =
        widget.controller == null ? context.read<AuthTokenProvider>() : null;
    final activeUserId = auth?.activeUserId?.trim() ?? '';
    final isDirector = activeUserId.isNotEmpty &&
        (auth?.users.any((u) =>
                u.id == activeUserId &&
                u.roles.any((r) => r.trim().toLowerCase() == 'director')) ??
            false);
    c = widget.controller ??
        SuppliesController(
            api: isDirector
                ? sl<SuppliesRemoteDataSource>().forDirector(activeUserId)
                : sl<SuppliesRemoteDataSource>(),
            posKey: auth!.posKey ?? '',
            deviceId: auth.deviceId ?? '');
    c.initialize();
  }

  @override
  void dispose() {
    _number.dispose();
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_from != null && _to != null && _from!.isAfter(_to!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Начало периода должно быть не позже конца.')));
      return;
    }
    c.filters
      ..clear()
      ..addAll({
        if ((_supplier ?? '').isNotEmpty) 'supplier_id': _supplier,
        if ((_warehouse ?? '').isNotEmpty) 'warehouse_id': _warehouse,
        if (_number.text.trim().isNotEmpty) 'number': _number.text.trim(),
        if (_from != null) 'from': supplyDay(_from!),
        if (_to != null) 'to': supplyDay(_to!),
        if (_completed.isNotEmpty) 'completed': _completed == 'true',
        if (_payment.isNotEmpty) 'payment_status': _payment,
      });
    await c.refresh(pageNumber: 1);
  }

  Future<void> _edit([SupplyDocument? document]) async {
    if (c.busy) return;
    Map<String, dynamic>? draft = await c.loadDraft();
    if (!mounted) return;
    if (draft != null &&
        c.pending == null &&
        (document == null || draft['id'] != document.id)) {
      final choice = await showDialog<String>(
          context: context,
          builder: (_) => SupplyDialog(
                  title: const Text('На кассе есть локальный черновик'),
                  content: const Text(
                      'Восстановите несохранённые изменения или удалите их перед открытием другой приёмки.'),
                  actions: [
                    if (c.isDirector)
                      const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                              child: Text('Директор',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)))),
                    if (!c.isDirector)
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Отмена')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'discard'),
                        child: const Text('Удалить локальный черновик')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, 'resume'),
                        child: const Text('Восстановить'))
                  ]));
      if (choice == null || !mounted) return;
      if (choice == 'discard') {
        await c.clearDraft();
        draft = null;
      } else {
        final id = draft['id']?.toString();
        if (id != null && id.isNotEmpty) {
          if (!await c.open(id) || !mounted) return;
          document = c.selected;
        } else {
          document = null;
        }
      }
    }
    if (!mounted) return;
    final matchingDraft =
        draft != null && draft['id'] == document?.id ? draft : null;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SupplyEditor(
            controller: c, document: document, draft: matchingDraft)));
    if (mounted) await c.refresh();
  }

  Widget _dateFilter(bool start) {
    final value = start ? _from : _to;
    return OutlinedButton.icon(
        onPressed: c.busy
            ? null
            : () async {
                final date = await showDatePicker(
                    context: context,
                    initialDate: value ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    builder: (ctx, child) =>
                        Theme(data: supplyTheme(ctx), child: child!),
                    initialEntryMode: DatePickerEntryMode.calendarOnly);
                if (date != null && mounted) {
                  setState(() {
                    if (start) {
                      _from = date;
                    } else {
                      _to = date;
                    }
                  });
                }
              },
        icon: const Icon(Icons.calendar_today_outlined, size: 20),
        label: Text(
            '${start ? 'С' : 'По'}: ${value == null ? 'любая дата' : supplyDisplayDay(supplyDay(value))}'));
  }

  Widget _filters() => Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
                width: 240,
                child: SupplyNoteField(
                    controller: _number,
                    label: 'Номер приёмки',
                    enabled: !c.busy)),
            SizedBox(
                width: 240,
                child: SupplySelect(
                    label: 'Поставщик',
                    items: c.references.suppliers,
                    value: _supplier,
                    allowEmpty: true,
                    onChanged:
                        c.busy ? null : (v) => setState(() => _supplier = v))),
            SizedBox(
                width: 220,
                child: SupplySelect(
                    label: 'Склад',
                    items: c.references.warehouses,
                    value: _warehouse,
                    allowEmpty: true,
                    onChanged:
                        c.busy ? null : (v) => setState(() => _warehouse = v))),
            SizedBox(
                width: 210,
                child: SupplySelect(
                    label: 'Статус документа',
                    items: const [
                      SupplyReference('true', 'Проведённые'),
                      SupplyReference('false', 'Черновики')
                    ],
                    value: _completed,
                    allowEmpty: true,
                    onChanged: c.busy
                        ? null
                        : (v) => setState(() => _completed = v ?? ''))),
            SizedBox(
                width: 210,
                child: SupplySelect(
                    label: 'Оплата',
                    items: const [
                      SupplyReference('paid', 'Оплаченные'),
                      SupplyReference('unpaid', 'Неоплаченные')
                    ],
                    value: _payment,
                    allowEmpty: true,
                    onChanged: c.busy
                        ? null
                        : (v) => setState(() => _payment = v ?? ''))),
            _dateFilter(true),
            _dateFilter(false),
            FilledButton(
                onPressed: c.busy ? null : _apply,
                child: const Text('Применить')),
            TextButton(
                onPressed: c.busy
                    ? null
                    : () {
                        setState(() {
                          _number.clear();
                          _supplier = null;
                          _warehouse = null;
                          _completed = '';
                          _payment = '';
                          _from = null;
                          _to = null;
                        });
                        _apply();
                      },
                child: const Text('Сбросить')),
          ]));

  Widget _card(SupplyDocument d) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: c.busy
              ? null
              : () async {
                  if (await c.open(d.id) && mounted) await _edit(c.selected);
                },
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE3F3EC),
                              borderRadius: BorderRadius.circular(13)),
                          child: const Icon(Icons.move_to_inbox_outlined,
                              color: supplyGreen)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Приёмка № ${d.number}',
                                style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: supplyInk)),
                            const SizedBox(height: 4),
                            Text(
                                '${supplyDisplayDay(d.date)} · ${d.supplierName}',
                                style: const TextStyle(color: supplyMuted)),
                          ])),
                      SupplyStatus(completed: d.completed)
                    ]),
                    const SizedBox(height: 18),
                    Wrap(spacing: 24, runSpacing: 8, children: [
                      Text(d.warehouseName,
                          style: const TextStyle(color: supplyMuted)),
                      Text(supplyMoney(d.total),
                          style: const TextStyle(
                              color: supplyInk,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      Text('Оплачено ${supplyMoney(d.paid)}',
                          style: const TextStyle(color: supplyGreen)),
                      Text('Осталось ${supplyMoney(d.unpaid)}',
                          style: const TextStyle(color: supplyMuted)),
                    ]),
                  ]))));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (_, __) => Theme(
          data: supplyTheme(context),
          child: PopScope(
            canPop: !c.busy,
            child: Scaffold(
              appBar: AppBar(
                  backgroundColor: supplyInk,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                      tooltip: 'Вернуться на кассу',
                      onPressed: c.busy ? null : () => context.go('/pos'),
                      icon: const Icon(Icons.arrow_back)),
                  title: const Text('Приёмка товаров'),
                  actions: [
                    IconButton(
                        tooltip: c.hasManagerKey
                            ? 'Убрать ключ управляющего'
                            : 'Ввести ключ управляющего',
                        onPressed: c.busy
                            ? null
                            : () async {
                                if (c.hasManagerKey) {
                                  c.clearManagerKey();
                                } else {
                                  await ensureSupplyAccess(context, c);
                                }
                              },
                        icon: Icon(c.hasManagerKey
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline)),
                    IconButton(
                        tooltip: 'Обновить приёмки',
                        onPressed: c.busy ? null : () => c.refresh(),
                        icon: const Icon(Icons.refresh)),
                    const SizedBox(width: 12)
                  ]),
              body: Column(children: [
                if (c.busy) const LinearProgressIndicator(color: supplyGreen),
                Expanded(
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 14,
                      children: [
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Поступления от поставщиков',
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: supplyInk)),
                              SizedBox(height: 6),
                              Text('Документы, товары и расчёты с поставщиками',
                                  style: TextStyle(color: supplyMuted))
                            ]),
                        Wrap(spacing: 12, runSpacing: 10, children: [
                          OutlinedButton.icon(
                              onPressed: c.busy
                                  ? null
                                  : () => setState(
                                      () => _filtersOpen = !_filtersOpen),
                              icon: const Icon(Icons.tune),
                              label: const Text('Фильтры')),
                          FilledButton.icon(
                              onPressed: c.busy || c.pending != null
                                  ? null
                                  : () => _edit(),
                              icon: const Icon(Icons.add),
                              label: const Text('Новая приёмка')),
                        ]),
                      ]),
                  const SizedBox(height: 20),
                  SupplyPendingBanner(
                      controller: c,
                      refresh: () => c.refresh(),
                      allowReview: true),
                  if (c.error != null) SupplyMessage(c.error!, error: true),
                  if (_filtersOpen) _filters(),
                  if (c.page != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Wrap(spacing: 20, runSpacing: 8, children: [
                          Text('На странице: ${c.page!.items.length}',
                              style: const TextStyle(color: supplyMuted)),
                          if (c.page!.summary['count'] != null)
                            Text(
                                'Всего документов: ${c.page!.summary['count']}'),
                          if (c.page!.summary['total_amount'] != null)
                            Text(
                                'Сумма: ${supplyMoney(supplyNumber(c.page!.summary['total_amount']))}'),
                          if (c.page!.summary['payments_total'] != null)
                            Text(
                                'Оплачено: ${supplyMoney(supplyNumber(c.page!.summary['payments_total']))}'),
                          if (c.page!.summary['document_unpaid_amount'] != null)
                            Text(
                                'Долг: ${supplyMoney(supplyNumber(c.page!.summary['document_unpaid_amount']))}'),
                        ])),
                  if (c.page?.items.isEmpty == true)
                    Container(
                        padding: const EdgeInsets.all(48),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20)),
                        child: Column(children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 64, color: supplyGreen),
                          const SizedBox(height: 20),
                          const Text('Приёмок пока нет',
                              style: TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(
                              c.isDirector
                                  ? 'Создайте документ или измените фильтры. Доступ директора активен.'
                                  : 'Создайте документ или измените фильтры. Для записи потребуется ключ управляющего.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: supplyMuted))
                        ])),
                  ...?c.page?.items.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _card(d))),
                  if (c.page != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                  tooltip: 'Предыдущая страница',
                                  onPressed: !c.busy && c.page!.page > 1
                                      ? () => c.refresh(
                                          pageNumber: c.page!.page - 1)
                                      : null,
                                  icon:
                                      const Icon(Icons.chevron_left, size: 30)),
                              Text('${c.page!.page} / ${c.page!.lastPage}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              IconButton(
                                  tooltip: 'Следующая страница',
                                  onPressed:
                                      !c.busy && c.page!.page < c.page!.lastPage
                                          ? () => c.refresh(
                                              pageNumber: c.page!.page + 1)
                                          : null,
                                  icon: const Icon(Icons.chevron_right,
                                      size: 30)),
                            ])),
                ])),
              ]),
            ),
          )));
}
