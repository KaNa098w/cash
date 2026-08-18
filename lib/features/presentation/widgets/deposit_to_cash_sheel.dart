import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/core/service/fiscal_receipt_service.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/presentation/utils/comment_text_controller.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'package:leemon_app/features/presentation/widgets/payment_panel.dart'
    show FiscalReceiptDialog;

/// type: true = ВЗНОС, false = РАСХОД
Future<bool> showDepositToCashSheet(BuildContext context, bool type) async {
  final res = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'deposit-to-cash',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) {
      return SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: _DepositToCashSheet(type: type),
          ),
        ),
      );
    },
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );

  return res ?? false;
}

class _DepositToCashSheet extends StatefulWidget {
  const _DepositToCashSheet({required this.type});

  final bool type;

  @override
  State<_DepositToCashSheet> createState() => _DepositToCashSheetState();
}

class _DepositToCashSheetState extends State<_DepositToCashSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();
  OverlayEntry? _keyboardEntry;
  String _text = '';
  bool _loading = false;

  bool _loadingTypes = false;
  List<Map<String, dynamic>> _expenseTypes = const [];
  String? _expenseTypeId;
  String? _expenseTypeTitle;

  num? get _amount {
    final v = _text.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }

  bool get _isExpense => !widget.type; // ✅ type=false -> расход

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_handleAmountChanged);
    _noteCtrl.addListener(_capitalizeNote);

    // Если это расход — заранее подгружаем типы расходов
    if (_isExpense) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExpenseTypes());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _amountFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideKeyboard();
    _amountCtrl.removeListener(_handleAmountChanged);
    _noteCtrl.removeListener(_capitalizeNote);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _capitalizeNote() {
    capitalizeFirstLetterInController(_noteCtrl);
  }

  void _ensureNoteSelection() {
    final selection = _noteCtrl.selection;
    if (selection.isValid) return;

    _noteCtrl.selection =
        TextSelection.collapsed(offset: _noteCtrl.text.length);
  }

  void _showKeyboard() {
    if (_loading) return;
    _noteFocus.requestFocus();
    _ensureNoteSelection();
    if (_keyboardEntry != null) return;

    _keyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _noteCtrl,
            onEnter: _hideKeyboard,
            onClose: _hideKeyboard,
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_keyboardEntry!);
  }

  void _hideKeyboard() {
    _keyboardEntry?.remove();
    _keyboardEntry = null;
  }

  Future<void> _loadExpenseTypes() async {
    setState(() => _loadingTypes = true);

    try {
      final types = await sl<PosSyncService>().loadExpenseTypes();

      if (!mounted) return;
      setState(() {
        _expenseTypes = types
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'name': item.name,
                ...item.rawJson,
              },
            )
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки типов расходов: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  Future<void> _pickExpenseType() async {
    if (_loadingTypes) return;

    // если ещё не подгружали — подгрузим
    if (_expenseTypes.isEmpty) {
      await _loadExpenseTypes();
    }
    if (!mounted) return;

    if (_expenseTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Типы расходов не найдены')),
      );
      return;
    }

    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.category_outlined, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Выберите тип расхода',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      icon: const Icon(Icons.close),
                      splashRadius: 22,
                      tooltip: 'Закрыть',
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // list container
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6E6EB)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _expenseTypes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = _expenseTypes[i];
                          final id = item['id']?.toString() ?? '';
                          final title = (item['name'] ??
                                  item['title'] ??
                                  item['label'] ??
                                  item['code'] ??
                                  id)
                              .toString();

                          final disabled = id.isEmpty;

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: disabled
                                  ? null
                                  : () => Navigator.of(ctx).pop(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFEDEDF2)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4FF),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                          Icons.receipt_long_outlined,
                                          size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.15,
                                          fontWeight: FontWeight.w500,
                                          color: disabled
                                              ? Colors.black38
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(
                                      Icons.chevron_right,
                                      color: disabled
                                          ? Colors.black26
                                          : Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // footer
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: Color(0xFFE6E6EB)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Text(
                      'ОТМЕНА',
                      style: TextStyle(
                          fontWeight: FontWeight.w500, letterSpacing: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _expenseTypeId = picked['id']?.toString();
      _expenseTypeTitle = (picked['name'] ??
              picked['title'] ??
              picked['label'] ??
              picked['code'] ??
              _expenseTypeId)
          .toString();
    });
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount == null || amount <= 0) return;

    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не найден key POS терминала')),
      );
      return;
    }

    // ✅ Для расхода обязателен expenseTypeId
    if (_isExpense && (_expenseTypeId == null || _expenseTypeId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите тип расхода')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final provider = context.read<AuthTokenProvider>();
      final deviceId = provider.deviceId?.trim() ?? '';
      final accountId = provider.accountId?.trim() ?? '';
      final posSessionId = provider.shiftId?.trim() ?? '';
      if (deviceId.isEmpty) {
        throw Exception('deviceId не найден');
      }
      if (accountId.isEmpty) {
        throw Exception('accountId не найден');
      }
      if (posSessionId.isEmpty) {
        throw Exception('Смена не открыта');
      }

      final result = await sl<PosSyncService>().createPayment(
        key: key,
        deviceId: deviceId,
        posSessionId: posSessionId,
        accountId: accountId,
        isExpense: _isExpense, // ✅ type=false -> расход
        expenseTypeId: _isExpense ? _expenseTypeId : null,
        amount: amount,
        comment: _noteCtrl.text.trim(),
        date: DateTime.now(),
        userId: provider.activeUserId?.trim(),
      );

      if (result.result == QueueSendResult.manual) {
        throw Exception(
            result.errorMessage ?? 'Операция требует ручной обработки');
      }

      if (provider.fiscalizationEnabled &&
          result.result == QueueSendResult.sent) {
        final fiscalService = sl<FiscalReceiptService>();
        final fiscalReceipt =
            fiscalService.fromSaleResponse(result.responseData);
        if (fiscalReceipt == null) {
          throw StateError(
            'Операция сохранена, но backend не вернул фискальный чек. Повторно операцию не создавайте.',
          );
        }
        await fiscalService.save(
          fiscalReceipt,
          localReceiptPrinted: false,
          saleIds: {
            result.clientId,
            (result.responseData?['id'] ?? '').toString(),
          },
        );
        fiscalService.startBackgroundPolling(
          key: key,
          deviceId: deviceId,
          receipt: fiscalReceipt,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FiscalReceiptDialog(
            initial: fiscalReceipt,
            posKey: key,
            deviceId: deviceId,
            paperMm: provider.receiptPaperMm,
            printerName: provider.receiptPrinterName,
          ),
        );
      }

      if (!mounted) return;
      _hideKeyboard();
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isExpense ? 'Расход сохранён' : 'Взнос сохранён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleAmountChanged() {
    final normalized = _normalizeAmountInput(_amountCtrl.text);
    if (_text == normalized) return;
    setState(() => _text = normalized);
  }

  String _normalizeAmountInput(String raw) {
    var value = raw.replaceAll(' ', '').replaceAll(',', '.');
    if (value.isEmpty) return '';

    final cleaned = StringBuffer();
    var hasDot = false;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final isDigit = rune >= 48 && rune <= 57;
      if (isDigit) {
        cleaned.write(char);
        continue;
      }
      if (char == '.' && !hasDot) {
        cleaned.write(char);
        hasDot = true;
      }
    }

    value = cleaned.toString();
    if (value.startsWith('.')) {
      value = '0$value';
    }
    if (value.startsWith('0') && value.length > 1 && !value.startsWith('0.')) {
      value = value.replaceFirst(RegExp(r'^0+'), '');
      if (value.isEmpty) value = '0';
    }
    return value;
  }

  void _setAmountText(String value) {
    final normalized = _normalizeAmountInput(value);
    _amountCtrl.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _appendToken(String token) {
    if (_loading) return;

    var value = _text;

    if (token == 'backspace') {
      if (value.isNotEmpty) value = value.substring(0, value.length - 1);
      _setAmountText(value);
      return;
    }

    if (token == '.') {
      if (!value.contains('.')) {
        value = value.isEmpty ? '0.' : '$value.';
      }
      _setAmountText(value);
      return;
    }

    value = value == '0' ? token : '$value$token';
    value = value.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    _setAmountText(value);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type ? 'Взнос' : 'Расходы';
    final amountText =
        _text.isEmpty ? '0,00 ₸' : '${_text.replaceAll('.', ',')} ₸';
    final typeText = _isExpense
        ? (_expenseTypeTitle ??
            (_loadingTypes ? 'Загрузка типов...' : 'Тип расхода'))
        : 'Взнос в кассу';

    return SizedBox(
      width: 527,
      height: 432,
      child: DefaultTextStyle(
        style: GoogleFonts.inter(color: Colors.black),
        child: Stack(
          children: [
            Positioned(
              left: 3.12695,
              top: 0,
              width: 520,
              height: 425,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(15.6354),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 3.127,
                      offset: const Offset(0, 3.127),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 3.12695,
              top: 0,
              width: 520,
              height: 49.8206,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF373D46),
                  borderRadius: BorderRadius.circular(10.163),
                ),
                padding: const EdgeInsets.only(left: 20.2),
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 19.6271,
              top: 68.5001,
              width: 200.273,
              height: 46.6278,
              child: _ExpenseAmountBox(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                displayText: amountText,
                onSubmitted: (_) => _noteFocus.requestFocus(),
              ),
            ),
            Positioned(
              left: 247.627,
              top: 68.5,
              width: 258,
              height: 42,
              child: _ExpenseSelectBox(
                text: typeText,
                showArrow: _isExpense,
                onTap: _loading || !_isExpense ? null : _pickExpenseType,
              ),
            ),
            Positioned(
              left: 247.627,
              top: 132.5,
              width: 258,
              height: 198,
              child: _ExpenseCommentBox(
                controller: _noteCtrl,
                focusNode: _noteFocus,
                onOpenKeyboard: _showKeyboard,
              ),
            ),
            _ExpenseKeyButton(
              left: 19.127,
              top: 132,
              text: '7',
              onTap: () => _appendToken('7'),
            ),
            _ExpenseKeyButton(
              left: 89.4326,
              top: 132,
              text: '8',
              onTap: () => _appendToken('8'),
            ),
            _ExpenseKeyButton(
              left: 159.739,
              top: 132,
              text: '9',
              onTap: () => _appendToken('9'),
            ),
            _ExpenseKeyButton(
              left: 19.127,
              top: 202.306,
              text: '4',
              onTap: () => _appendToken('4'),
            ),
            _ExpenseKeyButton(
              left: 89.4326,
              top: 202.306,
              text: '5',
              onTap: () => _appendToken('5'),
            ),
            _ExpenseKeyButton(
              left: 159.739,
              top: 202.306,
              text: '6',
              onTap: () => _appendToken('6'),
            ),
            _ExpenseKeyButton(
              left: 19.127,
              top: 272.612,
              text: '1',
              onTap: () => _appendToken('1'),
            ),
            _ExpenseKeyButton(
              left: 89.4326,
              top: 272.611,
              text: '2',
              onTap: () => _appendToken('2'),
            ),
            _ExpenseKeyButton(
              left: 159.739,
              top: 272.612,
              text: '3',
              onTap: () => _appendToken('3'),
            ),
            _ExpenseKeyButton(
              left: 19.127,
              top: 342.919,
              icon: Icons.backspace,
              fg: const Color(0xFF33CC99),
              onTap: () => _appendToken('backspace'),
            ),
            _ExpenseKeyButton(
              left: 89.4326,
              top: 342.919,
              text: '0',
              onTap: () => _appendToken('0'),
            ),
            _ExpenseKeyButton(
              left: 159.739,
              top: 342.918,
              text: '.',
              onTap: () => _appendToken('.'),
            ),
            Positioned(
              left: 247.127,
              top: 342,
              width: 95.7723,
              height: 61.5518,
              child: _ExpenseActionButton(
                text: 'ЗАКРЫТЬ',
                color: const Color(0xFFD15850),
                onTap: _loading ? null : () => Navigator.of(context).pop(false),
              ),
            ),
            Positioned(
              left: 351.042,
              top: 342.866,
              width: 155.085,
              height: 59.7355,
              child: _ExpenseActionButton(
                text: widget.type ? 'СОХРАНИТЬ' : 'СОХРАНИТЬ',
                color: const Color(0xFF33CC99),
                loading: _loading,
                onTap: (_loading || (_amount == null) || (_amount! <= 0))
                    ? null
                    : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseAmountBox extends StatelessWidget {
  const _ExpenseAmountBox({
    required this.controller,
    required this.focusNode,
    required this.displayText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String displayText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.50173),
        border: Border.all(color: const Color(0xFF00A1FF), width: 1.0002),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        textAlign: TextAlign.right,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
        ],
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: displayText,
          hintStyle: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            height: 1,
          ),
        ),
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          height: 1,
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _ExpenseSelectBox extends StatelessWidget {
  const _ExpenseSelectBox({
    required this.text,
    required this.onTap,
    this.showArrow = true,
  });

  final String text;
  final VoidCallback? onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF999999),
        padding: const EdgeInsets.fromLTRB(13, 0, 12, 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5.5),
          side: const BorderSide(color: Color(0xFF00A1FF), width: 1),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF999999),
              ),
            ),
          ),
          if (showArrow)
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF4F4F4F),
              size: 28,
            ),
        ],
      ),
    );
  }
}

