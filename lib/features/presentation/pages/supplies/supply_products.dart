import 'dart:async';
import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'supply_widgets.dart';

List<ProductModel> supplyBarcodeMatches(
    List<ProductModel> products, String barcode) {
  final code = barcode.trim();
  if (code.isEmpty) return [];
  final unique = <String, ProductModel>{};
  for (final p in products) {
    if ((p.id ?? '').isNotEmpty &&
        (p.barcode?.trim() == code || p.localBarcode?.trim() == code)) {
      unique[p.id!] = p;
    }
  }
  return unique.values.toList();
}

Future<ProductModel?> pickSupplyProduct(
        BuildContext context, List<ProductModel> products,
        {String initial = ''}) =>
    showDialog<ProductModel>(
        context: context,
        builder: (_) =>
            SupplyProductPicker(products: products, initial: initial));

class SupplyProductPicker extends StatefulWidget {
  const SupplyProductPicker(
      {super.key, required this.products, this.initial = ''});
  final List<ProductModel> products;
  final String initial;
  @override
  State<SupplyProductPicker> createState() => _SupplyProductPickerState();
}

class _SupplyProductPickerState extends State<SupplyProductPicker> {
  late final _search = TextEditingController(text: widget.initial);
  bool _keyboard = false;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final results = widget.products
        .where((p) =>
            (p.id ?? '').isNotEmpty &&
            (query.isEmpty ||
                p.name.toLowerCase().contains(query) ||
                (p.barcode ?? '').contains(query) ||
                (p.localBarcode ?? '').contains(query)))
        .take(100)
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: supplyBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
          width: 1000,
          height: MediaQuery.sizeOf(context).height * .9,
          child: Column(children: [
            Container(
                color: supplyInk,
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  const Expanded(
                      child: Text('Выберите товар',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white))),
                  IconButton(
                      tooltip: 'Закрыть каталог',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white)),
                ])),
            const SizedBox(height: 16),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                    controller: _search,
                    autofocus: true,
                    keyboardType: TextInputType.none,
                    onSubmitted: (barcode) {
                      final exact =
                          supplyBarcodeMatches(widget.products, barcode);
                      if (exact.length == 1) {
                        Navigator.pop(context, exact.single);
                      }
                    },
                    decoration: InputDecoration(
                        hintText: 'Название или штрихкод',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                            tooltip: 'Клавиатура поиска',
                            onPressed: () =>
                                setState(() => _keyboard = !_keyboard),
                            icon: const Icon(Icons.keyboard_outlined))))),
            const SizedBox(height: 12),
            Expanded(
                child: results.isEmpty
                    ? const Center(
                        child: Text(
                            'Товар не найден. Его можно создать в приёмке.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = results[i];
                          return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                  minVerticalPadding: 18,
                                  leading: const Icon(
                                      Icons.inventory_2_outlined,
                                      color: supplyGreen),
                                  title: Text(p.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                      '${p.barcode ?? p.localBarcode ?? 'Без штрихкода'} · ${p.measurementUnit}'),
                                  trailing: const Icon(Icons.add_circle_outline,
                                      color: supplyGreen),
                                  onTap: () => Navigator.pop(context, p)));
                        })),
            if (_keyboard)
              SizedBox(
                  height: 300,
                  child: SingleChildScrollView(
                      child: OnScreenKeyboardSheet(
                          controllerGetter: () => _search,
                          onEnter: () => setState(() => _keyboard = false),
                          onClose: () => setState(() => _keyboard = false)))),
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Показаны первые 100 совпадений. Уточните поиск.',
                    style: TextStyle(color: supplyMuted))),
          ])),
    );
  }
}
