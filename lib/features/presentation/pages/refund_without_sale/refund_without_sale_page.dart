import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/product_response.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:leemon_app/features/presentation/widgets/keypad_widget.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

class RefundWithoutSalePage extends StatefulWidget {
  const RefundWithoutSalePage({super.key});

  @override
  State<RefundWithoutSalePage> createState() => _RefundWithoutSalePageState();
}

class _RefundWithoutSalePageState extends State<RefundWithoutSalePage> {
  static const _draftKey = 'refund_without_sale_draft_v1';

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _keyboardFocus = FocusNode();
  final _sync = sl<PosSyncService>();
  final _lines = <_RefundLine>[];
  final _productsScroll = ScrollController();

  OverlayEntry? _keyboardEntry;
  Timer? _typingDebounce;
  Timer? _scanDebounce;
  Timer? _hardwareScanResetTimer;
  DateTime? _lastHardwareDigitAt;
  String? _pendingHardwareDigit;
  bool _hardwareScanMode = false;

  List<ProductModel> _products = const [];
  List<ProductModel> _results = const [];
  List<LocalAccount> _accounts = const [];
  bool _loading = true;
  bool _submitting = false;
  String _paymentMethod = 'cash';
  String? _selectedBankAccountId;
  String? _error;
  bool _accessDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocus.addListener(_keepSearchFocused);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    unawaited(_loadProducts());
    unawaited(_loadAccounts());
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _scanDebounce?.cancel();
    _hardwareScanResetTimer?.cancel();
    _keyboardEntry?.remove();
    _searchFocus.removeListener(_keepSearchFocused);
    _productsScroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _keepSearchFocused() {
    if (_accessDialogOpen) return;
    if (_searchFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _accessDialogOpen || _searchFocus.hasFocus) return;
      _searchFocus.requestFocus();
    });
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _sync.loadProducts();
      if (!mounted) return;
      final draftLines = await _loadDraftLines(products);
      setState(() {
        _products = products
            .where((product) => (product.id ?? '').trim().isNotEmpty)
            .toList(growable: false);
        _results = _products.take(60).toList(growable: false);
        _lines
          ..clear()
          ..addAll(draftLines);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить товары: $e';
      });
    }
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _sync.loadAccounts();
      if (!mounted) return;
      final visibleAccounts =
          accounts.where((account) => account.visibleToPos).toList();
      final bankAccounts =
          visibleAccounts.where((account) => account.normalizedType == 'bank');
      setState(() {
        _accounts = visibleAccounts;
        _selectedBankAccountId ??=
            bankAccounts.isEmpty ? null : bankAccounts.first.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить счета: $e');
    }
  }

  LocalAccount? get _cashAccount {
    return _accounts.cast<LocalAccount?>().firstWhere(
          (account) => account?.isCash ?? false,
          orElse: () => null,
        );
  }

  List<LocalAccount> get _bankAccounts {
    return _accounts
        .where((account) => account.normalizedType == 'bank')
        .toList(growable: false);
  }

  LocalAccount? get _selectedBankAccount {
    final selectedId = (_selectedBankAccountId ?? '').trim();
    if (selectedId.isEmpty) return null;
    return _bankAccounts.cast<LocalAccount?>().firstWhere(
          (account) => account?.id == selectedId,
          orElse: () => null,
        );
  }

  Future<List<_RefundLine>> _loadDraftLines(List<ProductModel> products) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final productsById = {
        for (final product in products)
          if ((product.id ?? '').trim().isNotEmpty)
            (product.id ?? '').trim(): product,
      };
      final lines = <_RefundLine>[];
      for (final item in decoded.whereType<Map>()) {
        final productId = (item['product_id'] ?? '').toString().trim();
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final product = productsById[productId];
        if (product == null || quantity <= 0) continue;
        lines.add(_RefundLine(product: product)..quantity = quantity);
      }
      return lines;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (_lines.isEmpty) {
      await prefs.remove(_draftKey);
      return;
    }
    final payload = _lines
        .map(
          (line) => {
            'product_id': line.productId,
            'quantity': line.quantity,
          },
        )
        .toList(growable: false);
    await prefs.setString(_draftKey, jsonEncode(payload));
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  void _onSearchChanged() {
    final raw = _searchCtrl.text;
    if (raw.contains('\n') || raw.contains('\r')) {
      final cleaned = raw.replaceAll(RegExp(r'[\r\n]+'), '');
      _searchCtrl.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
      _applySearch(autoAddBarcode: true);
      return;
    }

    final q = raw.trim();
    if (q.isEmpty) {
      _typingDebounce?.cancel();
      _scanDebounce?.cancel();
      setState(() => _results = _products.take(60).toList(growable: false));
      return;
    }

    if (RegExp(r'^\d{8,}$').hasMatch(q)) {
      _typingDebounce?.cancel();
      _scanDebounce?.cancel();
      _scanDebounce = Timer(const Duration(milliseconds: 80),
          () => _applySearch(autoAddBarcode: true));
      return;
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 180), _applySearch);
  }

  void _applySearch({bool autoAddBarcode = false}) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = _products.take(60).toList(growable: false));
      return;
    }

    bool matches(ProductModel product) {
      final barcode = (product.barcode ?? '').trim().toLowerCase();
      final localBarcode = (product.localBarcode ?? '').trim().toLowerCase();
      final sku = (product.sku ?? '').trim().toLowerCase();
      final name = product.name.trim().toLowerCase();
      if (barcode == q || localBarcode == q) return true;
      return barcode.contains(q) ||
          localBarcode.contains(q) ||
          sku.contains(q) ||
          name.contains(q);
    }

    final results = _products.where(matches).take(80).toList(growable: false);
    if (autoAddBarcode) {
      final exact = results.cast<ProductModel?>().firstWhere(
        (product) {
          final barcode = (product?.barcode ?? '').trim().toLowerCase();
          final localBarcode =
              (product?.localBarcode ?? '').trim().toLowerCase();
          return barcode == q || localBarcode == q;
        },
        orElse: () => null,
      );
      if (exact != null) {
        _addProduct(exact);
        _searchCtrl.clear();
        setState(() => _results = _products.take(60).toList(growable: false));
        return;
      }
    }

    setState(() => _results = results);
  }

  String? _digitFromPhysicalKey(PhysicalKeyboardKey key) {
    final digits = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.digit0: '0',
      PhysicalKeyboardKey.digit1: '1',
      PhysicalKeyboardKey.digit2: '2',
      PhysicalKeyboardKey.digit3: '3',
      PhysicalKeyboardKey.digit4: '4',
      PhysicalKeyboardKey.digit5: '5',
      PhysicalKeyboardKey.digit6: '6',
      PhysicalKeyboardKey.digit7: '7',
      PhysicalKeyboardKey.digit8: '8',
      PhysicalKeyboardKey.digit9: '9',
      PhysicalKeyboardKey.numpad0: '0',
      PhysicalKeyboardKey.numpad1: '1',
      PhysicalKeyboardKey.numpad2: '2',
      PhysicalKeyboardKey.numpad3: '3',
      PhysicalKeyboardKey.numpad4: '4',
      PhysicalKeyboardKey.numpad5: '5',
      PhysicalKeyboardKey.numpad6: '6',
      PhysicalKeyboardKey.numpad7: '7',
      PhysicalKeyboardKey.numpad8: '8',
      PhysicalKeyboardKey.numpad9: '9',
    };
    return digits[key];
  }

  void _scheduleHardwareScanReset() {
    _hardwareScanResetTimer?.cancel();
    _hardwareScanResetTimer = Timer(
      const Duration(milliseconds: 180),
      () {
        _lastHardwareDigitAt = null;
        _pendingHardwareDigit = null;
        _hardwareScanMode = false;
      },
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final digit = _digitFromPhysicalKey(event.physicalKey);
    if (digit != null && _searchFocus.hasFocus && !_accessDialogOpen) {
      final now = DateTime.now();
      final last = _lastHardwareDigitAt;
      final rapid = last != null &&
          now.difference(last) <= const Duration(milliseconds: 45);

      if (_hardwareScanMode) {
        _lastHardwareDigitAt = now;
        _scheduleHardwareScanReset();
        _insertSearchText(digit);
        return KeyEventResult.handled;
      }

      if (rapid && _pendingHardwareDigit != null) {
        _hardwareScanMode = true;
        _lastHardwareDigitAt = now;
        _replaceSearchText('${_pendingHardwareDigit!}$digit');
        _pendingHardwareDigit = null;
        _scheduleHardwareScanReset();
        return KeyEventResult.handled;
      }

      _pendingHardwareDigit = digit;
      _lastHardwareDigitAt = now;
      _scheduleHardwareScanReset();
      return KeyEventResult.ignored;
    }

    if (event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter) {
      if (_accessDialogOpen) return KeyEventResult.ignored;
      _hardwareScanMode = false;
      _pendingHardwareDigit = null;
      _applySearch(autoAddBarcode: true);
      return KeyEventResult.handled;
    }

    _pendingHardwareDigit = null;
    _lastHardwareDigitAt = null;
    return KeyEventResult.ignored;
  }

  void _insertSearchText(String text) {
    final value = _searchCtrl.value;
    final start =
        value.selection.start < 0 ? value.text.length : value.selection.start;
    final end =
        value.selection.end < 0 ? value.text.length : value.selection.end;
    final next = value.text.replaceRange(start, end, text);
    _searchCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  void _replaceSearchText(String text) {
    _searchCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _showKeyboard() {
    if (_keyboardEntry != null) return;
    _searchFocus.requestFocus();
    _keyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _searchCtrl,
            onEnter: () => _applySearch(autoAddBarcode: true),
            onClose: _hideKeyboard,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_keyboardEntry!);
  }

  void _hideKeyboard() {
    _keyboardEntry?.remove();
    _keyboardEntry = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _addProduct(ProductModel product) {
    final id = (product.id ?? '').trim();
    if (id.isEmpty) return;
    final index = _lines.indexWhere((line) => line.productId == id);
    setState(() {
      if (index >= 0) {
        _lines[index].quantity += 1;
      } else {
        _lines.add(_RefundLine(product: product));
      }
      _error = null;
    });
    unawaited(_saveDraft());
    _searchFocus.requestFocus();
  }

  void _removeProduct(ProductModel product) {
    final id = (product.id ?? '').trim();
    if (id.isEmpty) return;
    setState(() {
      _lines.removeWhere((line) => line.productId == id);
      _error = null;
    });
    unawaited(_saveDraft());
    _searchFocus.requestFocus();
  }

  void _changeQty(int index, int delta) {
    if (index < 0 || index >= _lines.length) return;
    setState(() {
      final next = _lines[index].quantity + delta;
      if (next <= 0) {
        _lines.removeAt(index);
      } else {
        _lines[index].quantity = next;
      }
    });
    unawaited(_saveDraft());
  }

  void _setQty(int index, int quantity) {
    if (index < 0 || index >= _lines.length) return;
    setState(() {
      if (quantity <= 0) {
        _lines.removeAt(index);
      } else {
        _lines[index].quantity = quantity;
      }
    });
    unawaited(_saveDraft());
    _searchFocus.requestFocus();
  }

  Future<bool> _confirmClose() async {
    if (_lines.isEmpty) return true;
    final action = await showDialog<_RefundExitAction>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _RefundExitDialog(),
    );
    if (action == _RefundExitAction.clear) {
      setState(() => _lines.clear());
      await _clearDraft();
      return true;
    }
    return action == _RefundExitAction.keep;
  }

  Future<void> _closePage() async {
    final ok = await _confirmClose();
    if (!mounted || !ok) return;
    context.go('/pos');
  }

  int get _totalAmount =>
      _lines.fold<int>(0, (sum, line) => sum + line.total.round());

  void _logRefund(String message) {
    debugPrint('[RefundWithoutSale] $message');
  }

  Future<String?> _requestReturnAccessKey() async {
    String? acceptedKey;
    _accessDialogOpen = true;
    _searchFocus.unfocus();
    try {
      final granted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RefundAccessDialog(
          onScanned: (code) async {
            final key = code.trim();
            if (key.isEmpty) return false;
            _logRefund('checking return access key');
            final ok = await _sync.checkReturnAccessKey(key);
            _logRefund('return access key check: ${ok ? 'ok' : 'failed'}');
            if (ok) acceptedKey = key;
            return ok;
          },
        ),
      );
      return granted == true ? acceptedKey : null;
    } finally {
      _accessDialogOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    _logRefund('submit pressed');
    final auth = context.read<AuthTokenProvider>();
    if (!auth.allowRefundsWithoutSale) {
      _logRefund('blocked: allowRefundsWithoutSale=false');
      setState(() => _error = 'Возврат без чека запрещён для магазина');
      return;
    }
    if (_lines.isEmpty) {
      _logRefund('blocked: no items');
      setState(() => _error = 'Добавьте товар для возврата');
      return;
    }

    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final posId = auth.posId?.trim() ?? '';
    final storeId = auth.storeId?.trim() ?? '';
    final posSessionId = auth.shiftId?.trim() ?? '';
    if (key.isEmpty || deviceId.isEmpty || posId.isEmpty || storeId.isEmpty) {
      _logRefund(
        'blocked: missing context key=${key.isNotEmpty}, device=${deviceId.isNotEmpty}, pos=${posId.isNotEmpty}, store=${storeId.isNotEmpty}',
      );
      setState(() => _error = 'Не найден контекст POS. Выполните вход заново.');
      return;
    }
    if (posSessionId.isEmpty) {
      _logRefund('blocked: shift is not open');
      setState(() => _error = 'Смена не открыта');
      return;
    }

    final account =
        _paymentMethod == 'card' ? _selectedBankAccount : _cashAccount;
    if ((account?.id.trim().isEmpty ?? true)) {
      _logRefund('blocked: account not selected for method=$_paymentMethod');
      setState(() {
        _error = _paymentMethod == 'card'
            ? 'Выберите банковский счет для безналичного возврата.'
            : 'Не найден счет наличных. Обновите синхронизацию POS.';
      });
      return;
    }

    final returnAccessKey = await _requestReturnAccessKey();
    if ((returnAccessKey ?? '').trim().isEmpty) {
      _logRefund('blocked: return access key not provided');
      setState(() => _error = 'Введите ключ доступа для возврата');
      return;
    }

    final total = _totalAmount;
    final paymentId = 'refund_no_sale_${DateTime.now().microsecondsSinceEpoch}';
    final items = _lines
        .map(
          (line) => {
            'product_id': line.productId,
            'quantity': line.quantity,
            'price': line.price,
          },
        )
        .toList(growable: false);
    final payments = [
      {
        'account_id': account!.id,
        'amount': total,
        'client_payment_id': '$paymentId-$_paymentMethod',
      },
    ];

    _logRefund(
      'creating refund: method=$_paymentMethod account=${account.id} total=$total items=${jsonEncode(items)} payments=${jsonEncode(payments)}',
    );

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _sync.createRefund(
        key: key,
        deviceId: deviceId,
        posSessionId: posSessionId,
        posId: posId,
        storeId: storeId,
        accountId: account.id,
        saleId: '',
        clientSaleId: null,
        totalAmount: total,
        paymentMethod: _paymentMethod,
        payments: payments,
        date: DateTime.now(),
        items: items,
        returnAccessKey: returnAccessKey,
      );
      _logRefund(
        'createRefund result=${result.result} error=${result.errorMessage ?? ''}',
      );
      if (!mounted) return;
      if (result.result == QueueSendResult.manual) {
        setState(() {
          _submitting = false;
          _error = result.errorMessage ?? 'Возврат требует ручной обработки';
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.result == QueueSendResult.sent
                ? 'Возврат отправлен'
                : 'Возврат добавлен в очередь',
          ),
        ),
      );
      await _clearDraft();
      _logRefund('refund completed and draft cleared');
      if (!mounted) return;
      context.go('/pos');
    } catch (e) {
      _logRefund('createRefund exception: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Не удалось создать возврат: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthTokenProvider>();
    final disabled = !auth.allowRefundsWithoutSale;
    final addedProductIds = _lines.map((line) => line.productId).toSet();

    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(_searchFocus, event),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _closePage,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text('Закрыть'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF111827),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: disabled
                    ? _DisabledRefundView(onBack: () => context.go('/pos'))
                    : Row(
                        children: [
                          Expanded(
                            flex: 12,
                            child: _ProductsPanel(
                              loading: _loading,
                              error: _error,
                              searchCtrl: _searchCtrl,
                              searchFocus: _searchFocus,
                              products: _results,
                              addedProductIds: addedProductIds,
                              scrollController: _productsScroll,
                              onAdd: _addProduct,
                              onRemove: _removeProduct,
                              onOpenKeyboard: _showKeyboard,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 9,
                            child: _RefundCartPanel(
                              lines: _lines,
                              totalAmount: _totalAmount,
                              paymentMethod: _paymentMethod,
                              bankAccounts: _bankAccounts,
                              selectedBankAccountId: _selectedBankAccountId,
                              submitting: _submitting,
                              error: _error,
                              onPaymentMethodChanged: (method) => setState(() {
                                _paymentMethod = method;
                                if (method == 'card' &&
                                    (_selectedBankAccountId ?? '').isEmpty &&
                                    _bankAccounts.isNotEmpty) {
                                  _selectedBankAccountId =
                                      _bankAccounts.first.id;
                                }
                              }),
                              onBankAccountChanged: (id) => setState(
                                () => _selectedBankAccountId = id,
                              ),
                              onChangeQty: _changeQty,
                              onSetQty: _setQty,
                              onSubmit: _submit,
                              onBack: _closePage,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundLine {
  _RefundLine({required this.product});

  final ProductModel product;
  int quantity = 1;

  String get productId => (product.id ?? '').trim();
  num get price => product.effectivePrice.round();
  num get total => price * quantity;
}

enum _RefundExitAction { keep, clear }

class _RefundExitDialog extends StatelessWidget {
  const _RefundExitDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 26,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Закрыть возврат?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'В возврат добавлены товары. Можно оставить их на экране или очистить и выйти.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_RefundExitAction.keep),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          foregroundColor: const Color(0xFF374151),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Сохранить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_RefundExitAction.clear),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: const Color(0xFFD45F4F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Очистить'),
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

class _DisabledRefundView extends StatelessWidget {
  const _DisabledRefundView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Возврат без чека запрещён',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'Для этого магазина нужно выбрать чек в истории продаж и сделать возврат по продаже.',
              style: TextStyle(fontSize: 16, color: Color(0xFF4B5563)),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: onBack,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: const Color(0xFFF9B32C),
                foregroundColor: Colors.black,
              ),
              child: const Text('Вернуться'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductsPanel extends StatelessWidget {
  const _ProductsPanel({
    required this.loading,
    required this.error,
    required this.searchCtrl,
    required this.searchFocus,
    required this.products,
    required this.addedProductIds,
    required this.scrollController,
    required this.onAdd,
    required this.onRemove,
    required this.onOpenKeyboard,
  });

  final bool loading;
  final String? error;
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final List<ProductModel> products;
  final Set<String> addedProductIds;
  final ScrollController scrollController;
  final ValueChanged<ProductModel> onAdd;
  final ValueChanged<ProductModel> onRemove;
  final VoidCallback onOpenKeyboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                height: 58,
                child: TextField(
                  controller: searchCtrl,
                  focusNode: searchFocus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Поиск товара или штрихкод',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 58,
              width: 58,
              child: FilledButton(
                onPressed: onOpenKeyboard,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF111827),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Icon(Icons.keyboard_alt_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? Center(
                        child: Text(
                          (error ?? '').trim().isNotEmpty
                              ? error!
                              : 'Товары не найдены',
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final productId = (product.id ?? '').trim();
                          final added = addedProductIds.contains(productId);
                          return _ProductResultTile(
                            product: product,
                            added: added,
                            onTap: () =>
                                added ? onRemove(product) : onAdd(product),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

class _ProductResultTile extends StatelessWidget {
  const _ProductResultTile({
    required this.product,
    required this.added,
    required this.onTap,
  });

  final ProductModel product;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              product.measurementUnit,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(width: 18),
            Text(
              money(product.effectivePrice),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              added ? Icons.remove_circle_rounded : Icons.add_circle_rounded,
              color: added ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefundCartPanel extends StatelessWidget {
  const _RefundCartPanel({
    required this.lines,
    required this.totalAmount,
    required this.paymentMethod,
    required this.bankAccounts,
    required this.selectedBankAccountId,
    required this.submitting,
    required this.error,
    required this.onPaymentMethodChanged,
    required this.onBankAccountChanged,
    required this.onChangeQty,
    required this.onSetQty,
    required this.onSubmit,
    required this.onBack,
  });

  final List<_RefundLine> lines;
  final int totalAmount;
  final String paymentMethod;
  final List<LocalAccount> bankAccounts;
  final String? selectedBankAccountId;
  final bool submitting;
  final String? error;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<String?> onBankAccountChanged;
  final void Function(int index, int delta) onChangeQty;
  final void Function(int index, int quantity) onSetQty;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Возврат товара',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('Добавьте товары для возврата'))
                : ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      return _RefundLineTile(
                        line: line,
                        onMinus: () => onChangeQty(index, -1),
                        onPlus: () => onChangeQty(index, 1),
                        onSetQty: (quantity) => onSetQty(index, quantity),
                      );
                    },
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: _PaymentChoice(
                  label: 'Наличные',
                  selected: paymentMethod == 'cash',
                  onTap: () => onPaymentMethodChanged('cash'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PaymentChoice(
                  label: 'Карта',
                  selected: paymentMethod == 'card',
                  onTap: () => onPaymentMethodChanged('card'),
                ),
              ),
            ],
          ),
          if (paymentMethod == 'card') ...[
            const SizedBox(height: 10),
            _BankAccountSelect(
              accounts: bankAccounts,
              selectedAccountId: selectedBankAccountId,
              onChanged: onBankAccountChanged,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Сумма возврата',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  money(totalAmount),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if ((error ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: submitting || lines.isEmpty ? null : onSubmit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: const Color(0xFFD45F4F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              submitting ? 'Создаём возврат...' : 'Сделать возврат',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankAccountSelect extends StatelessWidget {
  const _BankAccountSelect({
    required this.accounts,
    required this.selectedAccountId,
    required this.onChanged,
  });

  final List<LocalAccount> accounts;
  final String? selectedAccountId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasAccounts = accounts.isNotEmpty;
    final selectedId = (selectedAccountId ?? '').trim();
    final value =
        accounts.any((account) => account.id == selectedId) ? selectedId : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Банковский счет',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          if (!hasAccounts)
            const Text(
              'Нет доступных счетов типа bank',
              style: TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w800,
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(14),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF456B5A),
                    width: 1.4,
                  ),
                ),
              ),
              hint: const Text('Выберите счет'),
              items: accounts
                  .map(
                    (account) => DropdownMenuItem<String>(
                      value: account.id,
                      child: Text(
                        account.name.trim().isEmpty
                            ? 'Банк ${account.id}'
                            : account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _RefundLineTile extends StatelessWidget {
  const _RefundLineTile({
    required this.line,
    required this.onMinus,
    required this.onPlus,
    required this.onSetQty,
  });

  final _RefundLine line;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<int> onSetQty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text('${money(line.price)} x ${line.quantity}'),
              ],
            ),
          ),
          _QtyStepButton(label: '-', onTap: onMinus),
          InkWell(
            onTap: () async {
              final value = await _showRefundQtyDialog(
                context,
                productName: line.product.name,
                initialQty: line.quantity,
              );
              if (value == null) return;
              onSetQty(value);
            },
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                '${line.quantity}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          _QtyStepButton(label: '+', onTap: onPlus),
        ],
      ),
    );
  }
}

Future<int?> _showRefundQtyDialog(
  BuildContext context, {
  required String productName,
  required int initialQty,
}) async {
  final focusNode = FocusNode();
  var text = initialQty.toString();
  var didSelectInitialText = false;

  int parseValue() => int.tryParse(text.trim()) ?? -1;

  void inputToken(StateSetter setState, String token) {
    if (token == '.') return;
    setState(() {
      if (didSelectInitialText && token != '⌫') {
        text = '';
        didSelectInitialText = false;
      }
      if (token == '⌫') {
        if (text.isNotEmpty) text = text.substring(0, text.length - 1);
        didSelectInitialText = false;
        return;
      }
      if (!RegExp(r'^[0-9]$').hasMatch(token)) return;
      final next = '$text$token'.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      text = next.isEmpty ? '0' : next;
    });
  }

  void handleKey(
    KeyEvent event,
    StateSetter setState,
    BuildContext dialogContext,
  ) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final value = parseValue();
      if (value >= 0) Navigator.of(dialogContext).pop(value);
      return;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(dialogContext).pop();
      return;
    }
    if (key == LogicalKeyboardKey.backspace) {
      inputToken(setState, '⌫');
      return;
    }
    final character = event.character ?? key.keyLabel;
    if (RegExp(r'^[0-9]$').hasMatch(character)) {
      inputToken(setState, character);
    }
  }

  final result = await showDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          if (!didSelectInitialText) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!focusNode.hasFocus) focusNode.requestFocus();
              didSelectInitialText = true;
              if (ctx.mounted) setState(() {});
            });
          }

          final value = parseValue();
          final canSave = value >= 0;
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: KeyboardListener(
              focusNode: focusNode,
              autofocus: true,
              onKeyEvent: (event) => handleKey(event, setState, dialogContext),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Изменить количество',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F7F8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFF9B32C),
                            width: 1.2,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: didSelectInitialText
                                  ? const Color(0xFFF9B32C)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: Text(
                                text.isEmpty ? '0' : text,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: didSelectInitialText
                                      ? Colors.black
                                      : const Color(0xFF111827),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '0 удалит товар из возврата',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Keypad(
                        keyHeight: 54,
                        fontSize: 20,
                        onTap: (token) {
                          inputToken(setState, token);
                          focusNode.requestFocus();
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                fixedSize: const Size.fromHeight(56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Отмена',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: canSave
                                  ? () => Navigator.of(dialogContext).pop(value)
                                  : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                fixedSize: const Size.fromHeight(56),
                                backgroundColor: const Color(0xFF456B5A),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Готово',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
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
        },
      );
    },
  );

  focusNode.dispose();
  return result;
}

class _QtyStepButton extends StatelessWidget {
  const _QtyStepButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFCDCDCD),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _PaymentChoice extends StatelessWidget {
  const _PaymentChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF9B32C) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFF9B32C) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: selected ? Colors.black : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