class _ExpenseCommentBox extends StatelessWidget {
  const _ExpenseCommentBox({
    required this.controller,
    required this.focusNode,
    required this.onOpenKeyboard,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpenKeyboard;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.50173),
        border: Border.all(color: const Color(0xFF00A1FF), width: 1.0002),
      ),
      child: Stack(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'Комментарий',
              hintStyle: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF999999),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(13, 14, 48, 14),
            ),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: IconButton(
              tooltip: 'Клавиатура',
              onPressed: onOpenKeyboard,
              icon: const Icon(
                Icons.keyboard_alt_outlined,
                color: Color(0xFF999999),
                size: 30,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseKeyButton extends StatelessWidget {
  const _ExpenseKeyButton({
    required this.left,
    required this.top,
    required this.onTap,
    this.text,
    this.icon,
    this.fg = Colors.black,
  });

  final double left;
  final double top;
  final String? text;
  final IconData? icon;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: 61.1361,
      height: 61.1361,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFDADADA),
          foregroundColor: fg,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9.0685),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: icon == null
            ? Text(
                text ?? '',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              )
            : Icon(icon, size: 20, color: fg),
      ),
    );
  }
}

class _ExpenseActionButton extends StatelessWidget {
  const _ExpenseActionButton({
    required this.text,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  final String text;
  final Color color;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.58),
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6.57621),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
    );
  }
}
