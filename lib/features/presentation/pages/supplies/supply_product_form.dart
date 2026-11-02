import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/pos_category.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/models/product_creation_form.dart';
import 'package:leemon_app/core/models/supply.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/product_remote_datasource.dart';
import 'package:leemon_app/features/data/datasources/supplies_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'supplies_controller.dart';
import 'supply_widgets.dart';

class SupplyCreatedProduct {
  const SupplyCreatedProduct(this.product, this.arrivalPrice);
  final ProductModel product;
  final double arrivalPrice;
}

Future<SupplyCreatedProduct?> showSupplyProductForm(BuildContext context,
    {required SuppliesController controller, String barcode = ''}) {
  final auth = context.read<AuthTokenProvider>();
  return showDialog<SupplyCreatedProduct>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SupplyProductForm(
          posKey: controller.posKey,
          deviceId: controller.deviceId,
          userId: auth.activeUserId ?? '',
          managerKey: controller.isDirector ? null : controller.managerKey,
          api: sl<ProductRemoteDataSource>(),
          initialBarcode: barcode,
          loadCategories: () => sl<PosSyncService>().loadCategories(),
          cacheProduct: (p) => sl<PosSyncService>().cacheServerProduct(p)));
}

class SupplyProductForm extends StatefulWidget {
  const SupplyProductForm(
      {super.key,
      required this.api,
      required this.posKey,
      required this.deviceId,
      required this.userId,
      this.managerKey,
      this.initialBarcode = '',
      this.loadCategories,
      this.cacheProduct});
  final ProductRemoteDataSource api;
  final String posKey, deviceId, userId, initialBarcode;
  final String? managerKey;
  final Future<List<PosCategory>> Function()? loadCategories;
  final Future<void> Function(ProductModel)? cacheProduct;
  @override
  State<SupplyProductForm> createState() => _SupplyProductFormState();
}

