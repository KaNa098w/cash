import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/models/fiscal_receipt.dart';
import 'package:leemon_app/core/marking/gs1_datamatrix_validator.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/service/fiscal_receipt_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/provider/auth_provider.dart'
    show AuthTokenProvider;
import 'package:leemon_app/features/data/datasources/customers_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/entities/cart_item.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_dialog.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_page.dart';
import 'package:leemon_app/features/presentation/widgets/last_sale_amount_notifier.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'package:leemon_app/features/presentation/widgets/receipt_print_confirmation_dialog.dart';
import 'package:leemon_app/features/presentation/utils/comment_text_controller.dart';
import 'package:uuid/uuid.dart';
import '../../data/utils/money.dart';
import '../../domain/entities/payment.dart';

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key});

  static const designWidth = 573.0;
  static const designHeight = 540.0;

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _MarkCodesDialog extends StatefulWidget {
  const _MarkCodesDialog({
    required this.productName,
    required this.requiredCount,
    required this.initialCodes,
    required this.usedCodes,
    this.gtin,
    this.ntin,
  });

  final String productName;
  final int requiredCount;
  final List<String> initialCodes;
  final Set<String> usedCodes;
  final String? gtin;
  final String? ntin;

  @override
  State<_MarkCodesDialog> createState() => _MarkCodesDialogState();
}

