import 'dart:async';
import 'package:dio/dio.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/models/marking_check.dart';
import 'package:leemon_app/features/data/datasources/sale_remote_datesource.dart';

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

class MarkingPackageCoverage {
  const MarkingPackageCoverage({
    required this.quantity,
    required this.packageQuantity,
    required this.packageCount,
    this.alreadyCovered = 0,
  });

  final int quantity;
  final int packageQuantity;
  final int packageCount;
  final int alreadyCovered;

  int get capacity => alreadyCovered + packageQuantity * packageCount;
  int get covered => capacity.clamp(0, quantity);
  int get missing => (quantity - capacity).clamp(0, quantity);
  bool get needsNewPackage => missing > 0;
}

int markingPackageQuantity({
  required double? conversionValue,
  required bool allowsPartialPackages,
}) {
  if (!allowsPartialPackages || conversionValue == null) return 1;
  return conversionValue.round().clamp(1, 1000000000);
}

Future<List<String>?> showMarkingPackageScanDialog(
  BuildContext context, {
  required String productName,
  required int quantity,
  required int packageQuantity,
  required String? gtin,
  required List<String> initialCodes,
  required Set<String> usedCodes,
  int alreadyCovered = 0,
  bool initialCodesAlreadyCounted = false,
  int? requiredCodesCount,
  String? errorMessage,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MarkingPackageScanDialog(
      productName: productName,
      quantity: quantity,
      packageQuantity: packageQuantity,
      gtin: gtin,
      initialCodes: initialCodes,
      usedCodes: usedCodes,
      alreadyCovered: alreadyCovered,
      initialCodesAlreadyCounted: initialCodesAlreadyCounted,
      requiredCodesCount: requiredCodesCount,
      errorMessage: errorMessage,
    ),
  );
}

class _MarkingPackageScanDialog extends StatefulWidget {
  const _MarkingPackageScanDialog({
    required this.productName,
    required this.quantity,
    required this.packageQuantity,
    required this.gtin,
    required this.initialCodes,
    required this.usedCodes,
    required this.alreadyCovered,
    required this.initialCodesAlreadyCounted,
    this.requiredCodesCount,
    this.errorMessage,
  });

  final String productName;
  final int quantity;
  final int packageQuantity;
  final String? gtin;
  final List<String> initialCodes;
  final Set<String> usedCodes;
  final int alreadyCovered;
  final bool initialCodesAlreadyCounted;
  final int? requiredCodesCount;
  final String? errorMessage;

  @override
  State<_MarkingPackageScanDialog> createState() =>
      _MarkingPackageScanDialogState();
}