class _SupplyProductFormState extends State<SupplyProductForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _localCode = TextEditingController(),
      _sku = TextEditingController();
  late final _barcode = TextEditingController(text: widget.initialBarcode);
  MeasurementUnit _unit = MeasurementUnit.pieces,
      _packUnit = MeasurementUnit.box;
  List<PosCategory> _categories = [];
  String? _category, _error;
  double _cost = 0, _price = 0, _wholesale = 0, _conversion = 1;
  bool _packaging = false, _busy = false, _uncertain = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final categories = await widget.loadCategories?.call() ?? <PosCategory>[];
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Категории не загрузились. Товар можно сохранить без категории.');
      }
    }
  }

  @override
  void dispose() {
    for (final text in [_name, _localCode, _sku, _barcode]) {
      text.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _uncertain || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    ProductModel? created;
    try {
      created = await widget.api.createFullProduct(
          key: widget.posKey,
          deviceId: widget.deviceId,
          userId: widget.userId,
          managerAccessKey: widget.managerKey,
          form: ProductCreationForm(
              name: _name.text,
              barcode: _barcode.text,
              localBarcode: _localCode.text,
              sku: _sku.text,
              categoryId: _category,
              measurementUnit: _unit,
              arrivalCost: _cost,
              sellingPrice: _price,
              wholesalePrice: _wholesale,
              conversionValue: _packaging ? _conversion : null,
              conversionUnit: _packaging ? _packUnit.apiValue : null));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = supplyError(e);
          _uncertain = e is! DioException ||
              e.response == null ||
              (e.response?.statusCode ?? 500) >= 500;
        });
      }
    }
    if (created != null) {
      // A local-cache failure cannot make a successful POST look like a failed
      // creation: the server identity must be returned to the receipt editor.
      try {
        await widget.cacheProduct?.call(created);
      } catch (_) {}
      if (mounted) Navigator.pop(context, SupplyCreatedProduct(created, _cost));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _amount(String label, double value, ValueChanged<double> changed,
          {bool quantity = false}) =>
      OutlinedButton(
          onPressed: _busy || _uncertain
              ? null
              : () async {
                  final next = await supplyNumberDialog(context,
                      title: label, value: value, quantity: quantity);
                  if (next != null && mounted) setState(() => changed(next));
                },
          style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size(double.infinity, 76)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: supplyMuted)),
            const SizedBox(height: 6),
            Text(quantity ? supplyQuantity(value) : supplyMoney(value),
                style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: supplyInk)),
          ]));

  Widget _section(String title, List<Widget> children) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: supplyBackground, borderRadius: BorderRadius.circular(18)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: supplyInk)),
            const SizedBox(height: 18),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              children[i]
            ],
          ]));

  @override
  Widget build(BuildContext context) {
    final editable = !_busy && !_uncertain;
    return PopScope(
        canPop: !_busy,
        child: SupplyDialog(
          width: 1040,
          canClose: !_busy,
          title: const Text('Новый товар'),
          subtitle: 'Карточка товара · заполните данные и добавьте в приёмку',
          icon: Icons.add_box_outlined,
          content: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_busy)
                  const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: LinearProgressIndicator(color: supplyGreen)),
                if (_error != null) SupplyMessage(_error!, error: true),
                if (_uncertain)
                  const SupplyMessage(
                      'Ответ на создание не получен. Повторная отправка заблокирована. Закройте окно и проверьте товар по штрихкоду в каталоге.',
                      error: true),
                LayoutBuilder(builder: (_, constraints) {
                  final identity = _section('Основные данные', [
                    SupplyTouchField(
                        controller: _name,
                        label: 'Название товара *',
                        enabled: editable,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Укажите название'
                            : null),
                    SupplyTouchField(
                        controller: _barcode,
                        label: 'Штрихкод *',
                        numeric: true,
                        maxLength: 64,
                        enabled: editable,
                        validator: (v) =>
                            RegExp(r'^\d{11,13}$').hasMatch((v ?? '').trim())
                                ? null
                                : 'Введите 11–13 цифр'),
                    SupplyTouchField(
                        controller: _localCode,
                        label: 'Внутренний штрихкод',
                        numeric: true,
                        maxLength: 64,
                        enabled: editable),
                    SupplyTouchField(
                        controller: _sku,
                        label: 'Артикул',
                        enabled: editable,
                        maxLength: 64),
                    SupplySelect(
                        label: 'Категория',
                        value: _category,
                        items: _categories
                            .map((v) => SupplyReference(v.id, v.name))
                            .toList(),
                        onChanged: editable
                            ? (v) => setState(() => _category = v)
                            : null),
                    DropdownButtonFormField<MeasurementUnit>(
                        initialValue: _unit,
                        isExpanded: true,
                        itemHeight: 56,
                        decoration: const InputDecoration(
                            labelText: 'Единица измерения'),
                        items: MeasurementUnit.values
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(v.apiValue)))
                            .toList(),
                        onChanged: editable
                            ? (v) => setState(() => _unit = v!)
                            : null),
                  ]);
                  final pricing = _section('Цены и упаковка', [
                    _amount('Закупочная цена', _cost, (v) => _cost = v),
                    _amount('Розничная цена', _price, (v) => _price = v),
                    _amount('Оптовая цена', _wholesale, (v) => _wholesale = v),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Упаковка / пересчёт'),
                        subtitle:
                            const Text('Для коробок, упаковок и других единиц'),
                        value: _packaging,
                        onChanged: editable
                            ? (v) => setState(() => _packaging = v)
                            : null),
                    if (_packaging) ...[
                      _amount('Количество в упаковке', _conversion,
                          (v) => _conversion = v,
                          quantity: true),
                      DropdownButtonFormField<MeasurementUnit>(
                          initialValue: _packUnit,
                          isExpanded: true,
                          itemHeight: 56,
                          decoration: const InputDecoration(
                              labelText: 'Единица упаковки'),
                          items: MeasurementUnit.values
                              .map((v) => DropdownMenuItem(
                                  value: v, child: Text(v.apiValue)))
                              .toList(),
                          onChanged: editable
                              ? (v) => setState(() => _packUnit = v!)
                              : null),
                    ],
                    const Text(
                        '* Обязательные поля. Остаток увеличится после проведения приёмки.',
                        style: TextStyle(
                            color: supplyMuted, fontSize: 12, height: 1.5)),
                  ]);
                  return constraints.maxWidth >= 800
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(child: identity),
                              const SizedBox(width: 20),
                              Expanded(child: pricing)
                            ])
                      : Column(children: [
                          identity,
                          const SizedBox(height: 20),
                          pricing
                        ]);
                }),
              ])),
          actions: [
            OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton.icon(
                onPressed: editable ? _save : null,
                icon: const Icon(Icons.add_task),
                label: Text(_busy ? 'Сохраняем…' : 'Создать и добавить'))
          ],
        ));
  }
}