class _MarkCodesDialogState extends State<_MarkCodesDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final List<String> _codes =
      widget.initialCodes.take(widget.requiredCount).toList(growable: true);
  String? _error;

  KeyEventResult _handleScannerKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter) {
      _acceptScan(_controller.text);
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
    final character = MarkingKeyboardInputFormatter.scannerCharacter(event);
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _acceptScan(String _) {
    if (_codes.length >= widget.requiredCount) return;
    // TextField does not include the scanner's Enter key. Keep every other
    // character exactly as received (including the GS separator, ASCII 29).
    final raw = MarkingKeyboardInputFormatter.normalize(_controller.text);
    final validation = Gs1DataMatrixValidator.validate(
      raw,
      expectedGtin:
          (widget.gtin ?? '').trim().isNotEmpty ? widget.gtin : widget.ntin,
    );
    if (!validation.isValid) {
      setState(() => _error = validation.message);
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    final canonical = validation.canonical!;
    final duplicate = widget.usedCodes.contains(canonical) ||
        _codes.any(
          (code) => Gs1DataMatrixValidator.canonicalCode(code) == canonical,
        );
    if (duplicate) {
      setState(
        () => _error = 'Этот код маркировки уже добавлен в продажу.',
      );
      _controller.clear();
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      _codes.add(canonical);
      _error = null;
      _controller.clear();
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final complete = _codes.length == widget.requiredCount;
    return AlertDialog(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
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
                  'Маркировка товара',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 3),
                Text(
                  'Отсканируйте код с упаковки',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF64748B),
                  ),
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
              child: Text(
                widget.productName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if ((widget.gtin ?? '').isNotEmpty ||
                (widget.ntin ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text([
                  if ((widget.gtin ?? '').isNotEmpty) 'GTIN ${widget.gtin}',
                  if ((widget.ntin ?? '').isNotEmpty) 'NTIN ${widget.ntin}',
                ].join('  •  ')),
              ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: widget.requiredCount == 0
                  ? 1
                  : _codes.length / widget.requiredCount,
              minHeight: 8,
              color: const Color(0xFF22B982),
              backgroundColor: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Text(
              'Отсканировано ${_codes.length} из ${widget.requiredCount}',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
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
                enabled: !complete,
                autofocus: true,
                obscureText: true,
                obscuringCharacter: '•',
                onSubmitted: _acceptScan,
                onTapOutside: (_) => _focusNode.requestFocus(),
                decoration: InputDecoration(
                  labelText:
                      complete ? 'Все коды отсканированы' : 'Код маркировки',
                  hintText: complete ? null : 'Сканируйте маркировку',
                  errorText: _error,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(
                    Icons.qr_code_scanner_rounded,
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
            if (_codes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  _codes.length,
                  (index) => Chip(
                    label: Text('Код ${index + 1}'),
                    avatar: const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: Color(0xFF15966A),
                    ),
                    backgroundColor: const Color(0xFFE8F8F2),
                    side: BorderSide.none,
                    onDeleted: () {
                      setState(() => _codes.removeAt(index));
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _focusNode.requestFocus(),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF475569),
            minimumSize: const Size(110, 48),
          ),
          child: const Text('Закрыть'),
        ),
        FilledButton.icon(
          onPressed: complete
              ? () => Navigator.of(context).pop(List<String>.from(_codes))
              : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Продолжить'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF22B982),
            disabledBackgroundColor: const Color(0xFFCBD5E1),
            minimumSize: const Size(160, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class FiscalReceiptDialog extends StatefulWidget {
  const FiscalReceiptDialog({
    super.key,
    required this.initial,
    required this.posKey,
    required this.deviceId,
    required this.paperMm,
    this.printerName,
  });

  final FiscalReceipt initial;
  final String posKey;
  final String deviceId;
  final int paperMm;
  final String? printerName;

  @override
  State<FiscalReceiptDialog> createState() => _FiscalReceiptDialogState();
}

class _FiscalReceiptDialogState extends State<FiscalReceiptDialog> {
  late FiscalReceipt _receipt = widget.initial;
  final DateTime _activePollingStartedAt = DateTime.now();
  bool _printing = false;
  String? _error;
  Timer? _timer;
  bool _autoPrintStarted = false;

  FiscalReceiptService get _service => sl<FiscalReceiptService>();

  @override
  void initState() {
    super.initState();
    _schedulePoll();
    if (_receipt.canPrint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoPrint());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (!_receipt.isPending) return;
    _timer = Timer(Duration(seconds: _receipt.pollAfterSeconds), _poll);
  }

  Future<void> _poll() async {
    try {
      final updated = await _service.refresh(
        key: widget.posKey,
        deviceId: widget.deviceId,
        receiptId: _receipt.id,
      );
      if (!mounted) return;
      setState(() {
        _receipt = updated;
        _error = null;
      });
      if (updated.canPrint) unawaited(_autoPrint());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось обновить статус. Повторяем…');
    }
    _schedulePoll();
  }

  Future<void> _print() async {
    final shouldPrint = await showReceiptPrintConfirmation(
      context,
      title: 'Распечатать фискальный чек?',
      message: 'Фискальный чек готов. Отправить его на принтер?',
    );
    if (!mounted || !shouldPrint) return;

    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await _service.printTicket(
        _receipt,
        key: widget.posKey,
        deviceId: widget.deviceId,
        paperMm: widget.paperMm,
        printerName: widget.printerName,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'Ошибка печати: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _autoPrint() async {
    if (_autoPrintStarted || !_receipt.canPrint || !mounted) return;
    _autoPrintStarted = true;
    await _print();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _receipt.hasFailed;
    final activePolling = DateTime.now().difference(_activePollingStartedAt) <
        const Duration(seconds: 60);
    final pending = _receipt.isPending;
    final accentColor = failed
        ? const Color(0xFFDC2626)
        : _receipt.canPrint
            ? const Color(0xFF15966A)
            : const Color(0xFF2563EB);
    final accentBackground = failed
        ? const Color(0xFFFEECEC)
        : _receipt.canPrint
            ? const Color(0xFFE8F8F2)
            : const Color(0xFFEAF2FF);
    final title = switch (_receipt.status) {
      'succeeded' => 'Фискальный чек готов',
      'failed' => 'Ошибка фискализации',
      'needs_review' => 'Требуется проверка',
      _ => 'Формируем фискальный чек',
    };
    return AlertDialog(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accentBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              failed
                  ? Icons.error_outline_rounded
                  : _receipt.canPrint
                      ? Icons.receipt_long_rounded
                      : Icons.hourglass_top_rounded,
              color: accentColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          if (!pending && !_printing)
            IconButton(
              tooltip: 'Закрыть',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(
                Icons.close_rounded,
                color: Color(0xFF64748B),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (activePolling)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: const LinearProgressIndicator(
                          minHeight: 7,
                          color: Color(0xFF2563EB),
                          backgroundColor: Color(0xFFDBEAFE),
                        ),
                      ),
                    if (activePolling) const SizedBox(height: 14),
                    Text(
                      activePolling
                          ? 'Пожалуйста, подождите'
                          : 'Обработка продолжается в фоне',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!pending && !failed && _error == null) ...[
              Text(
                _receipt.canPrint
                    ? 'Чек готов к печати'
                    : 'Фискальный чек обработан',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF475569),
                ),
              ),
            ],
            if ((_receipt.errorMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_receipt.errorMessage!, textAlign: TextAlign.center),
            ],
            if (_receipt.lastErrorCodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Коды Webkassa: ${_receipt.lastErrorCodes.join(', ')}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_receipt.webkassaGuidance != null) ...[
              const SizedBox(height: 8),
              Text(
                _receipt.webkassaGuidance!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF7A271A)),
              ),
            ],
            if (_receipt.offlineMode) ...[
              const SizedBox(height: 10),
              Text(
                _receipt.ofdDeliveryStatus == 'queued_by_webkassa'
                    ? 'Чек создан в автономном режиме Webkassa и будет передан в ОФД после восстановления связи.'
                    : 'Чек создан в автономном режиме Webkassa.',
                textAlign: TextAlign.center,
              ),
            ],
            if (_receipt.canPrint && !_printing && _error != null) ...[
              const SizedBox(height: 14),
              const Text(
                'Автоматическая печать не удалась. Проверьте принтер и повторите.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEECEC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFB42318)),
                ),
              ),
            ],
            if (failed) ...[
              const SizedBox(height: 12),
              const Text(
                'Продажа сохранена. Повторно создавать её не нужно.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _printing || pending ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF475569),
            minimumSize: const Size(110, 48),
          ),
          child: Text(
            pending ? 'Подождите…' : 'Закрыть',
          ),
        ),
        FilledButton.icon(
          onPressed: _receipt.canPrint && !_printing ? _print : null,
          icon: _printing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_rounded),
          label: Text(
            _error == null ? 'Печать фискального чека' : 'Повторить печать',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF22B982),
            disabledBackgroundColor: const Color(0xFFCBD5E1),
            minimumSize: const Size(190, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentPanelState extends State<PaymentPanel> {
  final _cashCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  final _cashFocusNode = FocusNode();
  final _cardFocusNode = FocusNode();
  final _commentFocusNode = FocusNode();
  OverlayEntry? _commentKeyboardEntry;
  List<LocalAccount> _bankAccounts = const [];
  String? _selectedBankAccountId;
  bool _loadingBankAccounts = false;
  bool _paying = false;
  bool _paymentSuccess = false;
  bool _saleQueued = false;
  bool _openingCustomerPicker = false;
  bool _isMixedPayment = false;
  bool _mixedActiveIsCard = false;
  bool _markingConflictNeedsExtraCode = false;

  @override
  void initState() {
    super.initState();
    _commentCtrl.addListener(_capitalizeComment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<PosCubit>();
      cubit.setPaymentKind(PaymentKind.cash);
      cubit.setReceived(0);
      _cashCtrl.clear();
      _cardCtrl.clear();
      _cashFocusNode.requestFocus();
    });
    _loadBankAccounts();
  }

  @override
  void dispose() {
    _hideCommentKeyboard();
    _commentCtrl.removeListener(_capitalizeComment);
    _commentFocusNode.dispose();
    _cardFocusNode.dispose();
    _cashFocusNode.dispose();
    _commentCtrl.dispose();
    _cardCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  void _capitalizeComment() {
    capitalizeFirstLetterInController(_commentCtrl);
  }

  Future<void> _loadBankAccounts() async {
    if (_loadingBankAccounts) return;
    setState(() => _loadingBankAccounts = true);
    try {
      final accounts = await sl<PosSyncService>().loadAccounts();
      final bankAccounts = accounts
          .where((account) =>
              account.visibleToPos && account.normalizedType == 'bank')
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _bankAccounts = bankAccounts;
        final selectedExists = bankAccounts
            .any((account) => account.id.trim() == _selectedBankAccountId);
        if (!selectedExists) {
          _selectedBankAccountId =
              bankAccounts.length == 1 ? bankAccounts.single.id : null;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingBankAccounts = false);
    }
  }

  LocalAccount? get _selectedBankAccount {
    final selectedId = (_selectedBankAccountId ?? '').trim();
    if (selectedId.isEmpty) {
      return null;
    }
    return _bankAccounts.cast<LocalAccount?>().firstWhere(
          (account) => account?.id.trim() == selectedId,
          orElse: () => null,
        );
  }

  void _ensureCommentSelection() {
    final selection = _commentCtrl.selection;
    if (selection.isValid) return;

    _commentCtrl.selection =
        TextSelection.collapsed(offset: _commentCtrl.text.length);
  }

  void _showCommentKeyboard() {
    if (_paying) return;
    _commentFocusNode.requestFocus();
    _ensureCommentSelection();
    if (_commentKeyboardEntry != null) return;

    _commentKeyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CommentKeyboardPreview(controller: _commentCtrl),
              const SizedBox(height: 6),
              OnScreenKeyboardSheet(
                controllerGetter: () => _commentCtrl,
                onEnter: _hideCommentKeyboard,
                onClose: _hideCommentKeyboard,
              ),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_commentKeyboardEntry!);
  }

  void _hideCommentKeyboard() {
    _commentKeyboardEntry?.remove();
    _commentKeyboardEntry = null;
  }

  void _applyTextToState(BuildContext context, String text) {
    final cubit = context.read<PosCubit>();
    final normalized = text.replaceAll(',', '.');
    final value = double.tryParse(normalized) ?? 0;
    cubit.setReceived(value);
  }

  double _parseAmount(String text) {
    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  num _readNum(dynamic source, List<String> keys) {
    if (source is! Map) return 0;
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value;
      final parsed = num.tryParse((value ?? '').toString().trim());
      if (parsed != null) return parsed;
    }
    return 0;
  }

  bool _readBool(dynamic source, List<String> keys, {bool fallback = true}) {
    if (source is! Map) return fallback;
    for (final key in keys) {
      final value = source[key];
      if (value is bool) return value;
      final normalized = (value ?? '').toString().trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return fallback;
  }

  DateTime _defaultDebtDueDate(DateTime date) {
    return date.add(const Duration(days: 30));
  }

  String _normalizePaymentMethodLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cash':
        return 'Наличные';
      case 'card':
        return 'Безналичный';
      case 'mixed':
        return 'Смешанная';
      case 'debt':
      case 'credit':
      case 'partial_debt':
        return 'В долг';
      default:
        return raw.trim().isEmpty ? '-' : raw.trim();
    }
  }

  void _setText(
    BuildContext context,
    String text, {
    bool applyToState = true,
  }) {
    _cashCtrl.text = text;
    _cashCtrl.selection = TextSelection.collapsed(offset: text.length);
    if (applyToState) {
      _applyTextToState(context, text);
    }
  }

  void _setCardText(
    BuildContext context,
    String text, {
    bool applyToState = true,
  }) {
    _cardCtrl.text = text;
    _cardCtrl.selection = TextSelection.collapsed(offset: text.length);
    if (applyToState) {
      _applyTextToState(context, text);
    }
  }

  Future<void> _pickCustomer() async {
    if (_openingCustomerPicker) return;
    _openingCustomerPicker = true;

    final posCubit = context.read<PosCubit>();

    try {
      final customers = (await sl<PosSyncService>().loadCustomers())
          .map(
            (e) => CustomerLite(
              id: e.id,
              name: e.name,
              phone: e.phone,
              balance: _readNum(
                e.rawJson,
                const ['balance', 'debt_balance', 'current_debt'],
              ),
              debtLimit: _readNum(
                e.rawJson,
                const ['debt_limit', 'credit_limit', 'limit', 'max_debt'],
              ),
              debtAllowed: _readBool(
                e.rawJson,
                const [
                  'debt_allowed',
                  'allow_debt',
                  'credit_allowed',
                  'allow_credit',
                ],
              ),
            ),
          )
          .toList();

      if (!mounted) return;
      final selected = await showCustomerPickerDialog(
        context,
        customers: customers,
      );

      if (!mounted) return;
      if (selected == null) return;
      posCubit.setCustomerForActiveTicket(
        PosCustomer(
          id: selected.id,
          name: selected.name,
          phone: selected.phone,
          balance: selected.balance,
          debtLimit: selected.debtLimit,
          debtAllowed: selected.debtAllowed,
        ),
      );
    } catch (_) {
      // intentionally no snackbar in payment panel
    } finally {
      _openingCustomerPicker = false;
    }
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    final trimmed = s.endsWith('.00')
        ? s.substring(0, s.length - 3)
        : s.endsWith('0')
            ? s.substring(0, s.length - 1)
            : s;
    return trimmed.replaceAll('.', ',');
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _ensureMarkCodes(PosCubit cubit) async {
    var assignedConflictExtraCode = false;
    for (var index = 0; index < cubit.state.items.length; index++) {
      final item = cubit.state.items[index];
      if (!item.product.requiresMarking) continue;
      final roundedQuantity = item.qty.round();
      if ((item.qty - roundedQuantity).abs() > 0.000001) {
        _showError('Маркированный товар продаётся только целыми единицами');
        return false;
      }
      final partialMarkedPackage = item.product.hasConversion &&
          item.product.allowsPartialPackages &&
          (item.product.conversionValue ?? 0) > 0;
      var requiredCodes = partialMarkedPackage
          ? (item.qty / item.product.conversionValue!).ceil()
          : roundedQuantity;
      if (_markingConflictNeedsExtraCode &&
          partialMarkedPackage &&
          !assignedConflictExtraCode) {
        requiredCodes = item.markCodes.length + 1;
        assignedConflictExtraCode = true;
      }
      if (item.markCodes.length >= requiredCodes) continue;
      final codes = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MarkCodesDialog(
          productName: item.product.name,
          gtin: item.product.gtin,
          ntin: item.product.ntin,
          requiredCount: requiredCodes,
          initialCodes: item.markCodes,
          usedCodes: {
            for (var otherIndex = 0;
                otherIndex < cubit.state.items.length;
                otherIndex++)
              if (otherIndex != index)
                for (final code in cubit.state.items[otherIndex].markCodes)
                  Gs1DataMatrixValidator.canonicalCode(code),
          },
        ),
      );
      if (!mounted || codes == null) return false;
      cubit.setMarkCodes(index, codes);
    }
    if (assignedConflictExtraCode) {
      _markingConflictNeedsExtraCode = false;
    }
    return true;
  }

  Future<void> _showMissingDebtCustomerDialog() async {
    if (!mounted) return;

    final shouldPick = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _MissingDebtCustomerDialog(),
    );

    if (!mounted) return;
    if (shouldPick == true) {
      await _pickCustomer();
    }
  }

  final _printService = PrintService();

  double _saleQuantityForItem(CartItem it) {
    return it.qty;
  }

  Future<PosCustomer?> _validateDebtCustomerOnline({
    required String posKey,
    required PosCustomer customer,
  }) async {
    final customers = await sl<CustomersRemoteDataSource>().listCustomers(
      key: posKey,
      size: 500,
    );
    for (final remote in customers) {
      if (remote.id != customer.id) continue;
      return PosCustomer(
        id: remote.id,
        name: remote.name,
        phone: remote.phone,
        balance: remote.balance,
        debtLimit: remote.debtLimit,
        debtAllowed: remote.debtAllowed,
      );
    }
    return null;
  }

  bool _validateCustomSalePrices(
    List<CartItem> items, {
    required bool canCustomPrice,
  }) {
    for (final item in items) {
      if (item.product.isUniversal || item.customUnitPrice == null) continue;

      final productName = item.product.name.trim().isEmpty
          ? item.product.id
          : item.product.name.trim();

      if (!canCustomPrice) {
        _showError('Ручная цена запрещена для магазина: $productName');
        return false;
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PaymentPanel.designHeight,
      width: PaymentPanel.designWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: BlocConsumer<PosCubit, PosState>(
          listenWhen: (prev, curr) => prev.received != curr.received,
          listener: (context, state) {
            if (_isMixedPayment) return;

            final text = _fmt(state.received);
            if (!_isMixedPayment && state.paymentKind == PaymentKind.card) {
              if (_cardCtrl.text != text) {
                _cardCtrl.text = text;
                _cardCtrl.selection =
                    TextSelection.collapsed(offset: text.length);
              }
              return;
            }
            if (_cashCtrl.text != text) {
              _setText(context, text);
            }
          },
          builder: (context, state) {
            final cubit = context.read<PosCubit>();
            final total = cubit.total;
            final change = cubit.change.clamp(0, double.infinity);
            final hasItems = state.items.isNotEmpty;
            final isDebtSale = state.paymentKind == PaymentKind.credit;
            final hasMarkedItems =
                state.items.any((item) => item.product.requiresMarking);
            final markedDebtBlocked = isDebtSale && hasMarkedItems;
            final requiresBankAccount =
                state.paymentKind == PaymentKind.card || _isMixedPayment;
            final hasSelectedBankAccount =
                !requiresBankAccount || _selectedBankAccount != null;
            final hasSelectedPaymentMethod =
                state.paymentKind == PaymentKind.card ||
                    state.paymentKind == PaymentKind.credit ||
                    state.received > 0;
            final canSubmitPayment = !_paying &&
                !_saleQueued &&
                hasItems &&
                !markedDebtBlocked &&
                hasSelectedPaymentMethod &&
                hasSelectedBankAccount;

            Future<void> submitPayment() async {
              if (!canSubmitPayment) return;

              final posCubit = context.read<PosCubit>();
              final auth = context.read<AuthTokenProvider>();

              final key = auth.posKey?.trim() ?? '';
              final deviceId = auth.deviceId?.trim() ?? '';
              final storeId = auth.storeId?.trim() ?? '';
              final posId = auth.posId?.trim() ?? '';
              final userId = auth.activeUserId?.trim() ?? '';
              final fallbackAccountId = auth.accountId?.trim() ?? '';

              if (key.isEmpty) {
                _showError('Не найден ключ POS');
                return;
              }
              if (deviceId.isEmpty) {
                _showError('Не найден device_id терминала');
                return;
              }
              if (storeId.isEmpty) {
                _showError('Не найден магазин терминала');
                return;
              }
              if (posId.isEmpty) {
                _showError('Не найден идентификатор POS');
                return;
              }
              if (userId.isEmpty) {
                _showError('Не выбран кассир');
                return;
              }
              if (fallbackAccountId.isEmpty) {
                _showError('Не найден наличный счёт POS');
                return;
              }
              if (posCubit.state.items.isEmpty) {
                _showError('Корзина пустая');
                return;
              }
              if (isDebtSale &&
                  posCubit.state.items
                      .any((item) => item.product.requiresMarking)) {
                _showError(
                  'Маркированный товар нельзя продавать в долг. Выберите наличную или безналичную оплату.',
                );
                return;
              }
              final saleComment = _commentCtrl.text.trim();
              if (saleComment.length > 1000) {
                _showError('Комментарий не должен превышать 1000 символов');
                return;
              }

              if (posCubit.state.paymentKind == PaymentKind.cash &&
                  !_isMixedPayment &&
                  posCubit.state.received < posCubit.total) {
                _showError('Недостаточно наличных для оплаты');
                return;
              }
              if (isDebtSale && posCubit.state.activeCustomer == null) {
                await _showMissingDebtCustomerDialog();
                return;
              }

              var selectedCustomer = posCubit.state.activeCustomer;
              if (isDebtSale && selectedCustomer != null) {
                PosCustomer debtCustomer;
                try {
                  final verified = await _validateDebtCustomerOnline(
                    posKey: key,
                    customer: selectedCustomer,
                  );
                  if (verified == null) {
                    _showError(
                      'Этот покупатель недоступен для текущей кассы. Выполните синхронизацию или выберите другого покупателя.',
                    );
                    return;
                  }
                  debtCustomer = verified;
                  selectedCustomer = verified;
                  posCubit.setCustomerForActiveTicket(verified);
                } catch (error, stackTrace) {
                  developer.log(
                    'Debt customer validation failed',
                    name: 'PaymentPanel',
                    error: error,
                    stackTrace: stackTrace,
                  );
                  _showError(
                    'Не удалось проверить покупателя для продажи в долг. Проверьте интернет.',
                  );
                  return;
                }

                if (!debtCustomer.debtAllowed) {
                  _showError('Клиенту запрещены продажи в долг');
                  return;
                }
                final currentDebt = debtCustomer.balance.toDouble();
                final debtSalePaidNow =
                    _parseAmount(_cashCtrl.text).clamp(0, posCubit.total);
                final nextDebt =
                    currentDebt + (posCubit.total - debtSalePaidNow);
                final debtLimit = debtCustomer.debtLimit.toDouble();
                if (debtLimit > 0 && nextDebt > debtLimit) {
                  _showError(
                    'Лимит долга превышен: ${money(nextDebt)} из ${money(debtLimit)}',
                  );
                  return;
                }
              }

              if (!await _ensureMarkCodes(posCubit)) return;

              // Capture amounts before async gap
              final isMixed = _isMixedPayment;
              final containsMarkedItems = posCubit.state.items
                  .any((item) => item.product.requiresMarking);
              final fiscalizationEnabled = auth.fiscalizationEnabled;
              final totalAmountInt = posCubit.total.round();
              final customPricesOk = _validateCustomSalePrices(
                posCubit.state.items,
                canCustomPrice: auth.allowCustomSalePrices,
              );
              if (!customPricesOk) return;

              final saleItems = <SaleItemModel>[];
              for (final it in posCubit.state.items) {
                final qty = _saleQuantityForItem(it);
                final unitPrice = it.effectiveUnitPrice;
                final price = double.parse(unitPrice.toStringAsFixed(2));
                final totalPrice =
                    double.parse((unitPrice * qty).toStringAsFixed(2));

                saleItems.add(
                  SaleItemModel(
                    productId: it.product.id,
                    quantity: qty,
                    price: price,
                    totalPrice: totalPrice,
                    id: '',
                    saleId: '',
                    markCodes: it.markCodes
                        .map(Gs1DataMatrixValidator.canonicalCode)
                        .toList(growable: false),
                  ),
                );
              }

              final exactTotal = double.parse(
                saleItems
                    .fold(0.0, (s, e) => s + e.totalPrice)
                    .toStringAsFixed(2),
              );
              final mixedCashAmount = double.parse(
                _parseAmount(_cashCtrl.text)
                    .clamp(0, exactTotal)
                    .toStringAsFixed(2),
              );
              final mixedCardAmount = double.parse(
                _parseAmount(_cardCtrl.text)
                    .clamp(0, exactTotal)
                    .toStringAsFixed(2),
              );
              if (isMixed) {
                final mixedTotal = double.parse(
                  (mixedCashAmount + mixedCardAmount).toStringAsFixed(2),
                );
                if ((mixedTotal - exactTotal).abs() > 0.01) {
                  _showError(
                      'Сумма наличных и безналичных должна быть равна итогу');
                  return;
                }
              }

              final debtPaidNow = isDebtSale
                  ? _parseAmount(_cashCtrl.text).clamp(0, exactTotal).round()
                  : 0;
              final debtAmount =
                  isDebtSale ? (exactTotal - debtPaidNow).round() : 0;
              final paymentMethod = isDebtSale
                  ? 'debt'
                  : isMixed
                      ? mixedCashAmount <= 0
                          ? 'card'
                          : mixedCardAmount <= 0
                              ? 'cash'
                              : 'mixed'
                      : switch (posCubit.state.paymentKind) {
                          PaymentKind.cash => 'cash',
                          PaymentKind.card => 'card',
                          PaymentKind.credit => 'debt',
                        };
              final fiscalizationExpected = fiscalizationEnabled && !isDebtSale;

              final customerId = isDebtSale
                  ? selectedCustomer?.id.trim()
                  : posCubit.state.activeCustomer?.id.trim();

              final saleLocalId = const Uuid().v4();

              var sale = SaleModel(
                localId: saleLocalId,
                number: '',
                date: DateTime.now(),
                totalAmount: totalAmountInt,
                paymentMethod: paymentMethod,
                paymentType: isDebtSale ? paymentMethod : null,
                paidAmount: isDebtSale ? debtPaidNow : totalAmountInt,
                debtAmount: isDebtSale ? debtAmount : 0,
                paidPaymentMethod:
                    isDebtSale && debtPaidNow > 0 ? 'cash' : null,
                dueDate:
                    isDebtSale ? _defaultDebtDueDate(DateTime.now()) : null,
                comment: saleComment.isNotEmpty
                    ? saleComment
                    : isDebtSale
                        ? 'Продажа в долг'
                        : null,
                idempotencyKey:
                    '$posId-${DateTime.now().millisecondsSinceEpoch}-$saleLocalId',
                posId: posId,
                storeId: storeId,
                userId: userId,
                accountId: fallbackAccountId,
                posSessionId: auth.shiftId?.trim(),
                customerId: customerId,
                items: saleItems
                    .asMap()
                    .entries
                    .map(
                      (entry) => entry.value.copyWith(
                        product: ProductModel(
                          id: posCubit.state.items[entry.key].product.id,
                          name: posCubit.state.items[entry.key].product.name,
                          measurementUnit: posCubit
                              .state.items[entry.key].product.measurementUnit,
                          arrivalCost: posCubit
                              .state.items[entry.key].product.arrivalCost,
                          sellingPrice:
                              posCubit.state.items[entry.key].product.price,
                          wholesalePrice: 0,
                        ),
                      ),
                    )
                    .toList(),
              );

              // Load accounts to find cash/card account IDs
              final accounts = await sl<PosSyncService>().loadAccounts();
              final visibleAccounts =
                  accounts.where((account) => account.visibleToPos).toList();
              final cashAccount = visibleAccounts
                  .cast<LocalAccount?>()
                  .firstWhere((a) => a?.isCash ?? false, orElse: () => null);
              final bankAccounts = _bankAccounts.isNotEmpty
                  ? _bankAccounts
                  : visibleAccounts
                      .where((account) => account.normalizedType == 'bank')
                      .toList(growable: false);
              final cardAccount = _selectedBankAccount;

              final needsBankAccount =
                  paymentMethod == 'card' || paymentMethod == 'mixed';
              if (needsBankAccount && bankAccounts.isEmpty) {
                _showError(
                  'Не найден банковский счет. Обновите синхронизацию POS или настройте счет типа BANK.',
                );
                return;
              }

              if (needsBankAccount &&
                  (cardAccount?.id.trim().isEmpty ?? true)) {
                _showError('Выберите счет безналичной оплаты');
                return;
              }

              Map<String, dynamic> accountJson(LocalAccount account) => {
                    'id': account.id,
                    'name': account.name,
                    'type': account.type,
                    if ((account.logoUrl ?? '').trim().isNotEmpty)
                      'logo_url': account.logoUrl!.trim(),
                  };
              final posCashAccountJson = {
                'id': fallbackAccountId,
                'name': (cashAccount?.name.trim().isNotEmpty ?? false)
                    ? cashAccount!.name
                    : 'POS cash',
                'type': cashAccount?.type ?? 'POS',
              };

              sale = sale.copyWith(
                comment: saleComment.isNotEmpty
                    ? saleComment
                    : isDebtSale
                        ? 'РџСЂРѕРґР°Р¶Р° РІ РґРѕР»Рі'
                        : null,
              );

              final List<Map<String, dynamic>> payments;
              if (isDebtSale) {
                payments = debtPaidNow > 0
                    ? [
                        {
                          'account_id': fallbackAccountId,
                          'amount': debtPaidNow,
                          'client_payment_id': const Uuid().v4(),
                          'account': posCashAccountJson,
                        },
                      ]
                    : [];
              } else if (isMixed) {
                payments = [
                  if (mixedCashAmount > 0)
                    {
                      'account_id': fallbackAccountId,
                      'amount': mixedCashAmount,
                      'client_payment_id': const Uuid().v4(),
                      'account': posCashAccountJson,
                    },
                  if (mixedCardAmount > 0)
                    {
                      'account_id': cardAccount!.id,
                      'amount': mixedCardAmount,
                      'client_payment_id': const Uuid().v4(),
                      'account': accountJson(cardAccount),
                    },
                ];
              } else if (paymentMethod == 'card') {
                payments = [
                  {
                    'account_id': cardAccount!.id,
                    'amount': exactTotal,
                    'client_payment_id': const Uuid().v4(),
                    'account': accountJson(cardAccount),
                  },
                ];
              } else {
                payments = [
                  {
                    'account_id': fallbackAccountId,
                    'amount': exactTotal,
                    'client_payment_id': const Uuid().v4(),
                    'account': posCashAccountJson,
                  },
                ];
              }

              sale = sale.copyWith(
                payments: payments
                    .map((payment) => SalePaymentModel.fromJson(payment))
                    .toList(growable: false),
              );

              final repo = GetIt.I<SaleRepository>();

              setState(() {
                _paying = true;
                _paymentSuccess = false;
              });
              var saleCompleted = false;
              try {
                final pageFormat = auth.receiptPaperMm == 57
                    ? PdfPageFormat.roll57
                    : PdfPageFormat.roll80;
                final outcome = await repo.createSale(
                  key: key,
                  deviceId: deviceId,
                  sale: sale,
                  payments: payments,
                  requireOnline: isDebtSale ||
                      containsMarkedItems ||
                      fiscalizationExpected,
                );
                final result = outcome.result;
                final printedSale = outcome.sale;

                if (result == CreateSaleResult.rejected) {
                  final message = (outcome.errorMessage ?? '').trim();
                  final markedSale = containsMarkedItems;
                  if (outcome.errorCode == 'MARKING_CONFLICT' && mounted) {
                    setState(() => _markingConflictNeedsExtraCode = true);
                  }
                  if (markedSale && outcome.retryScheduled && mounted) {
                    setState(() => _saleQueued = true);
                  }
                  developer.log(
                    'Sale rejected. method=${sale.paymentMethod}, requireOnline=$isDebtSale, message=$message',
                    name: 'PaymentPanel',
                  );
                  _showError(
                    markedSale && outcome.retryScheduled
                        ? 'Продажа сохранена и будет повторена с тем же идентификатором. Повторно оплату не создавайте.'
                        : message.isEmpty
                            ? 'Продажа в долг не прошла. Проверьте интернет и настройки клиента.'
                            : message,
                  );
                  return;
                }

                var localReceiptPrinted = false;
                if (!mounted) return;
                final shouldPrintLocalReceipt =
                    await showReceiptPrintConfirmation(
                  this.context,
                  title: 'Распечатать чек продажи?',
                  message: 'Продажа успешно оформлена. Нужен бумажный чек?',
                );
                if (!mounted) return;
                if (shouldPrintLocalReceipt) {
                  final printedPaymentMethod =
                      printedSale.paymentMethod.trim().toLowerCase();
                  await _printService.print80mmSilently(
                    () => buildReceiptPdf(
                      ReceiptPdfData(
                        pageFormat: pageFormat,
                        money: money,
                        receiptDate: printedSale.date,
                        receiptNumber: formatPosReceiptNumber(
                          posNumber: auth.posNumber ?? '',
                          saleNumber: printedSale.number,
                          fallback: printedSale.localId,
                        ),
                        cashierName: (auth.activeUserName ?? '').trim().isEmpty
                            ? userId
                            : auth.activeUserName!.trim(),
                        storeName: (() {
                          final name = (auth.storeName ?? '').trim();
                          if (name.isNotEmpty) return name;
                          final posName = (auth.posName ?? '').trim();
                          if (posName.isNotEmpty) return posName;
                          return 'Магазин';
                        })(),
                        items: posCubit.state.items
                            .map(
                              (it) => ReceiptPdfItem(
                                name: it.product.name,
                                quantity: it.qty,
                                unitPrice: it.effectiveUnitPrice,
                                lineTotal: it.sum,
                                discountPercent: it.effectiveDiscountPercent,
                              ),
                            )
                            .toList(),
                        total: posCubit.total,
                        discountSum: posCubit.discountSum,
                        paymentMethodLabel: _normalizePaymentMethodLabel(
                            printedSale.paymentMethod),
                        isCashPayment: printedPaymentMethod == 'cash',
                        received: isDebtSale
                            ? printedSale.paidAmount
                            : posCubit.state.received,
                        change: isDebtSale ? 0 : posCubit.change,
                        customerName: selectedCustomer?.name,
                        previousDebt:
                            isDebtSale ? selectedCustomer?.balance : null,
                        newDebt: isDebtSale
                            ? (selectedCustomer?.balance ?? 0) +
                                printedSale.debtAmount
                            : null,
                        debtAmount: isDebtSale ? printedSale.debtAmount : null,
                        paidNow: isDebtSale ? printedSale.paidAmount : null,
                        documentTitle: isDebtSale ? 'ПРОДАЖА В ДОЛГ' : null,
                      ),
                    ),
                    printerName: auth.receiptPrinterName,
                  );
                  localReceiptPrinted = true;
                }

                final fiscalService = sl<FiscalReceiptService>();
                final fiscalReceipt = fiscalizationExpected
                    ? fiscalService.fromSaleResponse(outcome.responseData)
                    : null;
                if (fiscalizationExpected && fiscalReceipt != null) {
                  await fiscalService.save(
                    fiscalReceipt,
                    localReceiptPrinted: localReceiptPrinted,
                    saleIds: {
                      sale.localId,
                      printedSale.localId,
                      (outcome.responseData?['id'] ?? '').toString(),
                    },
                  );
                  fiscalService.startBackgroundPolling(
                    key: key,
                    deviceId: deviceId,
                    receipt: fiscalReceipt,
                  );
                  if (!mounted) return;
                  await showDialog<void>(
                    context: this.context,
                    barrierDismissible: false,
                    builder: (_) => FiscalReceiptDialog(
                      initial: fiscalReceipt,
                      posKey: key,
                      deviceId: deviceId,
                      paperMm: auth.receiptPaperMm,
                      printerName: auth.receiptPrinterName,
                    ),
                  );
                } else if (fiscalizationExpected && outcome.retryScheduled) {
                  _showError(
                    'Продажа сохранена локально. Фискальный чек станет доступен после синхронизации с backend.',
                  );
                } else if (fiscalizationExpected &&
                    !(outcome.responseData?.containsKey('fiscal_receipt') ??
                        false)) {
                  _showError(
                    'Продажа сохранена, но backend не вернул фискальный чек. Повторно продажу не создавайте — обратитесь к администратору.',
                  );
                }

                if (!context.mounted) return;
                saleCompleted = true;
                lastSaleAmountNotifier.value = printedSale.totalAmount;
                setState(() {
                  _paying = false;
                  _paymentSuccess = true;
                });
                await Future.delayed(const Duration(milliseconds: 950));
                if (!mounted) return;
                Navigator.of(this.context).pop();
                _commentCtrl.clear();
                posCubit.clearAfterPayment();
              } catch (_) {
                _showError('Не удалось провести оплату');
              } finally {
                if (mounted && !saleCompleted) {
                  setState(() => _paying = false);
                }
              }
            }

            bool useCardInput() {
              if (_isMixedPayment) return _mixedActiveIsCard;
              return state.paymentKind == PaymentKind.card;
            }

            String activeText() {
              return useCardInput() ? _cardCtrl.text : _cashCtrl.text;
            }

            String complementText(String text) {
              final amount = _parseAmount(text).clamp(0, total).toDouble();
              return _fmt(
                (total - amount).clamp(0, double.infinity).toDouble(),
              );
            }

            String normalizeAmountText(String text) {
              final normalized = text.replaceAll(',', '.').trim();
              if (normalized.isEmpty) return '0';
              if (normalized == '.') return '0.';
              if (normalized.startsWith('.')) return '0$normalized';
              return normalized.replaceFirst(RegExp(r'^0+(?=\d)'), '');
            }

            String limitedAmountText(String text) {
              final normalized = normalizeAmountText(text);
              if (normalized.isEmpty ||
                  normalized == '0.' ||
                  normalized == '.') {
                return normalized;
              }

              final amount = _parseAmount(normalized);
              if (amount <= total) return normalized;
              return _fmt(total);
            }

            void placeCashCursorAtEnd() {
              _cashCtrl.selection = TextSelection.collapsed(
                offset: _cashCtrl.text.length,
              );
            }

            void setMixedCashText(String text) {
              final limitedText = limitedAmountText(text);
              _setText(context, limitedText, applyToState: false);
              _setCardText(
                context,
                complementText(limitedText),
                applyToState: false,
              );
              cubit.setReceived(total);
            }

            void setMixedCardText(String text) {
              final limitedText = limitedAmountText(text);
              _setCardText(context, limitedText, applyToState: false);
              _setText(
                context,
                complementText(limitedText),
                applyToState: false,
              );
              cubit.setReceived(total);
            }

            void setActiveText(String text) {
              if (!_isMixedPayment && state.paymentKind == PaymentKind.card) {
                return;
              }

              if (_isMixedPayment && useCardInput()) {
                setMixedCardText(text);
                _cardFocusNode.requestFocus();
                return;
              }

              if (_isMixedPayment) {
                setMixedCashText(text);
                _cashFocusNode.requestFocus();
                return;
              }

              if (useCardInput()) {
                _setCardText(context, text);
                _cardFocusNode.requestFocus();
              } else {
                _setText(context, text);
                _cashFocusNode.requestFocus();
              }
            }

            void addQuick(int inc) {
              final curr =
                  double.tryParse(activeText().replaceAll(',', '.')) ?? 0;
              final next = _isMixedPayment
                  ? (curr + inc).clamp(0, total).toDouble()
                  : curr + inc;
              setActiveText(_fmt(next));
            }

            void appendToken(String token) {
              var t = activeText();

              if (token == '⌫') {
                if (t.isNotEmpty) t = t.substring(0, t.length - 1);
                setActiveText(t);
                return;
              }

              if (token == 'C') {
                setActiveText('');
                return;
              }

              if (token == '.') {
                if (!t.contains('.')) {
                  t = t.isEmpty ? '0.' : '$t.';
                }
                setActiveText(t);
                return;
              }

              t = t == '0' ? token : '$t$token';

              t = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
              setActiveText(t);
            }

            final customerName = state.activeCustomer?.name.trim();
            final customerButtonText =
                (customerName != null && customerName.isNotEmpty)
                    ? customerName
                    : 'ПОКУПАТЕЛЬ';
            final hasSelectedCustomer = state.activeCustomer != null;
            final currentDebt = state.activeCustomer?.balance.toDouble() ?? 0;
            final debtLimit = state.activeCustomer?.debtLimit.toDouble() ?? 0;
            final debtPaidNow = isDebtSale
                ? _parseAmount(_cashCtrl.text).clamp(0, total).toDouble()
                : 0.0;
            final projectedDebt =
                isDebtSale ? currentDebt + (total - debtPaidNow) : currentDebt;
            return Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter):
                    ActivateIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      submitPayment();
                      return null;
                    },
                  ),
                },
                child: Focus(
                  autofocus: true,
                  child: DefaultTextStyle(
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 3.12695,
                          top: 0,
                          width: 566,
                          height: 531.296,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F2),
                              borderRadius: BorderRadius.circular(15.6354),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 3.12695,
                          top: 0,
                          width: 566,
                          height: 83.976,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF373D46),
                              borderRadius: BorderRadius.circular(10.163),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14.8535,
                          top: 12.9858,
                          width: 203.26,
                          height: 57.1383,
                          child: _TopAmountBox(
                            label: 'К оплате',
                            value: money(total),
                          ),
                        ),
                        Positioned(
                          left: 230.622,
                          top: 12.9858,
                          width: 159.481,
                          height: 57.1383,
                          child: _TopAmountBox(
                            label: 'Получено',
                            value: money(state.received),
                          ),
                        ),
                        Positioned(
                          left: 401.829,
                          top: 13.29,
                          width: 154.008,
                          height: 57.0691,
                          child: _TopAmountBox(
                            label: 'Сдача',
                            value: money(change),
                          ),
                        ),
                        Positioned(
                          left: 14.8535,
                          top: 96.939,
                          width: 541.765,
                          height: 34.3978,
                          child: _PaymentTabs(
                            paymentKind: state.paymentKind,
                            mixed: _isMixedPayment,
                            onCash: () {
                              setState(() {
                                _isMixedPayment = false;
                                _mixedActiveIsCard = false;
                              });
                              cubit.setPaymentKind(PaymentKind.cash);
                              _cashFocusNode.requestFocus();
                            },
                            onCard: () {
                              setState(() {
                                _isMixedPayment = false;
                                _mixedActiveIsCard = false;
                                _selectedBankAccountId =
                                    _bankAccounts.length == 1
                                        ? _bankAccounts.single.id
                                        : null;
                              });
                              cubit.setPaymentKind(PaymentKind.card);
                              _setCardText(context, _fmt(total));
                              if (_bankAccounts.isEmpty) _loadBankAccounts();
                              _cardFocusNode.requestFocus();
                            },
                            onMixed: () {
                              setState(() {
                                _isMixedPayment = true;
                                _mixedActiveIsCard = false;
                                _selectedBankAccountId =
                                    _bankAccounts.length == 1
                                        ? _bankAccounts.single.id
                                        : null;
                              });
                              cubit.setPaymentKind(PaymentKind.cash);
                              if (_bankAccounts.isEmpty) _loadBankAccounts();
                              _setText(context, '0', applyToState: false);
                              _setCardText(context, '0', applyToState: false);
                              cubit.setReceived(0);
                              _cashFocusNode.requestFocus();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted || !_isMixedPayment) return;
                                placeCashCursorAtEnd();
                              });
                            },
                          ),
                        ),
                        if (state.paymentKind != PaymentKind.card ||
                            _isMixedPayment)
                          Positioned(
                            left: 15.3536,
                            top: 143.564,
                            width: _isMixedPayment ? 271.055 : 540.766,
                            height: 46.6278,
                            child: _BlueInput(
                              label: 'Наличный счет',
                              controller: _cashCtrl,
                              focusNode: _cashFocusNode,
                              onTap: () {
                                if (_isMixedPayment) {
                                  setState(() => _mixedActiveIsCard = false);
                                }
                              },
                              onChanged: (v) {
                                if (_isMixedPayment) {
                                  _mixedActiveIsCard = false;
                                  setMixedCashText(v);
                                  return;
                                }
                                _applyTextToState(context, v);
                              },
                              onSubmitted: (_) => submitPayment(),
                              borderColor: const Color(0xFF999999),
                            ),
                          ),
                        if (state.paymentKind == PaymentKind.card ||
                            _isMixedPayment)
                          Positioned(
                            left: _isMixedPayment ? 297.572 : 15.3536,
                            top: 143.564,
                            width: _isMixedPayment ? 258.547 : 540.766,
                            height: 46.6278,
                            child: _BlueInput(
                              label: 'Безналичный счет',
                              controller: _cardCtrl,
                              focusNode: _cardFocusNode,
                              readOnly: !_isMixedPayment,
                              onTap: () {
                                if (_isMixedPayment) {
                                  setState(() => _mixedActiveIsCard = true);
                                }
                              },
                              onChanged: (v) {
                                if (_isMixedPayment) {
                                  _mixedActiveIsCard = true;
                                  setMixedCardText(v);
                                }
                              },
                              onSubmitted: (_) => submitPayment(),
                              borderColor: const Color(0xFF00A1FF),
                            ),
                          ),
                        _KeypadButtonPositioned(
                          left: 14.8535,
                          top: 208.732,
                          text: '7',
                          onTap: () => appendToken('7'),
                        ),
                        _KeypadButtonPositioned(
                          left: 85.1592,
                          top: 208.732,
                          text: '8',
                          onTap: () => appendToken('8'),
                        ),
                        _KeypadButtonPositioned(
                          left: 155.466,
                          top: 208.732,
                          text: '9',
                          onTap: () => appendToken('9'),
                        ),
                        _KeypadButtonPositioned(
                          left: 225.773,
                          top: 208.732,
                          text: 'C',
                          fg: const Color(0xFFFF5B5B),
                          onTap: () => appendToken('C'),
                        ),
                        _KeypadButtonPositioned(
                          left: 14.8535,
                          top: 279.038,
                          text: '4',
                          onTap: () => appendToken('4'),
                        ),
                        _KeypadButtonPositioned(
                          left: 85.1592,
                          top: 279.038,
                          text: '5',
                          onTap: () => appendToken('5'),
                        ),
                        _KeypadButtonPositioned(
                          left: 155.466,
                          top: 279.038,
                          text: '6',
                          onTap: () => appendToken('6'),
                        ),
                        _KeypadButtonPositioned(
                          left: 225.773,
                          top: 279.038,
                          text: 'Скидка',
                          fontSize: 12,
                          onTap: () {},
                        ),
                        _KeypadButtonPositioned(
                          left: 14.8535,
                          top: 349.344,
                          text: '1',
                          onTap: () => appendToken('1'),
                        ),
                        _KeypadButtonPositioned(
                          left: 85.1592,
                          top: 349.344,
                          text: '2',
                          onTap: () => appendToken('2'),
                        ),
                        _KeypadButtonPositioned(
                          left: 155.466,
                          top: 349.344,
                          text: '3',
                          onTap: () => appendToken('3'),
                        ),
                        _KeypadButtonPositioned(
                          left: 225.773,
                          top: 349.344,
                          text: 'Счет на\nоплату',
                          fontSize: 11,
                          onTap: () {},
                        ),
                        _KeypadButtonPositioned(
                          left: 14.8535,
                          top: 419.651,
                          icon: Icons.backspace,
                          fg: const Color(0xFF33CC99),
                          onTap: () => appendToken('⌫'),
                        ),
                        _KeypadButtonPositioned(
                          left: 85.1592,
                          top: 419.651,
                          text: '0',
                          onTap: () => appendToken('0'),
                        ),
                        _KeypadButtonPositioned(
                          left: 155.466,
                          top: 419.65,
                          text: '.',
                          onTap: () => appendToken('.'),
                        ),
                        _KeypadButtonPositioned(
                          left: 225.773,
                          top: 419.65,
                          text: 'Наклад',
                          fontSize: 11,
                          onTap: () {},
                        ),
                        if (!isDebtSale) ...[
                          if (state.paymentKind == PaymentKind.cash &&
                              !_isMixedPayment) ...[
                            Positioned(
                              left: 299.417,
                              top: 208.732,
                              width: 121.306,
                              height: 46.4758,
                              child: _WhiteButton(
                                text: '+1 000',
                                onTap: () => addQuick(1000),
                              ),
                            ),
                            Positioned(
                              left: 435.312,
                              top: 208.732,
                              width: 121.306,
                              height: 46.4758,
                              child: _WhiteButton(
                                text: '+2 000',
                                onTap: () => addQuick(2000),
                              ),
                            ),
                            Positioned(
                              left: 299.417,
                              top: 267.794,
                              width: 121.306,
                              height: 46.4758,
                              child: _WhiteButton(
                                text: '+5 000',
                                onTap: () => addQuick(5000),
                              ),
                            ),
                            Positioned(
                              left: 435.312,
                              top: 267.794,
                              width: 121.306,
                              height: 46.4758,
                              child: _WhiteButton(
                                text: '+10 000',
                                onTap: () => addQuick(10000),
                              ),
                            ),
                          ] else
                            Positioned(
                              left: 299.417,
                              top: 208.732,
                              width: 257.201,
                              height: 105.538,
                              child: _BankAccountButtons(
                                accounts: _bankAccounts,
                                selectedId: _selectedBankAccountId,
                                loading: _loadingBankAccounts,
                                onSelected: (id) {
                                  setState(() => _selectedBankAccountId = id);
                                },
                              ),
                            ),
                        ] else
                          Positioned(
                            left: 299.417,
                            top: 208.732,
                            width: 257.201,
                            height: 105.538,
                            child: _DebtSummaryBox(
                              customerName: customerButtonText,
                              currentDebt: currentDebt,
                              debtLimit: debtLimit,
                              saleAmount: total,
                              paidNow: debtPaidNow,
                              projectedDebt: projectedDebt,
                              money: money,
                              debtAllowed:
                                  state.activeCustomer?.debtAllowed ?? false,
                            ),
                          ),
                        Positioned(
                          left: 299.934,
                          top: 323.387,
                          width: 256.169,
                          height: 29.1575,
                          child: Row(
                            children: [
                              Expanded(
                                child: _WhiteButton(
                                  text: customerButtonText,
                                  onTap: _pickCustomer,
                                  borderRadius: 4.64873,
                                  borderColor: Colors.black,
                                ),
                              ),
                              if (hasSelectedCustomer) ...[
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 30,
                                  height: 29.1575,
                                  child: _CustomerClearButton(
                                    onTap: () =>
                                        cubit.clearCustomerForActiveTicket(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Positioned(
                          left: 299.417,
                          top: 360.838,
                          width: 95.1073,
                          height: 49.4316,
                          child: _GreyButton(
                            text: 'В ДОЛГ',
                            onTap: hasItems
                                ? () {
                                    if (hasMarkedItems) {
                                      _showError(
                                        'Маркированный товар нельзя продавать в долг',
                                      );
                                      return;
                                    }
                                    setState(() {
                                      _isMixedPayment = false;
                                      _mixedActiveIsCard = false;
                                    });
                                    cubit.setPaymentKind(PaymentKind.credit);
                                  }
                                : null,
                            selected: state.paymentKind == PaymentKind.credit,
                          ),
                        ),
                        Positioned(
                          left: 402.61,
                          top: 360.838,
                          width: 154.008,
                          height: 49.3467,
                          child: _GreyButton(
                            text: 'БЕЗ СДАЧИ',
                            onTap: () {
                              cubit.setPaymentKind(PaymentKind.cash);
                              _setText(context, _fmt(total));
                              _cashFocusNode.requestFocus();
                            },
                            selected: state.paymentKind == PaymentKind.cash &&
                                !_isMixedPayment &&
                                state.received >= total,
                          ),
                        ),
                        Positioned(
                          left: 299.417,
                          top: 417.977,
                          width: 95.1073,
                          height: 61.5518,
                          child: _BottomButton(
                            text: 'ОТМЕНА',
                            bg: const Color(0xFFD15850),
                            fg: Colors.white,
                            onTap: () {
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        Positioned(
                          left: 402.61,
                          top: 418.842,
                          width: 154.008,
                          height: 59.7355,
                          child: _BottomButton(
                            text: 'ОПЛАТА',
                            bg: const Color(0xFF33CC99),
                            disabledBg: const Color(0xFFA8DABD),
                            successBg: const Color(0xFF179D72),
                            fg: Colors.white,
                            loading: _paying,
                            success: _paymentSuccess,
                            onTap: canSubmitPayment && !_paymentSuccess
                                ? submitPayment
                                : null,
                          ),
                        ),
                        Positioned(
                          left: 14.8535,
                          top: 489.5,
                          width: 541,
                          height: 35,
                          child: _InlineSaleCommentField(
                            controller: _commentCtrl,
                            focusNode: _commentFocusNode,
                            onOpenKeyboard: _showCommentKeyboard,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopAmountBox extends StatelessWidget {
  const _TopAmountBox({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.806),
      ),
      padding: const EdgeInsets.fromLTRB(9, 7, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              height: 1,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingDebtCustomerDialog extends StatelessWidget {
  const _MissingDebtCustomerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, 18),
                color: Color(0x33000000),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
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
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B),
                          width: 1.1,
                        ),
                      ),
                      child: const Icon(
                        Icons.person_search_rounded,
                        color: Color(0xFFEA580C),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Выберите покупателя',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Для продажи в долг нужно указать покупателя. После выбора можно продолжить оплату.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Закрыть',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(
                            'Выбрать',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF33CC99),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
  }
}

class _DebtSummaryBox extends StatelessWidget {
  const _DebtSummaryBox({
    required this.customerName,
    required this.currentDebt,
    required this.debtLimit,
    required this.saleAmount,
    required this.paidNow,
    required this.projectedDebt,
    required this.money,
    required this.debtAllowed,
  });

  final String customerName;
  final double currentDebt;
  final double debtLimit;
  final double saleAmount;
  final double paidNow;
  final double projectedDebt;
  final String Function(num) money;
  final bool debtAllowed;

  @override
  Widget build(BuildContext context) {
    final hasCustomer =
        customerName.trim().isNotEmpty && customerName.trim() != 'ПОКУПАТЕЛЬ';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
      ),
      child: DefaultTextStyle(
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF7C2D12),
          height: 1.2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasCustomer ? customerName : 'Клиент не выбран',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF9A3412),
              ),
            ),
            const SizedBox(height: 6),
            Text('Текущий долг: ${money(currentDebt)}'),
            Text(
                'Лимит долга: ${debtLimit > 0 ? money(debtLimit) : "Без лимита"}'),
            Text('Сумма продажи: ${money(saleAmount)}'),
            Text('Оплачено сейчас: ${money(paidNow)}'),
            Text(
              'Итоговый долг: ${money(projectedDebt)}'
              '${debtAllowed ? "" : "  •  запрет"}',
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTabs extends StatelessWidget {
  const _PaymentTabs({
    required this.paymentKind,
    required this.mixed,
    required this.onCash,
    required this.onCard,
    required this.onMixed,
  });

  final PaymentKind paymentKind;
  final bool mixed;
  final VoidCallback onCash;
  final VoidCallback onCard;
  final VoidCallback onMixed;

  static const double _tabHeight = 34.3978;
  static const double _dividerTop = 4;
  static const double _dividerHeight = 26;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9.002),
        border: Border.all(color: const Color(0xFFD9E1DC), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9.002),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            if (mixed || paymentKind != PaymentKind.credit)
              Positioned(
                left: mixed
                    ? 351.795
                    : paymentKind == PaymentKind.cash
                        ? 0
                        : 180.59,
                top: 0,
                width: mixed
                    ? 189.97
                    : paymentKind == PaymentKind.cash
                        ? 180.59
                        : 171.205,
                height: _tabHeight,
                child: const ColoredBox(color: Color(0xFF33CC99)),
              ),
            const Positioned(
              left: 180.59,
              top: _dividerTop,
              width: 0.7818,
              height: _dividerHeight,
              child: ColoredBox(color: Color(0xFFB6B6B6)),
            ),
            const Positioned(
              left: 351.795,
              top: _dividerTop,
              width: 0.7818,
              height: _dividerHeight,
              child: ColoredBox(color: Color(0xFFB6B6B6)),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: _PaymentTabButton(
                      text: 'Наличные',
                      selected: !mixed && paymentKind == PaymentKind.cash,
                      onTap: onCash,
                    ),
                  ),
                  Expanded(
                    child: _PaymentTabButton(
                      text: 'Безналичные',
                      selected: !mixed && paymentKind == PaymentKind.card,
                      onTap: onCard,
                    ),
                  ),
                  Expanded(
                    child: _PaymentTabButton(
                      text: 'Смешенная',
                      selected: mixed,
                      onTap: onMixed,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTabButton extends StatelessWidget {
  const _PaymentTabButton({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          foregroundColor: selected ? Colors.white : Colors.black,
          minimumSize: Size.zero,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _SalePaymentDetails {
  const _SalePaymentDetails({
    required this.comment,
    this.bankAccount,
  });

  final String comment;
  final LocalAccount? bankAccount;
}

class _SalePaymentDetailsDialog extends StatefulWidget {
  const _SalePaymentDetailsDialog({
    required this.bankAccounts,
    required this.requireBankAccount,
  });

  final List<LocalAccount> bankAccounts;
  final bool requireBankAccount;

  @override
  State<_SalePaymentDetailsDialog> createState() =>
      _SalePaymentDetailsDialogState();
}

class _SalePaymentDetailsDialogState extends State<_SalePaymentDetailsDialog> {
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  OverlayEntry? _keyboardEntry;
  LocalAccount? _selectedBankAccount;

  @override
  void initState() {
    super.initState();
    _commentCtrl.addListener(_capitalizeComment);
    if (widget.requireBankAccount && widget.bankAccounts.isNotEmpty) {
      _selectedBankAccount = widget.bankAccounts.first;
    }
  }

  @override
  void dispose() {
    _hideKeyboard();
    _commentCtrl.removeListener(_capitalizeComment);
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _capitalizeComment() {
    capitalizeFirstLetterInController(_commentCtrl);
  }

  void _ensureSelection() {
    final selection = _commentCtrl.selection;
    if (selection.isValid) return;
    _commentCtrl.selection =
        TextSelection.collapsed(offset: _commentCtrl.text.length);
  }

  void _showKeyboard() {
    _commentFocus.requestFocus();
    _ensureSelection();
    if (_keyboardEntry != null) return;

    _keyboardEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _commentCtrl,
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

  void _submit() {
    final comment = _commentCtrl.text.trim();
    if (comment.length > 1000) return;
    if (widget.requireBankAccount && _selectedBankAccount == null) return;

    Navigator.of(context).pop(
      _SalePaymentDetails(
        comment: comment,
        bankAccount: _selectedBankAccount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        !widget.requireBankAccount || _selectedBankAccount != null;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1ED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Color(0xFF456B5A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.requireBankAccount
                          ? 'Детали безналичной оплаты'
                          : 'Комментарий к оплате',
                      style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.requireBankAccount) ...[
                const SizedBox(height: 16),
                Text(
                  'Банковский счет',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.bankAccounts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final account = widget.bankAccounts[index];
                        final selected = account.id == _selectedBankAccount?.id;
                        final title = account.name.trim().isEmpty
                            ? 'Банк ${account.id}'
                            : account.name.trim();

                        return Material(
                          color: selected
                              ? const Color(0xFFEAF7F1)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () =>
                                setState(() => _selectedBankAccount = account),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF33CC99)
                                      : const Color(0xFFE2E8F0),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: selected
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Tooltip(
                                      message: title,
                                      child: _BankAccountLogoOrName(
                                        account: account,
                                      ),
                                    ),
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
              ],
              const SizedBox(height: 16),
              Text(
                'Комментарий',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 112,
                child: _SaleCommentBox(
                  controller: _commentCtrl,
                  focusNode: _commentFocus,
                  onOpenKeyboard: _showKeyboard,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSubmit ? _submit : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        backgroundColor: const Color(0xFF33CC99),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFA8DABD),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Продолжить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankAccountButtons extends StatelessWidget {
  const _BankAccountButtons({
    required this.accounts,
    required this.selectedId,
    required this.loading,
    required this.onSelected,
  });

  final List<LocalAccount> accounts;
  final String? selectedId;
  final bool loading;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (accounts.isEmpty) {
      return _BankEmptyBox(onTap: () {});
    }

    final effectiveSelectedId =
        accounts.any((account) => account.id == selectedId) ? selectedId : null;

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: accounts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 14,
        childAspectRatio: 2.62,
      ),
      itemBuilder: (context, index) {
        final account = accounts[index];
        final name = account.name.trim().isEmpty
            ? 'Банк ${account.id}'
            : account.name.trim();
        final selected = account.id == effectiveSelectedId;

        return _BankNameButton(
          name: name,
          account: account,
          selected: selected,
          onTap: () => onSelected(account.id),
        );
      },
    );
  }
}

class _BankNameButton extends StatelessWidget {
  const _BankNameButton({
    required this.name,
    required this.selected,
    required this.onTap,
    this.account,
  });

  final String name;
  final LocalAccount? account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.69061),
          side: BorderSide(
            color: selected ? const Color(0xFF33CC99) : Colors.transparent,
            width: selected ? 1.3 : 0,
          ),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Tooltip(
        message: name,
        child: account == null
            ? _BankAccountNameText(name: name)
            : _BankAccountLogoOrName(account: account!),
      ),
    );
  }
}

class _BankAccountLogoOrName extends StatelessWidget {
  const _BankAccountLogoOrName({
    required this.account,
  });

  final LocalAccount account;

  @override
  Widget build(BuildContext context) {
    final name = account.name.trim().isEmpty
        ? 'Банк ${account.id}'
        : account.name.trim();
    final logoUrl = (account.logoUrl ?? '').trim();
    if (logoUrl.isEmpty) {
      return _BankAccountNameText(name: name);
    }

    return Padding(
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3.5),
        child: SizedBox.expand(
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => _BankAccountNameText(name: name),
          ),
        ),
      ),
    );
  }
}

class _BankAccountNameText extends StatelessWidget {
  const _BankAccountNameText({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Colors.black,
        height: 1,
      ),
    );
  }
}

class _BankEmptyBox extends StatelessWidget {
  const _BankEmptyBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BankNameButton(
      name: 'Банк',
      selected: false,
      onTap: onTap,
    );
  }
}

class _InlineSaleCommentField extends StatelessWidget {
  const _InlineSaleCommentField({
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
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF999999), width: 1),
      ),
      child: Stack(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 1,
            readOnly: true,
            showCursor: true,
            textAlign: TextAlign.left,
            textAlignVertical: TextAlignVertical.center,
            inputFormatters: [
              LengthLimitingTextInputFormatter(1000),
            ],
            decoration: InputDecoration(
              hintText:
                  '\u041a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0439',
              counterText: '',
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 42, 6),
              hintStyle: GoogleFonts.inter(
                fontSize: 12.76,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF999999),
                height: 1,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: 12.76,
              fontWeight: FontWeight.w500,
              color: Colors.black,
              height: 1,
            ),
          ),
          Positioned(
            right: 4,
            top: 1,
            bottom: 1,
            child: IconButton(
              tooltip:
                  '\u041a\u043b\u0430\u0432\u0438\u0430\u0442\u0443\u0440\u0430',
              onPressed: onOpenKeyboard,
              icon: const Icon(
                Icons.keyboard_alt_outlined,
                color: Color(0xFF999999),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BottomSaleCommentField extends StatelessWidget {
  const _BottomSaleCommentField({
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
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF999999), width: 1),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 1,
        textAlign: TextAlign.left,
        textAlignVertical: TextAlignVertical.center,
        onTap: onOpenKeyboard,
        inputFormatters: [
          LengthLimitingTextInputFormatter(1000),
        ],
        decoration: InputDecoration(
          hintText: 'Комментарий',
          counterText: '',
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 36, 10),
          hintStyle: GoogleFonts.inter(
            fontSize: 12.76,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF999999),
            height: 1,
          ),
        ),
        style: GoogleFonts.inter(
          fontSize: 12.76,
          fontWeight: FontWeight.w500,
          color: Colors.black,
          height: 1,
        ),
      ),
    );
  }
}

class _CommentKeyboardPreview extends StatelessWidget {
  const _CommentKeyboardPreview({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      minimum: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF33CC99), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 17,
              color: Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final text = controller.text.trim();
                  return Text(
                    text.isEmpty ? 'Комментарий' : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: text.isEmpty
                          ? const Color(0xFF999999)
                          : const Color(0xFF111827),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 25),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _InlineBankAccountSelect extends StatelessWidget {
  const _InlineBankAccountSelect({
    required this.accounts,
    required this.selectedId,
    required this.loading,
    required this.onChanged,
  });

  final List<LocalAccount> accounts;
  final String? selectedId;
  final bool loading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00A1FF), width: 1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: loading
                ? Text(
                    'Загрузка счетов...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedId,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      hint: Text(
                        accounts.isEmpty ? 'Нет счетов bank' : 'Счет',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      items: accounts
                          .map(
                            (account) => DropdownMenuItem<String>(
                              value: account.id,
                              child: Text(
                                account.name.trim().isEmpty
                                    ? 'Банк ${account.id}'
                                    : account.name.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: accounts.isEmpty ? null : onChanged,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SaleCommentBox extends StatelessWidget {
  const _SaleCommentBox({
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
        borderRadius: BorderRadius.circular(8.502),
        border: Border.all(color: const Color(0xFF00A1FF), width: 1),
      ),
      child: Stack(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLength: 1000,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            inputFormatters: [
              LengthLimitingTextInputFormatter(1000),
            ],
            decoration: InputDecoration(
              hintText: 'Комментарий к продаже',
              counterText: '',
              hintStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF999999),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(
                10,
                10,
                42,
                10,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              height: 1.15,
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: IconButton(
              tooltip: 'Клавиатура',
              onPressed: onOpenKeyboard,
              icon: const Icon(
                Icons.keyboard_alt_outlined,
                color: Color(0xFF999999),
                size: 24,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueInput extends StatelessWidget {
  const _BlueInput({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.borderColor,
    this.readOnly = false,
    this.onTap,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final Color borderColor;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, child) {
        final focused = focusNode.hasFocus;
        final effectiveBorder = focused ? const Color(0xFF33CC99) : borderColor;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: focused ? const Color(0xFFF8FFFC) : Colors.white,
            borderRadius: BorderRadius.circular(8.502),
            border: Border.all(
              color: effectiveBorder.withValues(alpha: focused ? 0.9 : 0.65),
              width: focused ? 1.2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: const Color(0xFF33CC99).withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 7,
            child: AnimatedBuilder(
              animation: focusNode,
              builder: (context, _) {
                return Text(
                  label,
                  style: GoogleFonts.inter(
                    color: focusNode.hasFocus
                        ? const Color(0xFF168F6A)
                        : const Color(0xFF8A8A8A),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    height: 1,
                  ),
                );
              },
            ),
          ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: false,
            readOnly: readOnly,
            enableInteractiveSelection: false,
            contextMenuBuilder: null,
            onTap: () {
              onTap?.call();
              final text = controller.text;
              controller.selection = TextSelection.collapsed(
                offset: text.length,
              );
            },
            onChanged: (value) {
              onChanged(value);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!focusNode.hasFocus) return;
                final text = controller.text;
                if (controller.selection.isCollapsed &&
                    controller.selection.baseOffset == text.length) {
                  return;
                }
                controller.selection = TextSelection.collapsed(
                  offset: text.length,
                );
              });
            },
            onSubmitted: onSubmitted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(8, 17, 13, 0),
            ),
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeypadButtonPositioned extends StatelessWidget {
  const _KeypadButtonPositioned({
    required this.left,
    required this.top,
    required this.onTap,
    this.text,
    this.icon,
    this.fg = Colors.black,
    this.fontSize = 18,
  });

  final double left;
  final double top;
  final String? text;
  final IconData? icon;
  final Color fg;
  final double fontSize;
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
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: fg,
                  height: 1.05,
                ),
              )
            : Icon(icon, size: 20, color: fg),
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({
    required this.text,
    required this.onTap,
    this.borderRadius = 4.69061,
    this.borderColor,
  });

  final String text;
  final VoidCallback onTap;
  final double borderRadius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!, width: 1.033),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          height: 1,
        ),
      ),
    );
  }
}

class _CustomerClearButton extends StatelessWidget {
  const _CustomerClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Убрать покупателя',
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFFD15850),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.64873),
            side: const BorderSide(color: Color(0xFFD15850), width: 1.033),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: const Icon(
          Icons.close_rounded,
          size: 20,
          color: Color(0xFFD15850),
        ),
      ),
    );
  }
}

class _GreyButton extends StatelessWidget {
  const _GreyButton({
    required this.text,
    required this.onTap,
    this.selected = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFB7791F) : const Color(0xFFBBBBBB);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6.806),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        text,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.text,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.disabledBg,
    this.successBg,
    this.loading = false,
    this.success = false,
  });

  final String text;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final Color? disabledBg;
  final Color? successBg;
  final bool loading;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: TextButton(
        onPressed: onTap,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (success) {
              return successBg ?? bg;
            }
            if (states.contains(WidgetState.disabled)) {
              return disabledBg ?? bg;
            }
            return bg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return fg.withValues(alpha: 0.88);
            }
            return fg;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          ),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: loading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : success
                  ? Row(
                      key: const ValueKey('success'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'ГОТОВО',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      key: const ValueKey('idle'),
                      text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
        ),
      ),
    );
  }
}
