import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/marking/gs1_datamatrix_validator.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/domain/entities/cart_item.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/search/search_keyboard_controller.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';

Future<void> showDuplicateMarkCodeDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFEA8A16),
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Код уже использован',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
          ),
        ],
      ),
      content: const SizedBox(
        width: 430,
        child: Text(
          'Этот код маркировки уже добавлен в чек. Отсканируйте код с другой упаковки.',
          style: TextStyle(
            fontSize: 16,
            height: 1.45,
            color: Color(0xFF475569),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF22B982),
            minimumSize: const Size(130, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('ОК'),
        ),
      ],
    ),
  );
  requestSearchResetAndFocus();
}

Future<bool> addProductToCartWithConversionFlow(
  BuildContext context,
  ProductModel product,
) async {
  if (product.requiresMarking) {
    return addMarkedProductToCart(context, product);
  }

  if (!product.hasConversion) {
    context.read<PosCubit>().addFromProductModel(product);
    return true;
  }

  // Discrete base units are sold one base unit per scan. Packages may be
  // fractional and are shown only as a derived value.
  if (product.allowsPartialPackages) {
    context.read<PosCubit>().addFromProductModel(product, qty: 1);
    return true;
  }

  final qtyToAdd = await showDialog<double>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ConversionProductDialog(
      product: product,
    ),
  );

  if (qtyToAdd == null || qtyToAdd <= 0) {
    requestSearchResetAndFocus();
    return false;
  }

  if (!context.mounted) return false;
  context.read<PosCubit>().setConvertedProductQuantity(product, qtyToAdd);
  return true;
}

Future<bool> addMarkedProductToCart(
  BuildContext context,
  ProductModel product, {
  String? initialMarkCode,
}) async {
  var quantity = 1.0;
  final partialMarkedPackage = product.hasConversion &&
      product.allowsPartialPackages &&
      (product.conversionValue ?? 0) > 0;

  if (partialMarkedPackage) {
    final selectedQuantity = await showDialog<double>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConversionProductDialog(product: product),
    );
    if (selectedQuantity == null || selectedQuantity <= 0) {
      requestSearchResetAndFocus();
      return false;
    }
    quantity = selectedQuantity.roundToDouble();
  }

  if (!context.mounted) return false;
  final posCubit = context.read<PosCubit>();
  final codes = <String>[
    if ((initialMarkCode ?? '').isNotEmpty) initialMarkCode!,
  ];
  final packageQuantity = partialMarkedPackage ? product.conversionValue! : 1.0;
  final requiredCodes = partialMarkedPackage
      ? (quantity / packageQuantity).ceil()
      : quantity.round();

  bool isUsedInCurrentCheck(String candidate) {
    final canonical = Gs1DataMatrixValidator.canonicalCode(candidate);
    return codes.any(
          (code) => Gs1DataMatrixValidator.canonicalCode(code) == canonical,
        ) ||
        posCubit.state.items.expand((item) => item.markCodes).any(
              (code) => Gs1DataMatrixValidator.canonicalCode(code) == canonical,
            );
  }

  if (codes.isNotEmpty &&
      posCubit.state.items.expand((item) => item.markCodes).any(
            (code) =>
                Gs1DataMatrixValidator.canonicalCode(code) ==
                Gs1DataMatrixValidator.canonicalCode(codes.first),
          )) {
    await showDuplicateMarkCodeDialog(context);
    return false;
  }

  while (codes.length < requiredCodes) {
    final markCode = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SingleMarkCodeDialog(product: product),
    );
    if (markCode == null) {
      requestSearchResetAndFocus();
      return false;
    }
    if (!context.mounted) return false;
    if (isUsedInCurrentCheck(markCode)) {
      await showDuplicateMarkCodeDialog(context);
      return false;
    }
    codes.add(markCode);
  }

  posCubit.addFromProductModel(
    product,
    qty: quantity,
    markCodes: codes,
  );
  return true;
}

