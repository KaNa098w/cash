import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/domain/entities/cart_item.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';

Future<bool> addProductToCartWithConversionFlow(
  BuildContext context,
  ProductModel product,
) async {
  if (!product.hasConversion) {
    context.read<PosCubit>().addFromProductModel(product);
    return true;
  }

  final qtyToAdd = await showDialog<double>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ConversionProductDialog(
      product: product,
    ),
  );

  if (qtyToAdd == null || qtyToAdd <= 0) return false;

  if (!context.mounted) return false;
  context.read<PosCubit>().setConvertedProductQuantity(product, qtyToAdd);
  return true;
}

Future<void> editConvertedCartItem(
  BuildContext context, {
  required int index,
  required CartItem item,
}) async {
  final product = ProductModel(
    id: item.product.id,
    name: item.product.name,
    measurementUnit: item.product.measurementUnit,
    arrivalCost: item.product.arrivalCost,
    sellingPrice: item.product.price,
    wholesalePrice: 0,
    quantity: item.product.quantity,
    conversionValue: item.product.conversionValue,
    conversionUnit: item.product.conversionUnit,
    discountType: item.product.discountType,
    discountPercent: item.product.discountPercent,
    priceAfterDiscount: item.product.priceAfterDiscount,
  );
  final qty = await showDialog<double>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ConversionProductDialog(
      product: product,
      initialPhysicalQuantity: item.qty,
    ),
  );
  if (qty == null || qty <= 0 || !context.mounted) return;
  context.read<PosCubit>().setQty(index, qty);
}

enum _InputTarget { measurement, pieces }

class _ConversionProductDialog extends StatefulWidget {
  const _ConversionProductDialog({
    required this.product,
    this.initialPhysicalQuantity,
  });

  final ProductModel product;
  final double? initialPhysicalQuantity;

  @override
  State<_ConversionProductDialog> createState() =>
      _ConversionProductDialogState();
}

class _ConversionProductDialogState extends State<_ConversionProductDialog> {
  final TextEditingController _measurementController = TextEditingController();
  final TextEditingController _piecesController = TextEditingController();
  final FocusNode _measurementFocusNode = FocusNode();
  final FocusNode _piecesFocusNode = FocusNode();

  _InputTarget _activeTarget = _InputTarget.measurement;
  bool _isSyncing = false;
  Timer? _recalcDebounce;