class _MarkingPackageScanDialogState extends State<_MarkingPackageScanDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final List<String> _codes = List<String>.from(widget.initialCodes);
  late final int _initialCodeCount = widget.initialCodes.length;
  String? _error;

  MarkingPackageCoverage get _coverage => MarkingPackageCoverage(
        quantity: widget.quantity,
        packageQuantity: widget.packageQuantity,
        packageCount: _codes.length -
            (widget.initialCodesAlreadyCounted ? _initialCodeCount : 0),
        alreadyCovered: widget.alreadyCovered,
      );

  @override
  void initState() {
    super.initState();
    _error = widget.errorMessage;
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

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.character != '\x1D' &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      return KeyEventResult.ignored;
    }
    if (event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter) {
      _accept();
      return KeyEventResult.handled;
    }
    final character = MarkingKeyboardInputFormatter.scannerCharacter(event);
    if (character == null) return KeyEventResult.ignored;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _controller.value = TextEditingValue(
        text: value.text.replaceRange(start, end, character),
        selection: TextSelection.collapsed(offset: start + character.length));
    return KeyEventResult.handled;
  }

  void _accept() {
    if (!_needsCodes) return;
    final code = _controller.text;
    if (code.isEmpty) return;
    final duplicate = widget.usedCodes.contains(code) || _codes.contains(code);
    if (duplicate) {
      setState(() => _error = 'Эта коробка уже отсканирована');
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      _codes.add(code);
      _error = null;
      _controller.clear();
    });
    if (widget.requiredCodesCount != null && !_needsCodes) {
      Navigator.of(context).pop(List<String>.from(_codes));
      return;
    }
    _focusNode.requestFocus();
  }

  bool get _needsCodes => widget.requiredCodesCount == null
      ? _coverage.needsNewPackage
      : _codes.length - _initialCodeCount < widget.requiredCodesCount!;

  Widget _valueCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverage = _coverage;
    final remainingCodes = widget.requiredCodesCount == null
        ? (coverage.missing / widget.packageQuantity).ceil()
        : widget.requiredCodesCount! - (_codes.length - _initialCodeCount);
    return AlertDialog(
      backgroundColor: Colors.white,
      scrollable: true,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.qr_code_scanner_rounded,
                color: Color(0xFF15966A), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Маркировка',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(widget.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _valueCard(
                    'Количество', coverage.quantity, const Color(0xFF2563EB)),
                const SizedBox(width: 8),
                _valueCard(
                    'Пробито', coverage.covered, const Color(0xFF15966A)),
                const SizedBox(width: 8),
                _valueCard(
                    'Не хватает', coverage.missing, const Color(0xFFDC2626)),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _needsCodes
                    ? const Color(0xFFFFF3E6)
                    : const Color(0xFFE8F8F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _needsCodes
                    ? remainingCodes > 1
                        ? 'Новых коробок: $remainingCodes • по ${widget.packageQuantity} шт.'
                        : 'Нужна новая коробка • ${widget.packageQuantity} шт.'
                    : 'Готово • коробок: ${_codes.length}',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            if (_needsCodes) ...[
              const SizedBox(height: 14),
              Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  obscureText: true,
                  inputFormatters: const [MarkingKeyboardInputFormatter()],
                  onSubmitted: (_) => _accept(),
                  decoration: InputDecoration(
                    labelText: 'Сканируйте новую коробку',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    suffixIcon: IconButton(
                        onPressed: _accept,
                        tooltip: 'Проверить код',
                        icon: const Icon(Icons.check)),
                    errorText: _error,
                    prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
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
                      borderSide:
                          const BorderSide(color: Color(0xFF15966A), width: 2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: 500,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    textStyle: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFF15966A),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _needsCodes
                        ? value.text.isEmpty
                            ? null
                            : _accept
                        : () => Navigator.of(context)
                            .pop(List<String>.from(_codes)),
                    child: Text(_needsCodes || widget.requiredCodesCount != null
                        ? 'Проверить'
                        : 'Добавить в чек'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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

  {
    final selectedQuantity = await showDialog<double>(
      context: context,
      barrierDismissible: true,
      builder: (_) => partialMarkedPackage
          ? _ConversionProductDialog(product: product)
          : _MarkedQuantityDialog(productName: product.name),
    );
    if (selectedQuantity == null || selectedQuantity <= 0) {
      requestSearchResetAndFocus();
      return false;
    }
    quantity = selectedQuantity.roundToDouble();
  }

  if (!context.mounted) return false;
  final posCubit = context.read<PosCubit>();
  final existingIndex = posCubit.state.items
      .indexWhere((item) => item.product.id == (product.id ?? ''));
  if (existingIndex >= 0) {
    return setCartItemQuantityWithMarking(
      context,
      index: existingIndex,
      quantity: posCubit.state.items[existingIndex].qty + quantity,
      additionalMarkCodes: [
        if ((initialMarkCode ?? '').isNotEmpty) initialMarkCode!,
      ],
    );
  }
  var codes = <String>[
    if ((initialMarkCode ?? '').isNotEmpty) initialMarkCode!,
  ];
  if (codes.toSet().length != codes.length ||
      codes.any((code) =>
          posCubit.state.items.any((item) => item.markCodes.contains(code)))) {
    await showDuplicateMarkCodeDialog(context);
    return false;
  }
  posCubit.addFromProductModel(product, qty: quantity, markCodes: codes);
  await ensureCartMarkingReady(context);
  return true;
}

Future<bool> setCartItemQuantityWithMarking(
  BuildContext context, {
  required int index,
  required double quantity,
  List<String> additionalMarkCodes = const [],
}) async {
  final cubit = context.read<PosCubit>();
  if (index < 0 ||
      index >= cubit.state.items.length ||
      cubit.state.activeTicket.checkout != null) {
    return false;
  }
  final item = cubit.state.items[index];
  if (item.product.requiresMarking && quantity != quantity.roundToDouble()) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Маркированный товар продаётся только поштучно')));
    return false;
  }
  final codes = [...item.markCodes, ...additionalMarkCodes];
  if (codes.toSet().length != codes.length ||
      additionalMarkCodes.any((code) =>
          cubit.state.items.any((item) => item.markCodes.contains(code)))) {
    await showDuplicateMarkCodeDialog(context);
    return false;
  }
  cubit.setMarkCodes(index, codes);
  cubit.setQty(index, quantity);
  await ensureCartMarkingReady(context);
  return true;
}

class _MarkedQuantityDialog extends StatefulWidget {
  const _MarkedQuantityDialog({required this.productName});
  final String productName;
  @override
  State<_MarkedQuantityDialog> createState() => _MarkedQuantityDialogState();
}

class _MarkedQuantityDialogState extends State<_MarkedQuantityDialog> {
  final _quantity = TextEditingController();
  void _submit() {
    final value = int.tryParse(_quantity.text);
    if (value != null && value > 0) Navigator.pop(context, value.toDouble());
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.productName),
        content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration:
                      const InputDecoration(labelText: 'Количество, шт.'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit()),
              const SizedBox(height: 16),
              AmountKeypad(
                  text: _quantity.text,
                  showQuickRows: false,
                  allowDecimal: false,
                  onChanged: (text) => setState(() {
                        _quantity.value = TextEditingValue(
                            text: text,
                            selection:
                                TextSelection.collapsed(offset: text.length));
                      })),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed:
                  (int.tryParse(_quantity.text) ?? 0) > 0 ? _submit : null,
              child: const Text('Продолжить'))
        ],
      );
}