Future<bool> setCartItemQuantityWithMarking(
  BuildContext context, {
  required int index,
  required double quantity,
}) async {
  final cubit = context.read<PosCubit>();
  if (index < 0 || index >= cubit.state.items.length) return false;
  final item = cubit.state.items[index];
  if (!item.product.requiresMarking) {
    cubit.setQty(index, quantity);
    return true;
  }

  final target = quantity.round();
  if ((quantity - target).abs() > 0.000001) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Маркированный товар продаётся только поштучно')),
    );
    return false;
  }
  final partialMarkedPackage = item.product.hasConversion &&
      item.product.allowsPartialPackages &&
      (item.product.conversionValue ?? 0) > 0;
  final requiredCodes = partialMarkedPackage
      ? (target / item.product.conversionValue!).ceil()
      : target;
  if (requiredCodes <= item.markCodes.length) {
    cubit.setMarkCodes(index, item.markCodes.take(requiredCodes).toList());
    cubit.setQty(index, target.toDouble());
    return true;
  }

  final codes = List<String>.from(item.markCodes);
  final product = ProductModel(
    id: item.product.id,
    name: item.product.name,
    measurementUnit: item.product.measurementUnit,
    arrivalCost: item.product.arrivalCost,
    sellingPrice: item.product.price,
    wholesalePrice: 0,
    quantity: item.product.quantity,
    requiresMarking: true,
    gtin: item.product.gtin,
    ntin: item.product.ntin,
    conversionValue: item.product.conversionValue,
    conversionUnit: item.product.conversionUnit,
  );
  while (codes.length < requiredCodes) {
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SingleMarkCodeDialog(product: product),
    );
    if (code == null) {
      requestSearchResetAndFocus();
      return false;
    }
    if (!context.mounted) return false;
    final usedInCart =
        cubit.state.items.expand((cartItem) => cartItem.markCodes).any(
              (existing) =>
                  Gs1DataMatrixValidator.canonicalCode(existing) ==
                  Gs1DataMatrixValidator.canonicalCode(code),
            );
    final usedInPending = codes.any(
      (existing) =>
          Gs1DataMatrixValidator.canonicalCode(existing) ==
          Gs1DataMatrixValidator.canonicalCode(code),
    );
    if (usedInCart || usedInPending) {
      await showDuplicateMarkCodeDialog(context);
      return false;
    }
    codes.add(code);
  }
  cubit.setMarkCodes(index, codes);
  cubit.setQty(index, target.toDouble());
  return true;
}

class _SingleMarkCodeDialog extends StatefulWidget {
  const _SingleMarkCodeDialog({required this.product});

  final ProductModel product;

  @override
  State<_SingleMarkCodeDialog> createState() => _SingleMarkCodeDialogState();
}