  @override
  void initState() {
    super.initState();
    final initialPieces = widget.initialPhysicalQuantity;
    final cv = widget.product.conversionValue ?? 0;
    if (initialPieces != null && initialPieces > 0) {
      _setText(_piecesController, _formatNumber(initialPieces));
      _setText(
        _measurementController,
        _formatNumber(initialPieces * cv, fractionDigits: 3),
      );
    }
    _measurementFocusNode.addListener(() {
      if (_measurementFocusNode.hasFocus) {
        setState(() => _activeTarget = _InputTarget.measurement);
      }
    });
    _piecesFocusNode.addListener(() {
      if (_piecesFocusNode.hasFocus) {
        setState(() => _activeTarget = _InputTarget.pieces);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measurementFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _recalcDebounce?.cancel();
    _measurementController.dispose();
    _piecesController.dispose();
    _measurementFocusNode.dispose();
    _piecesFocusNode.dispose();
    super.dispose();
  }

  double? _parseValue(String raw) {
    final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String _formatNumber(num value, {int fractionDigits = 2}) {
    final fixed = value.toStringAsFixed(fractionDigits);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _setText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  int _physicalQuantityFor(double measurement, double conversionValue) {
    if (measurement <= 0 || conversionValue <= 0) return 0;
    // Avoid an exact converted area such as 63.930 / 2.131 becoming
    // 30.000000000000004 in binary floating point and ceil() returning 31.
    final ratio = measurement / conversionValue;
    final normalizedRatio = double.parse(ratio.toStringAsFixed(9));
    return normalizedRatio.ceil();
  }

  void _syncFromMeasurement() {
    if (_isSyncing) return;
    _isSyncing = true;
    final cv = widget.product.conversionValue ?? 0;
    final measurement = _parseValue(_measurementController.text) ?? 0;
    final pieces = _physicalQuantityFor(measurement, cv);
    final actualMeasurement =
        pieces > 0 ? double.parse((pieces * cv).toStringAsFixed(3)) : 0;
    _setText(_piecesController, pieces <= 0 ? '' : pieces.toString());
    _setText(
      _measurementController,
      actualMeasurement <= 0 ? '' : _formatNumber(actualMeasurement),
    );
    _isSyncing = false;
    setState(() {});
  }

  void _syncFromPieces() {
    if (_isSyncing) return;
    _isSyncing = true;
    final cv = widget.product.conversionValue ?? 0;
    final pieces = (_parseValue(_piecesController.text) ?? 0).round();
    final measurement =
        pieces > 0 ? double.parse((pieces * cv).toStringAsFixed(3)) : 0;
    _setText(
      _measurementController,
      measurement <= 0 ? '' : _formatNumber(measurement),
    );
    _isSyncing = false;
    setState(() {});
  }

  void _runSyncNow() {
    _recalcDebounce?.cancel();
    if (_activeTarget == _InputTarget.measurement) {
      _syncFromMeasurement();
    } else {
      _syncFromPieces();
    }
  }

  void _scheduleSync() {
    _recalcDebounce?.cancel();
    _recalcDebounce = Timer(const Duration(milliseconds: 800), _runSyncNow);
  }

  void _clear() {
    _recalcDebounce?.cancel();
    _setText(_measurementController, '');
    _setText(_piecesController, '');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final cv = product.conversionValue ?? 0;
    final measurementValue = _parseValue(_measurementController.text) ?? 0;
    final piecesValue =
        (_parseValue(_piecesController.text) ?? 0).roundToDouble();
    final hasRequiredDiscount = product.discountType == 'fixed' &&
        product.priceAfterDiscount > 0 &&
        product.priceAfterDiscount < product.sellingPrice;
    final unitPrice =
        hasRequiredDiscount ? product.priceAfterDiscount : product.sellingPrice;
    final totalAmount = measurementValue * unitPrice;
    final canConfirm = piecesValue > 0;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FBFA),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3ED),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          size: 22,
                          color: Color(0xFF1F7A55),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF15231A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoChip(
                                  icon: Icons.payments_outlined,
                                  label: hasRequiredDiscount
                                      ? '${money(unitPrice)} / ${product.measurementUnit} со скидкой'
                                      : '${money(unitPrice)} / ${product.measurementUnit}',
                                ),
                                _InfoChip(
                                  icon: Icons.straighten_rounded,
                                  label:
                                      '1 ${product.conversionUnit} = ${_formatNumber(cv, fractionDigits: 3)} ${product.measurementUnit}',
                                ),
                                // _InfoChip(
                                //   icon: Icons.inventory_2_outlined,
                                //   label:
                                //       'Остаток: ${_formatNumber(widget.remainingQty)} шт.',
                                // ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _LinkedInputCard(
                          label: product.measurementUnit,
                          controller: _measurementController,
                          focusNode: _measurementFocusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^[0-9]*[.,]?[0-9]*$'),
                            ),
                          ],
                          selected: _activeTarget == _InputTarget.measurement,
                          hintText: '0',
                          onChanged: (_) => _scheduleSync(),
                          onTap: () {
                            setState(
                                () => _activeTarget = _InputTarget.measurement);
                            _measurementFocusNode.requestFocus();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LinkedInputCard(
                          label: 'Количество, ${product.conversionUnit}',
                          controller: _piecesController,
                          focusNode: _piecesFocusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: false),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^[0-9]*$')),
                          ],
                          selected: _activeTarget == _InputTarget.pieces,
                          hintText: '0',
                          onChanged: (_) => _scheduleSync(),
                          onTap: () {
                            setState(() => _activeTarget = _InputTarget.pieces);
                            _piecesFocusNode.requestFocus();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AmountKeypad(
                        text: _activeTarget == _InputTarget.measurement
                            ? _measurementController.text
                            : _piecesController.text,
                        allowDecimal: _activeTarget == _InputTarget.measurement,
                        showQuickRows: false,
                        onChanged: (next) {
                          final controller =
                              _activeTarget == _InputTarget.measurement
                                  ? _measurementController
                                  : _piecesController;
                          _setText(controller, next);
                          _scheduleSync();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _clear,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                side:
                                    const BorderSide(color: Color(0xFFD1D9D4)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Очистить',
                                  style: TextStyle(color: Colors.black)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF163F2C), Color(0xFF1F7A55)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Будет добавлено',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatNumber(measurementValue)} ${product.measurementUnit}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _SummaryTile(
                              title: 'Количество',
                              value:
                                  '${piecesValue.toInt()} ${product.conversionUnit}',
                            ),
                            _SummaryTile(
                              title: 'Сумма',
                              value: money(totalAmount),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            side: const BorderSide(color: Color(0xFFD1D9D4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: canConfirm
                              ? () {
                                  _runSyncNow();
                                  final finalPieces =
                                      (_parseValue(_piecesController.text) ?? 0)
                                          .roundToDouble();
                                  if (finalPieces <= 0) {
                                    return;
                                  }
                                  Navigator.of(context).pop(finalPieces);
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: const Color(0xFF1F7A55),
                            disabledBackgroundColor: const Color(0xFF9CB7AA),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Добавить в чек'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkedInputCard extends StatelessWidget {
  const _LinkedInputCard({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.keyboardType,
    required this.inputFormatters,
    required this.selected,
    required this.hintText,
    required this.onChanged,
    required this.onTap,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final bool selected;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF1F7A55) : const Color(0xFFD6E0DA),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              onChanged: onChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE6E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1F7A55)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF243B2E),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
