import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/product_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/amount_keypad.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'package:provider/provider.dart';

Future<ProductModel?> showProductCreateDialog(
  BuildContext context, {
  String initialBarcode = '',
  bool scannedProductNotFound = false,
}) async {
  final auth = context.read<AuthTokenProvider>();
  final activeUserId = auth.activeUserId?.trim() ?? '';
  final isDirector = auth.users.any(
    (user) =>
        user.id == activeUserId &&
        user.roles.any((role) => role.toLowerCase() == 'director'),
  );

  if (scannedProductNotFound) {
    final shouldCreate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProductNotFoundDialog(),
    );
    if (shouldCreate != true || !context.mounted) return null;
  }

  return showDialog<ProductModel>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductCreateDialog(
      posKey: auth.posKey?.trim() ?? '',
      userId: activeUserId,
      deviceId: auth.deviceId?.trim() ?? '',
      isDirector: isDirector,
      initialBarcode: initialBarcode.trim(),
      scannedProductNotFound: false,
    ),
  );
}

class _ProductNotFoundDialog extends StatelessWidget {
  const _ProductNotFoundDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF7ED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    size: 34,
                    color: Color(0xFFEA580C),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Товар не найден',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'По этому штрихкоду нет локального товара. Создать новый?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.4,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text('Закрыть'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFF179D72),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Создать',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCreateDialog extends StatefulWidget {
  const _ProductCreateDialog({
    required this.posKey,
    required this.userId,
    required this.deviceId,
    required this.isDirector,
    required this.initialBarcode,
    required this.scannedProductNotFound,
  });

  final String posKey;
  final String userId;
  final String deviceId;
  final bool isDirector;
  final String initialBarcode;
  final bool scannedProductNotFound;

  @override
  State<_ProductCreateDialog> createState() => _ProductCreateDialogState();
}

