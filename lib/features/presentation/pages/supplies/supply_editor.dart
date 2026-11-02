import 'dart:async';
import 'package:flutter/material.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'package:leemon_app/features/data/datasources/product_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'supply_product_form.dart';
import 'supplies_controller.dart';
import 'supply_widgets.dart';
import 'supply_products.dart';
import 'supply_payments.dart';

class SupplyEditor extends StatefulWidget {
  const SupplyEditor(
      {super.key,
      required this.controller,
      this.document,
      this.draft,
      this.loadProducts,
      this.createProduct});
  final SuppliesController controller;
  final SupplyDocument? document;
  final Map<String, dynamic>? draft;
  final Future<List<ProductModel>> Function()? loadProducts;
  final Future<ProductModel?> Function(String barcode)? createProduct;
  @override
  State<SupplyEditor> createState() => _SupplyEditorState();
}

class _SupplyEditorState extends State<SupplyEditor> {
  SuppliesController get c => widget.controller;
  SupplyDocument? _document;
  List<ProductModel> _products = [];
  final _lines = <SupplyLine>[];
  final _note = TextEditingController(), _scan = TextEditingController();
  final _scanFocus = FocusNode();
  DateTime _date = DateTime.now();
  String? _supplier, _warehouse, _localError;
  bool _loadingProducts = true, _lookingUp = false, _dirty = false;
  bool _detailsOpen = true;
  Future<void> _draftTail = Future.value();
  bool get _locked => c.busy || c.pending != null || _lookingUp;
  bool get _editable => !_locked && !(_document?.completed ?? false);
  double get _total => _lines.fold(0, (sum, l) => sum + l.total);

  @override
  void initState() {
    super.initState();
    _hydrate(widget.document);
    final draft = widget.draft;
    if (draft != null && !(widget.document?.completed ?? false)) {
      _date = DateTime.tryParse('${draft['date']}') ?? DateTime.now();
      _supplier = draft['supplier_id'] as String?;
      _warehouse = draft['warehouse_id'] as String?;
      _note.text = '${draft['note'] ?? ''}';
      _lines
        ..clear()
        ..addAll((draft['items'] as List? ?? [])
            .whereType<Map>()
            .map((l) => SupplyLine.fromJson(supplyMap(l))));
      _dirty = true;
    }
    _loadProducts();
    _detailsOpen = widget.document == null && _lines.isEmpty;
  }

  void _hydrate(SupplyDocument? document) {
    _document = document;
    if (document == null) {
      _warehouse = c.references.warehouses.length == 1
          ? c.references.warehouses.single.id
          : null;
      return;
    }
    _date = DateTime.tryParse(document.date) ?? DateTime.now();
    _supplier = document.supplierId;
    _warehouse = document.warehouseId;
    _note.text = document.note;
    _lines
      ..clear()
      ..addAll(document.items);
    _dirty = false;
  }

  Future<void> _loadProducts() async {
    try {
      _products = await (widget.loadProducts?.call() ??
          sl<PosSyncService>().loadProducts());
    } catch (_) {
      _localError = 'Не удалось загрузить каталог. Обновите синхронизацию.';
    }
    if (mounted) setState(() => _loadingProducts = false);
  }