final _markingChecks = Expando<Future<bool>>();

Future<bool> ensureCartMarkingReady(BuildContext context,
    {bool correctingCheckout = false}) {
  final cubit = context.read<PosCubit>();
  final pending = _markingChecks[cubit];
  if (pending != null) return pending;
  final future =
      _checkCartMarking(context, cubit, correctingCheckout: correctingCheckout);
  _markingChecks[cubit] = future;
  return future.whenComplete(() => _markingChecks[cubit] = null);
}

Future<bool> _checkCartMarking(BuildContext context, PosCubit cubit,
    {required bool correctingCheckout}) async {
  final auth = context.read<AuthTokenProvider>();
  final ticketId = cubit.state.activeTicketId;
  final codeErrors = <String, String>{};
  void report(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  while (context.mounted &&
      !cubit.isClosed &&
      cubit.state.activeTicketId == ticketId &&
      cubit.state.items.isNotEmpty) {
    if (cubit.state.activeTicket.checkout != null &&
        !(correctingCheckout &&
            cubit.state.activeTicket.checkout!['needs_marking_check'] ==
                true)) {
      return false;
    }
    final key = auth.posKey ?? '';
    final storeId = auth.storeId ?? '';
    final deviceId = auth.deviceId ?? '';
    cubit.markingScope = '$key/$storeId/$deviceId';
    if (key.isEmpty || storeId.isEmpty || deviceId.isEmpty) {
      report('Не настроены магазин или терминал');
      return false;
    }
    final snapshot = cubit.markingSnapshot;
    cubit.beginMarkingCheck();
    final items = List<CartItem>.from(cubit.state.items);
    MarkingCheckResponse response;
    try {
      response = await sl<SaleRemoteDataSource>().checkMarking(
          key: key,
          storeId: storeId,
          deviceId: deviceId,
          items: items
              .map((item) => <String, dynamic>{
                    'product_id': item.product.id,
                    'quantity': item.qty,
                    'mark_codes': List<String>.from(item.markCodes),
                  })
              .toList());
    } on DioException catch (error) {
      if (!context.mounted || snapshot != cubit.markingSnapshot) return false;
      final body = error.response?.data;
      final errors = body is Map ? body['errors'] : null;
      if (error.response?.statusCode == 422 && errors is Map) {
        var removed = false;
        for (var i = 0; i < items.length; i++) {
          final badIndexes = <int>{};
          String? message;
          for (final entry in errors.entries) {
            final match = RegExp(r'^items\.(\d+)\.mark_codes\.(\d+)$')
                .firstMatch(entry.key.toString());
            if (match != null && int.parse(match[1]!) == i) {
              badIndexes.add(int.parse(match[2]!));
              message = entry.value is List
                  ? (entry.value as List).join(' ')
                  : entry.value.toString();
            }
          }
          if (badIndexes.isNotEmpty) {
            cubit.selectItem(i);
            codeErrors[items[i].product.id] = message ?? 'Неверный код';
            report('${items[i].product.name}: $message');
            cubit.setMarkCodes(
                i,
                [
                  for (var j = 0; j < items[i].markCodes.length; j++)
                    if (!badIndexes.contains(j)) items[i].markCodes[j]
                ],
                correctingCheckoutMarking: correctingCheckout);
            removed = true;
          }
        }
        if (removed) continue;
      }
      report(body is Map
          ? (body['message']?.toString() ?? 'Не удалось проверить маркировку')
          : 'Нет связи. Повторите проверку маркировки');
      return false;
    } catch (_) {
      report('Не удалось проверить маркировку. Повторите проверку');
      return false;
    }
    if (!context.mounted ||
        cubit.isClosed ||
        cubit.state.activeTicketId != ticketId) {
      return false;
    }
    if (storeId != auth.storeId ||
        key != auth.posKey ||
        deviceId != auth.deviceId ||
        snapshot != cubit.markingSnapshot) {
      continue;
    }
    // A partial/malformed response must never authorize payment.
    if (items.any((item) =>
        !response.items.any((result) => result.productId == item.product.id))) {
      report('Сервер проверил не все товары. Повторите проверку');
      return false;
    }
    cubit.applyMarkingCheck(snapshot, response);
    if (response.canPay) return true;
    var changed = false;
    for (final result in response.items) {
      if (result.ready) continue;
      final index = cubit.state.items
          .indexWhere((item) => item.product.id == result.productId);
      if (index < 0) return false;
      cubit.selectItem(index);
      final item = cubit.state.items[index];
      if (result.errorCode == 'EXTRA_MARK_CODE' ||
          result.errorCode == 'MARK_CODE_CONFLICT') {
        if (item.markCodes.isEmpty) {
          report(result.message ?? 'Не удалось проверить код');
          return false;
        }
        // The response identifies the product, not a specific conflicting code.
        // Remove its newly supplied codes, then let the server request the exact deficit.
        cubit.setMarkCodes(index, const [],
            correctingCheckoutMarking: correctingCheckout);
        if (result.errorCode == 'MARK_CODE_CONFLICT') {
          codeErrors[item.product.id] =
              result.message ?? 'Код не подходит. Сканируйте другую коробку';
          report(codeErrors[item.product.id]!);
        }
        changed = true;
        break;
      }
      if (result.scanRequired && result.requiredCodesCount > 0) {
        final codes = await showMarkingPackageScanDialog(context,
            productName: item.product.name,
            quantity: item.qty.round(),
            packageQuantity:
                (result.packageQuantity ?? 1).round().clamp(1, 1000000000),
            gtin: null,
            initialCodes: item.markCodes,
            initialCodesAlreadyCounted: true,
            requiredCodesCount: result.requiredCodesCount,
            errorMessage: codeErrors.remove(item.product.id),
            alreadyCovered: (item.qty - result.missingQuantity)
                .round()
                .clamp(0, item.qty.round()),
            usedCodes: {
              for (var i = 0; i < cubit.state.items.length; i++)
                if (i != index) ...cubit.state.items[i].markCodes
            });
        if (codes == null || !context.mounted) return false;
        if (snapshot != cubit.markingSnapshot) {
          changed = true;
          break;
        }
        cubit.setMarkCodes(index, codes,
            correctingCheckoutMarking: correctingCheckout);
        changed = true;
        break;
      }
      report(result.message ?? 'Маркировка не прошла проверку');
      return false;
    }
    if (!changed) {
      report('Маркировка не прошла проверку');
      return false;
    }
  }
  return false;
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