class _ProductCreateDialogState extends State<_ProductCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  final _priceController = TextEditingController();
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();
  final _priceFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();
  OverlayEntry? _nameKeyboardEntry;
  Timer? _barcodeLookupDebounce;
  bool _nameKeyboardOpen = false;
  bool _nameLookupInProgress = false;
  bool _nameLookupCompleted = false;
  String? _foundProductName;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _barcodeController = TextEditingController(text: widget.initialBarcode);
    _barcodeController.addListener(_onBarcodeChanged);
    _nameController.addListener(_limitNameLength);
    if (widget.initialBarcode.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookupProductName();
      });
    }
  }

  @override
  void dispose() {
    _nameKeyboardEntry?.remove();
    _nameKeyboardEntry = null;
    _barcodeLookupDebounce?.cancel();
    _barcodeController.removeListener(_onBarcodeChanged);
    _barcodeController.dispose();
    _priceController.dispose();
    _nameController.removeListener(_limitNameLength);
    _nameController.dispose();
    _priceFocusNode.dispose();
    _nameFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double? _parsedPrice() =>
      double.tryParse(_priceController.text.trim().replaceAll(',', '.'));

  void _onBarcodeChanged() {
    _barcodeLookupDebounce?.cancel();
    final barcode = _barcodeController.text.trim();
    setState(() {
      _nameLookupInProgress = false;
      _nameLookupCompleted = false;
      _foundProductName = null;
      _nameController.clear();
      _error = null;
    });
    if (!RegExp(r'^\d{11,13}$').hasMatch(barcode)) return;
    if (barcode.startsWith('2')) {
      setState(() => _nameLookupCompleted = true);
      _focusNameField();
      return;
    }
    _barcodeLookupDebounce = Timer(
      const Duration(milliseconds: 350),
      _lookupProductName,
    );
  }

  Future<void> _lookupProductName() async {
    final barcode = _barcodeController.text.trim();
    if (!RegExp(r'^\d{11,13}$').hasMatch(barcode)) return;
    if (barcode.startsWith('2')) {
      setState(() {
        _nameLookupInProgress = false;
        _nameLookupCompleted = true;
        _foundProductName = null;
      });
      _focusNameField();
      return;
    }
    setState(() {
      _nameLookupInProgress = true;
      _nameLookupCompleted = false;
      _foundProductName = null;
    });
    try {
      final name = await sl<ProductRemoteDataSource>().findProductNameByBarcode(
        key: widget.posKey,
        barcode: barcode,
        deviceId: widget.deviceId,
      );
      if (!mounted || barcode != _barcodeController.text.trim()) return;
      setState(() {
        _nameLookupInProgress = false;
        _nameLookupCompleted = true;
        _foundProductName = name;
        if (name != null) _nameController.text = name;
      });
      if (name == null) _focusNameField();
    } catch (_) {
      if (!mounted || barcode != _barcodeController.text.trim()) return;
      setState(() {
        _nameLookupInProgress = false;
        _nameLookupCompleted = true;
        _foundProductName = null;
      });
      _focusNameField();
    }
  }

  void _focusNameField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loading) _nameFocusNode.requestFocus();
    });
  }

  void _limitNameLength() {
    final text = _nameController.text;
    if (text.length <= 255) return;
    final limited = text.substring(0, 255);
    _nameController.value = TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length),
    );
  }

  void _showNameKeyboard() {
    if (_loading) return;
    _nameFocusNode.requestFocus();
    if (_nameKeyboardEntry != null) return;

    setState(() => _nameKeyboardOpen = true);

    _nameKeyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _nameController,
            onEnter: _hideNameKeyboard,
            onClose: _hideNameKeyboard,
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_nameKeyboardEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _editFoundName() {
    if (_loading) return;
    _nameFocusNode.requestFocus();
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );
  }

  void _hideNameKeyboard() {
    _nameKeyboardEntry?.remove();
    _nameKeyboardEntry = null;
    if (mounted && _nameKeyboardOpen) {
      setState(() => _nameKeyboardOpen = false);
    }
  }

  void _showPriceKeyboard() {
    if (_loading) return;
    _hideNameKeyboard();
    _priceFocusNode.requestFocus();
  }

  void _setPriceFromKeypad(String next) {
    if (!RegExp(r'^\d*(?:\.\d{0,2})?$').hasMatch(next)) return;
    _priceController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _error = null);
  }

  void _closeDialog() {
    _hideNameKeyboard();
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_loading ||
        _nameLookupInProgress ||
        !_formKey.currentState!.validate()) {
      return;
    }
    if (widget.posKey.isEmpty ||
        widget.userId.isEmpty ||
        widget.deviceId.isEmpty) {
      setState(() {
        _error = 'Не найдены данные POS, пользователя или устройства.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    _hideNameKeyboard();
    try {
      final product = widget.isDirector
          ? await _createProduct()
          : await _createWithManagerKey();
      if (product == null) return;
      if (!mounted) return;
      await sl<PosSyncService>().cacheServerProduct(product);
      if (!mounted) return;
      Navigator.of(context).pop(product);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ProductModel> _createProduct({String? managerAccessKey}) {
    return sl<ProductRemoteDataSource>().createProduct(
      key: widget.posKey,
      barcode: _barcodeController.text,
      sellingPrice: _parsedPrice()!,
      userId: widget.userId,
      deviceId: widget.deviceId,
      name: _nameController.text,
      measurementUnit: MeasurementUnit.pieces,
      managerAccessKey: managerAccessKey,
    );
  }

  Future<ProductModel?> _createWithManagerKey() async {
    ProductModel? createdProduct;
    Object? retryError;

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RefundAccessDialog(
        title: 'Доступ к созданию товара',
        scanTitle: 'Сканируй штрих-код доступа менеджера',
        onScanned: (barcode) async {
          final accessKey = barcode.trim();
          if (accessKey.isEmpty) return false;
          try {
            createdProduct = await _createProduct(
              managerAccessKey: accessKey,
            );
            return true;
          } on DioException catch (error) {
            if (error.response?.statusCode == 401) return false;
            retryError = error;
            return true;
          } catch (error) {
            retryError = error;
            return true;
          }
        },
      ),
    );

    if (retryError != null) throw retryError!;
    return granted == true ? createdProduct : null;
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final errors = data['errors'];
        if (errors is Map) {
          for (final value in errors.values) {
            if (value is List && value.isNotEmpty) {
              return value.first.toString();
            }
            if (value != null && value.toString().trim().isNotEmpty) {
              return value.toString();
            }
          }
        }
        final message = data['message'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
      switch (error.response?.statusCode) {
        case 401:
          return 'Неверный, просроченный или чужой ключ менеджера.';
        case 403:
          return 'Подписка организации неактивна.';
        case 422:
          return 'Проверьте штрихкод и цену товара.';
        case 500:
          return 'Сервер не смог создать товар. Попробуйте ещё раз.';
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              26,
              24,
              26,
              _nameKeyboardOpen ? 420 : 22,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7F1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.add_box_outlined,
                          color: Color(0xFF179D72),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.scannedProductNotFound
                                  ? 'Товар не найден'
                                  : 'Создание товара',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.scannedProductNotFound
                                  ? 'Создайте товар по отсканированному штрихкоду'
                                  : 'Заполните штрихкод и розничную цену',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loading ? null : _closeDialog,
                        icon: const Icon(Icons.close),
                        tooltip: 'Закрыть',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _barcodeController,
                    autofocus: false,
                    enabled: !_loading,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(13),
                    ],
                    decoration: _decoration(
                      label: 'Штрихкод',
                      hint: '11–13 цифр',
                      icon: Icons.qr_code_2,
                    ),
                    validator: (value) {
                      final barcode = value?.trim() ?? '';
                      if (!RegExp(r'^\d{11,13}$').hasMatch(barcode)) {
                        return 'Введите штрихкод длиной от 11 до 13 цифр';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    focusNode: _priceFocusNode,
                    enabled: !_loading,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      LengthLimitingTextInputFormatter(12),
                    ],
                    onTap: _showPriceKeyboard,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: _decoration(
                      label: 'Цена продажи',
                      hint: '0,00',
                      icon: Icons.payments_outlined,
                      suffix: '₸',
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      final price = _parsedPrice();
                      if (raw.isEmpty || price == null) return 'Введите цену';
                      if (price < 0) return 'Цена не может быть отрицательной';
                      if (!RegExp(r'^\d+(?:[\.,]\d{1,2})?$').hasMatch(raw)) {
                        return 'Допустимо не более двух знаков после запятой';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AmountKeypad(
                      text: _priceController.text,
                      onChanged: _setPriceFromKeypad,
                      showQuickRows: false,
                      allowDecimal: true,
                      maxLength: 12,
                      keyHeight: 48,
                      keySpacing: 7,
                      keyColor: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_nameLookupInProgress)
                    const ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                      leading: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      title: Text('Ищем название по штрихкоду…'),
                    )
                  else if (_nameLookupCompleted)
                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      enabled: !_loading,
                      maxLength: 255,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _decoration(
                        label: 'Название товара',
                        hint: _foundProductName == null
                            ? 'Название не найдено — введите своё'
                            : 'Название товара',
                        icon: Icons.inventory_2_outlined,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_foundProductName != null)
                              IconButton(
                                onPressed: _loading ? null : _editFoundName,
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Изменить название',
                              ),
                            IconButton(
                              onPressed: _loading ? null : _showNameKeyboard,
                              icon: const Icon(Icons.keyboard_alt_outlined),
                              tooltip: 'Открыть клавиатуру',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFBE123C),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFF9F1239),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading ? null : _closeDialog,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _loading || _nameLookupInProgress
                              ? null
                              : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: const Color(0xFF179D72),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: Text(
                            _loading
                                ? 'Создание…'
                                : widget.isDirector
                                    ? 'Создать товар'
                                    : 'Ввести ключ менеджера',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
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

  InputDecoration _decoration({
    required String label,
    required String hint,
    required IconData icon,
    String? suffix,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixText: suffix,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }
}