  @override
  void dispose() {
    _note.dispose();
    _scan.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Map<String, dynamic> _snapshot() => {
        'id': _document?.id,
        'date': supplyDay(_date),
        'supplier_id': _supplier,
        'warehouse_id': _warehouse,
        'note': _note.text.trim(),
        'items': _lines.map((l) => l.toDraft()).toList(),
      };
  Future<void> _remember() {
    _dirty = true;
    final snapshot = _snapshot();
    _draftTail =
        _draftTail.catchError((Object _) {}).then((_) => c.saveDraft(snapshot));
    return _draftTail;
  }

  void _changed() {
    setState(() {});
    unawaited(_remember().catchError((Object _) {
      if (mounted) {
        setState(() => _localError =
            'Не удалось сохранить локальный черновик. Не закрывайте приёмку до сохранения на сервере.');
      }
    }));
  }

  Future<void> _close() async {
    if (c.busy || _lookingUp) return;
    if (_dirty) {
      try {
        await _remember();
      } catch (_) {
        if (mounted) {
          setState(() => _localError =
              'Локальный черновик не сохранён. Сохраните документ перед выходом.');
        }
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _refresh() async {
    final expectedId = c.pending?['document_id']?.toString() ?? _document?.id;
    await c.refresh();
    if (mounted &&
        c.selected != null &&
        c.selected!.id == expectedId &&
        c.pending == null) {
      await _draftTail.catchError((Object _) {});
      await c.clearDraft();
      setState(() => _hydrate(c.selected));
    }
  }

  void _add(ProductModel product, {double? arrivalPrice}) {
    if (!_editable || (product.id ?? '').isEmpty) return;
    final index = _lines.indexWhere((l) => l.productId == product.id);
    if (index >= 0) {
      _lines[index].quantity += 1;
    } else {
      final line = SupplyLine.fromProduct(product);
      if (arrivalPrice != null) line.arrivalPrice = arrivalPrice;
      _lines.add(line);
    }
    _scan.clear();
    _detailsOpen = false;
    _localError = null;
    _changed();
    _scanFocus.requestFocus();
  }

  Future<void> _create(String barcode) async {
    if (!mounted) return;
    if (!await ensureSupplyAccess(context, c)) return;
    if (!mounted) return;
    ProductModel? p;
    double? arrivalPrice;
    if (widget.createProduct != null) {
      p = await widget.createProduct!(barcode);
    } else {
      final result =
          await showSupplyProductForm(context, controller: c, barcode: barcode);
      p = result?.product;
      arrivalPrice = result?.arrivalPrice;
    }
    final created = p;
    if (!mounted || created == null) return;
    _products.removeWhere((v) => v.id == created.id);
    _products.add(created);
    _add(created, arrivalPrice: arrivalPrice);
  }

  Future<void> _scanBarcode(String raw) async {
    final barcode = raw.trim();
    if (barcode.isEmpty || !_editable) return;
    var exact = supplyBarcodeMatches(_products, barcode);
    if (exact.isEmpty && sl.isRegistered<ProductRemoteDataSource>()) {
      setState(() {
        _lookingUp = true;
        _localError = null;
      });
      try {
        final page = await sl<ProductRemoteDataSource>()
            .getProductsByBarcode(key: c.posKey, barcode: barcode);
        exact = supplyBarcodeMatches(page.items, barcode);
        for (final p in exact) {
          _products.removeWhere((v) => v.id == p.id);
          _products.add(p);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _localError =
              'Товар не найден локально; сервер недоступен. Проверьте связь перед созданием нового товара.');
        }
        return;
      } finally {
        if (mounted) setState(() => _lookingUp = false);
      }
    }
    if (!mounted) return;
    if (exact.length == 1) {
      _add(exact.single);
    } else if (exact.length > 1) {
      final p = await pickSupplyProduct(context, exact, initial: barcode);
      if (p != null && mounted) _add(p);
    } else if (await supplyConfirm(context, 'Товар не найден',
        'Точного совпадения штрихкода $barcode нет. Создать товар и добавить в приёмку?',
        button: 'Создать товар')) {
      await _create(barcode);
    }
  }

  Future<void> _editLine(SupplyLine line, String field) async {
    final value = await supplyNumberDialog(context,
        title: '$field · ${line.name}',
        value: field == 'Количество'
            ? line.quantity
            : field == 'Закупочная цена'
                ? line.arrivalPrice
                : line.price,
        quantity: field == 'Количество');
    if (value == null || !mounted || !_editable) return;
    if (field == 'Количество') {
      line.quantity = value;
    } else if (field == 'Закупочная цена') {
      line.arrivalPrice = value;
    } else {
      line.price = value;
    }
    _changed();
  }

  Future<void> _supplierCreate() async {
    if (!await ensureSupplyAccess(context, c) || !mounted) return;
    final name = await supplyTextDialog(context, title: 'Новый поставщик');
    if (name == null || !mounted) return;
    SupplyReference? created;
    final ok = await c.mutate('Создание поставщика', (manager) async {
      created =
          await c.api.supplier(c.posKey, c.deviceId, manager, {'name': name});
      return null;
    });
    if (ok && mounted && created != null) {
      _supplier = created!.id;
      _changed();
    }
  }

  Future<void> _save() async {
    if (!_editable) return;
    if ((_supplier ?? '').isEmpty ||
        (_warehouse ?? '').isEmpty ||
        _lines.isEmpty ||
        _lines.any((l) => !l.valid)) {
      setState(() => _localError =
          'Выберите поставщика, склад и добавьте товары с корректным количеством и ценами.');
      return;
    }
    if (!await ensureSupplyAccess(context, c) || !mounted) return;
    try {
      await _remember();
    } catch (_) {
      if (mounted) {
        setState(() => _localError =
            'Не удалось сохранить черновик на устройстве. Запись на сервер не отправлена.');
      }
      return;
    }
    final id = _document?.id;
    final payload = {
      'date': supplyDay(_date),
      'supplier_id': _supplier,
      'warehouse_id': _warehouse,
      'completed': false,
      'note': _note.text.trim(),
      'items': _lines.map((l) => l.toRequest()).toList()
    };
    final ok = await c.mutate('Сохранение приёмки',
        (manager) => c.api.save(c.posKey, c.deviceId, manager, payload, id: id),
        documentId: id, attachDraftIdentity: true);
    if (ok && mounted) {
      setState(() {
        _hydrate(c.selected);
        _localError = null;
      });
      try {
        await _draftTail;
        await c.clearDraft();
      } catch (_) {
        if (mounted) {
          setState(() => _localError =
              'Документ сохранён на сервере. Локальный черновик будет проверен при следующем открытии.');
        }
      }
    }
  }

  Future<void> _status() async {
    if (_document == null || _dirty || _locked) return;
    final completed = !_document!.completed;
    if (!await supplyConfirm(
        context,
        completed ? 'Провести приёмку?' : 'Вернуть в черновик?',
        completed
            ? 'Товары будут оприходованы на выбранный склад.'
            : 'Сервер отменит проведение, если это возможно. При последующих операциях с товаром он может отказать.')) {
      return;
    }
    if (!mounted || !await ensureSupplyAccess(context, c) || !mounted) return;
    final id = _document!.id;
    final ok = await c
        .mutate(completed ? 'Проведение приёмки' : 'Возврат в черновик',
            (manager) async {
      await c.api.status(c.posKey, c.deviceId, manager, id, completed);
      return id;
    }, documentId: id);
    if (ok && mounted) {
      setState(() => _hydrate(c.selected));
      if (sl.isRegistered<PosSyncService>()) {
        try {
          await sl<PosSyncService>()
              .pullOnce(key: c.posKey, deviceId: c.deviceId);
        } catch (_) {
          if (mounted) {
            setState(() => _localError =
                'Статус приёмки изменён. Остатки на кассе обновятся при следующей синхронизации.');
          }
        }
      }
    }
  }

  Future<void> _delete() async {
    if (_document == null || _document!.completed || _locked) return;
    if (!await supplyConfirm(context, 'Удалить черновик?',
        'Документ будет удалён с сервера. Это действие нельзя отменить.',
        button: 'Удалить')) {
      return;
    }
    if (!mounted || !await ensureSupplyAccess(context, c) || !mounted) return;
    final id = _document!.id;
    final ok = await c.mutate('Удаление приёмки', (manager) async {
      await c.api.delete(c.posKey, c.deviceId, manager, id);
      return id;
    }, documentId: id, deleting: true);
    if (ok && mounted) {
      await c.clearDraft();
      _dirty = false;
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _priceButton(String label, String value, VoidCallback onTap) =>
      OutlinedButton(
          onPressed: _editable ? onTap : null,
          style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: supplyMuted)),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ]));

  Widget _lineCard(SupplyLine line, int i) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: supplyBackground,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: supplyMuted, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
              child: Text(line.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: supplyInk))),
          IconButton(
              tooltip: 'Убрать ${line.name}',
              onPressed: _editable
                  ? () {
                      _lines.removeAt(i);
                      _changed();
                    }
                  : null,
              icon: const Icon(Icons.delete_outline, color: supplyMuted))
        ]),
        if (line.barcode.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(line.barcode,
                  style: const TextStyle(color: supplyMuted))),
        LayoutBuilder(builder: (_, constraints) {
          final buttons = [
            _priceButton(
                'Количество · ${line.unit}',
                supplyQuantity(line.quantity),
                () => _editLine(line, 'Количество')),
            _priceButton('Закупочная цена', supplyMoney(line.arrivalPrice),
                () => _editLine(line, 'Закупочная цена')),
            _priceButton('Розничная цена', supplyMoney(line.price),
                () => _editLine(line, 'Розничная цена')),
          ];
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (constraints.maxWidth > 540)
                  Row(children: [
                    for (var n = 0; n < buttons.length; n++) ...[
                      if (n > 0) const SizedBox(width: 10),
                      Expanded(child: buttons[n])
                    ]
                  ])
                else
                  Wrap(spacing: 8, runSpacing: 8, children: buttons),
                const SizedBox(height: 12),
                Text('Сумма закупки: ${supplyMoney(line.total)}',
                    style: const TextStyle(
                        color: supplyInk, fontWeight: FontWeight.w700)),
              ]);
        }),
      ]));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (_, __) => Theme(
          data: supplyTheme(context),
          child: PopScope(
            canPop: !c.busy && !_dirty && !_lookingUp,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _close();
            },
            child: Scaffold(
              appBar: AppBar(
                  backgroundColor: supplyInk,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                      tooltip: 'К списку приёмок',
                      onPressed: c.busy ? null : _close,
                      icon: const Icon(Icons.arrow_back)),
                  title: Text(_document == null
                      ? 'Новая приёмка'
                      : 'Приёмка № ${_document!.number}'),
                  actions: [
                    if (_document != null)
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: SupplyStatus(completed: _document!.completed)),
                    IconButton(
                        tooltip: 'Обновить документ',
                        onPressed: !c.busy &&
                                !_lookingUp &&
                                (!_dirty || c.pending != null)
                            ? _refresh
                            : null,
                        icon: const Icon(Icons.refresh))
                  ]),
              body: Column(children: [
                if (c.busy || _lookingUp)
                  const LinearProgressIndicator(color: supplyGreen),
                Expanded(
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                  SupplyPendingBanner(controller: c, refresh: _refresh),
                  if (_localError != null)
                    SupplyMessage(_localError!, error: true),
                  if (c.error != null) SupplyMessage(c.error!, error: true),
                  if (_document?.completed == true)
                    const SupplyMessage(
                        'Документ проведён. Для изменения товаров, цен или склада верните его в черновик.'),
                  Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                          minVerticalPadding: 12,
                          leading: const Icon(Icons.assignment_outlined,
                              color: supplyGreen),
                          title: const Text('Реквизиты приёмки',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: supplyInk)),
                          subtitle: Text(
                              '${c.references.suppliers.where((v) => v.id == _supplier).firstOrNull?.name ?? 'Выберите поставщика'} · ${supplyDisplayDay(supplyDay(_date))}'),
                          trailing: Icon(_detailsOpen
                              ? Icons.expand_less
                              : Icons.expand_more),
                          onTap: () =>
                              setState(() => _detailsOpen = !_detailsOpen))),
                  const SizedBox(height: 12),
                  if (_detailsOpen) ...[
                    Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                              width: 220,
                              child: OutlinedButton.icon(
                                  onPressed: _editable
                                      ? () async {
                                          final date = await showDatePicker(
                                              context: context,
                                              initialDate: _date,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                              builder: (ctx, child) => Theme(
                                                  data: supplyTheme(ctx),
                                                  child: child!),
                                              initialEntryMode:
                                                  DatePickerEntryMode
                                                      .calendarOnly);
                                          if (date != null && mounted) {
                                            _date = date;
                                            _changed();
                                          }
                                        }
                                      : null,
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
                                  label: Text(
                                      supplyDisplayDay(supplyDay(_date))))),
                          SizedBox(
                              width: 300,
                              child: SupplySelect(
                                  label: 'Поставщик',
                                  items: c.references.suppliers,
                                  value: _supplier,
                                  onChanged: _editable
                                      ? (v) {
                                          _supplier = v;
                                          _changed();
                                        }
                                      : null)),
                          OutlinedButton.icon(
                              onPressed: _editable ? _supplierCreate : null,
                              icon: const Icon(Icons.person_add_alt),
                              label: const Text('Новый поставщик')),
                          SizedBox(
                              width: 260,
                              child: SupplySelect(
                                  label: 'Склад',
                                  items: c.references.warehouses,
                                  value: _warehouse,
                                  onChanged: _editable
                                      ? (v) {
                                          _warehouse = v;
                                          _changed();
                                        }
                                      : null)),
                        ]),
                    const SizedBox(height: 16),
                    SupplyNoteField(
                        controller: _note,
                        label: 'Комментарий к приёмке',
                        enabled: _editable,
                        onChanged: (_) => _changed()),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                      controller: _scan,
                      focusNode: _scanFocus,
                      keyboardType: TextInputType.none,
                      enabled: _editable && !_loadingProducts,
                      onSubmitted: _scanBarcode,
                      decoration: InputDecoration(
                          labelText: 'Сканируйте штрихкод товара',
                          prefixIcon: const Icon(Icons.qr_code_scanner),
                          suffixIcon: IconButton(
                              tooltip: 'Ввести штрихкод на экране',
                              onPressed: _editable
                                  ? () async {
                                      final code = await supplyTextDialog(
                                          context,
                                          title: 'Штрихкод товара',
                                          numeric: true,
                                          maxLength: 64,
                                          initial: _scan.text);
                                      if (code != null && mounted) {
                                        await _scanBarcode(code);
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.keyboard_outlined)))),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 10, children: [
                    FilledButton.icon(
                        onPressed: _editable && !_loadingProducts
                            ? () async {
                                final product =
                                    await pickSupplyProduct(context, _products);
                                if (product != null && mounted) _add(product);
                              }
                            : null,
                        icon: const Icon(Icons.search),
                        label: const Text('Выбрать товар')),
                    OutlinedButton.icon(
                        onPressed: _editable ? () => _create('') : null,
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('Создать товар')),
                    if (_loadingProducts)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Загрузка каталога…')),
                  ]),
                  const SizedBox(height: 20),
                  if (_lines.isEmpty)
                    Container(
                        padding: const EdgeInsets.all(36),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18)),
                        child: const Column(children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 52, color: supplyGreen),
                          SizedBox(height: 16),
                          Text('Добавьте товары в приёмку',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800)),
                          SizedBox(height: 8),
                          Text(
                              'Отсканируйте штрихкод, выберите из каталога или создайте новый товар.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: supplyMuted))
                        ]))
                  else
                    ...List.generate(
                        _lines.length, (i) => _lineCard(_lines[i], i)),
                  const SizedBox(height: 20),
                  if (_document != null)
                    SupplyPaymentsPanel(
                        controller: c,
                        document: _document!,
                        enabled: !_locked && !_dirty,
                        onUpdated: () {
                          if (mounted) setState(() => _hydrate(c.selected));
                        }),
                ])),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${_lines.length} поз. · ${supplyMoney(_total)}',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: supplyInk)),
                          if (_dirty)
                            const Text('Есть несохранённые изменения',
                                style: TextStyle(color: supplyMuted)),
                          FilledButton.icon(
                              onPressed:
                                  _editable && _lines.isNotEmpty ? _save : null,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Сохранить черновик')),
                          if (_document != null)
                            OutlinedButton.icon(
                                onPressed: !_locked && !_dirty ? _status : null,
                                icon: Icon(_document!.completed
                                    ? Icons.undo
                                    : Icons.check_circle_outline),
                                label: Text(_document!.completed
                                    ? 'В черновик'
                                    : 'Провести приёмку')),
                          if (_document != null && !_document!.completed)
                            IconButton(
                                tooltip: 'Удалить черновик',
                                onPressed: !_locked ? _delete : null,
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent)),
                        ])),
              ]),
            ),
          )));
}