class _SingleMarkCodeDialogState extends State<_SingleMarkCodeDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  KeyEventResult _handleScannerKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter) {
      _submit(_controller.text);
      return KeyEventResult.handled;
    }
    if (event.physicalKey == PhysicalKeyboardKey.backspace) {
      if (_controller.text.isNotEmpty) {
        final text = _controller.text.substring(0, _controller.text.length - 1);
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      return KeyEventResult.handled;
    }
    final character = MarkingKeyboardInputFormatter.englishCharacter(event);
    if (character == null) return KeyEventResult.ignored;
    final text = '${_controller.text}$character';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String _) {
    // Enter sent by a hardware scanner is not part of controller.text.
    // Preserve all other characters, including the ASCII 29 GS separator.
    final rawCode = MarkingKeyboardInputFormatter.normalize(_controller.text);
    final validation = Gs1DataMatrixValidator.validate(
      rawCode,
      expectedGtin: (widget.product.gtin ?? '').trim().isNotEmpty
          ? widget.product.gtin
          : widget.product.ntin,
    );
    if (!validation.isValid) {
      setState(() => _error = validation.message);
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(rawCode);
  }

  @override
  Widget build(BuildContext context) {
    final identifiers = [
      if ((widget.product.gtin ?? '').isNotEmpty) 'GTIN ${widget.product.gtin}',
      if ((widget.product.ntin ?? '').isNotEmpty) 'NTIN ${widget.product.ntin}',
    ].join('  •  ');
    return AlertDialog(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Color(0xFF15966A),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сканирование маркировки',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 3),
                Text(
                  'Отсканируйте код с упаковки',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (identifiers.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      identifiers,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 19,
                  color: Color(0xFF2563EB),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Наведите сканер на квадратный код. Товар добавится в чек автоматически.',
                    style: TextStyle(color: Color(0xFF475569), height: 1.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Focus(
              onKeyEvent: _handleScannerKey,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                inputFormatters: const [MarkingKeyboardInputFormatter()],
                keyboardType: TextInputType.visiblePassword,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                autofocus: true,
                obscureText: true,
                obscuringCharacter: '•',
                onSubmitted: _submit,
                decoration: InputDecoration(
                  labelText: 'Код маркировки',
                  hintText: 'Ожидание сканера…',
                  errorText: _error,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(
                    Icons.center_focus_strong_rounded,
                    color: Color(0xFF15966A),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF22B982),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF475569),
            minimumSize: const Size(120, 48),
          ),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
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
    requiresMarking: item.product.requiresMarking,
    gtin: item.product.gtin,
    ntin: item.product.ntin,
  );
  final qty = await showDialog<double>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ConversionProductDialog(
      product: product,
      initialPhysicalQuantity: item.qty,
    ),
  );
  if (qty == null || qty <= 0) {
    requestSearchResetAndFocus();
    return;
  }
  if (!context.mounted) return;
  await setCartItemQuantityWithMarking(
    context,
    index: index,
    quantity: qty,
  );
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
  bool _replaceActiveValueOnNextKeypadInput = false;
  Timer? _recalcDebounce;

  @override
  void initState() {
    super.initState();
    final initialQuantity = widget.initialPhysicalQuantity;
    final cv = widget.product.conversionValue ?? 0;
    if (initialQuantity != null && initialQuantity > 0) {
      _setText(
        _measurementController,
        _formatNumber(initialQuantity, fractionDigits: 3),
      );
      _setText(
        _piecesController,
        _formatNumber(initialQuantity / cv, fractionDigits: 3),
      );
    }
    _measurementFocusNode.addListener(() {
      if (_measurementFocusNode.hasFocus) {
        _activateTarget(_InputTarget.measurement, selectAll: true);
      }
    });
    _piecesFocusNode.addListener(() {
      if (_piecesFocusNode.hasFocus) {
        _activateTarget(_InputTarget.pieces, selectAll: true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measurementFocusNode.requestFocus();
      _activateTarget(_InputTarget.measurement, selectAll: true);
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

  TextEditingController get _activeController =>
      _activeTarget == _InputTarget.measurement
          ? _measurementController
          : _piecesController;

  void _activateTarget(_InputTarget target, {required bool selectAll}) {
    _activeTarget = target;
    final controller = _activeController;
    if (selectAll && controller.text.isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      _replaceActiveValueOnNextKeypadInput = true;
    }
    if (mounted) setState(() {});
  }

  void _onFieldChanged(String _) {
    _replaceActiveValueOnNextKeypadInput = false;
    _scheduleSync();
  }

  void _onKeypadChanged(String next) {
    final controller = _activeController;
    final current = controller.text;
    var value = next;

    if (_replaceActiveValueOnNextKeypadInput && current.isNotEmpty) {
      if (next.startsWith(current) && next.length > current.length) {
        final entered = next.substring(current.length);
        value = entered == '.' ? '0.' : entered;
      } else if (next.length < current.length) {
        // Backspace on a fully selected initial value clears it.
        value = '';
      }
    }

    _replaceActiveValueOnNextKeypadInput = false;
    _setText(controller, value);
    _scheduleSync();
    setState(() {});
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
    final allowsPartial = widget.product.allowsPartialPackages;
    final normalizedMeasurement = allowsPartial
        ? measurement.roundToDouble()
        : (_physicalQuantityFor(measurement, cv) * cv);
    final packages = normalizedMeasurement > 0 ? normalizedMeasurement / cv : 0;
    _setText(
      _piecesController,
      packages <= 0 ? '' : _formatNumber(packages, fractionDigits: 3),
    );
    _setText(
      _measurementController,
      normalizedMeasurement <= 0
          ? ''
          : _formatNumber(normalizedMeasurement, fractionDigits: 3),
    );
    _isSyncing = false;
    setState(() {});
  }

  void _syncFromPieces() {
    if (_isSyncing) return;
    _isSyncing = true;
    final cv = widget.product.conversionValue ?? 0;
    final enteredPackages = _parseValue(_piecesController.text) ?? 0;
    final allowsPartial = widget.product.allowsPartialPackages;
    final measurement = allowsPartial
        ? (enteredPackages * cv).roundToDouble()
        : enteredPackages.round() * cv;
    final normalizedPackages = measurement > 0 ? measurement / cv : 0;
    _setText(
      _piecesController,
      normalizedPackages <= 0
          ? ''
          : _formatNumber(normalizedPackages, fractionDigits: 3),
    );
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

  Widget _buildFixedActions(BuildContext context, {required bool canConfirm}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: const Color(0xFF475569),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Отмена'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: canConfirm
                  ? () {
                      _runSyncNow();
                      final finalQuantity =
                          _parseValue(_measurementController.text) ?? 0;
                      if (finalQuantity <= 0) return;
                      Navigator.of(context).pop(finalQuantity);
                    }
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFF22B982),
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Добавить в чек'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final cv = product.conversionValue ?? 0;
    final measurementValue = _parseValue(_measurementController.text) ?? 0;
    final packagesValue = _parseValue(_piecesController.text) ?? 0;
    final hasRequiredDiscount = product.discountType == 'fixed' &&
        product.priceAfterDiscount > 0 &&
        product.priceAfterDiscount < product.sellingPrice;
    final unitPrice =
        hasRequiredDiscount ? product.priceAfterDiscount : product.sellingPrice;
    final totalAmount = measurementValue * unitPrice;
    final canConfirm = measurementValue > 0;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    88 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F8F2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              size: 24,
                              color: Color(0xFF15966A),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Количество товара',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  product.name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 10),
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
                            tooltip: 'Закрыть',
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _LinkedInputCard(
                              label: product.measurementUnit,
                              controller: _measurementController,
                              focusNode: _measurementFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^[0-9]*[.,]?[0-9]*$'),
                                ),
                              ],
                              selected:
                                  _activeTarget == _InputTarget.measurement,
                              hintText: '0',
                              onChanged: _onFieldChanged,
                              onTap: () {
                                _measurementFocusNode.requestFocus();
                                _activateTarget(
                                  _InputTarget.measurement,
                                  selectAll: true,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _LinkedInputCard(
                              label: 'Количество, ${product.conversionUnit}',
                              controller: _piecesController,
                              focusNode: _piecesFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  product.allowsPartialPackages
                                      ? RegExp(r'^[0-9]*[.,]?[0-9]*$')
                                      : RegExp(r'^[0-9]*$'),
                                ),
                              ],
                              selected: _activeTarget == _InputTarget.pieces,
                              hintText: '0',
                              onChanged: _onFieldChanged,
                              onTap: () {
                                _piecesFocusNode.requestFocus();
                                _activateTarget(
                                  _InputTarget.pieces,
                                  selectAll: true,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AmountKeypad(
                        text: _activeTarget == _InputTarget.measurement
                            ? _measurementController.text
                            : _piecesController.text,
                        allowDecimal:
                            _activeTarget == _InputTarget.measurement ||
                                product.allowsPartialPackages,
                        showQuickRows: false,
                        onChanged: _onKeypadChanged,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF22B982)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatNumber(measurementValue)} ${product.measurementUnit}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: 20,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _SummaryTile(
                                  title: 'Количество',
                                  value:
                                      '${_formatNumber(packagesValue, fractionDigits: 3)} ${product.conversionUnit}',
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
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildFixedActions(context, canConfirm: canConfirm),
                ),
              ],
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF22B982) : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF22B982).withValues(alpha: 0.10),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? const Color(0xFF15966A)
                        : const Color(0xFF475569),
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF15966A)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475569),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          const SizedBox(height: 2),
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
