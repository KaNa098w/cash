import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_cubit.dart';
import 'package:leemon_app/features/presentation/pages/auth/auth_bloc/auth_state.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

class CloseShiftPage extends StatefulWidget {
  const CloseShiftPage({super.key});

  @override
  State<CloseShiftPage> createState() => _CloseShiftPageState();
}

class _CloseShiftPageState extends State<CloseShiftPage> {
  final _ctrl = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _shortageCommentCtrl = TextEditingController();
  final _shortageCommentFocusNode = FocusNode();
  OverlayEntry? _shortageCommentKeyboardEntry;

  bool _submitting = false;
  bool _showSuccessState = false;
  bool _showConfirmDialog = false;
  bool _printingReport = false;
  bool _shortageCommentKeyboardOpen = false;
  String? _shortageCommentError;

  late final Future<ShiftClosureSummaryData?> _summaryFuture;

  @override
  void initState() {
    super.initState();
    final sessionId = context.read<AuthTokenProvider>().shiftId?.trim() ?? '';
    _summaryFuture = sessionId.isEmpty
        ? Future<ShiftClosureSummaryData?>.value(null)
        : _loadClosureSummary(sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAmountInput();
    });
  }

  Future<ShiftClosureSummaryData?> _loadClosureSummary(String sessionId) async {
    final auth = context.read<AuthTokenProvider>();
    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final sync = GetIt.I<PosSyncService>();
    if (key.isEmpty) {
      throw Exception(
          'posKey отсутствует: невозможно загрузить итоги с бэка');
    }
    if (deviceId.isEmpty) {
      throw Exception(
          'deviceId отсутствует: невозможно загрузить итоги с бэка');
    }
    return sync.loadShiftClosureSummaryFromBackend(
      key: key,
      sessionId: sessionId,
      deviceId: deviceId,
    );
  }

  Future<ShiftReportData?> _loadShiftReport(String sessionId) async {
    final auth = context.read<AuthTokenProvider>();
    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final sync = GetIt.I<PosSyncService>();
    if (key.isEmpty) {
      throw Exception(
          'posKey отсутствует: невозможно загрузить Z-отчет с бэка');
    }
    if (deviceId.isEmpty) {
      throw Exception(
          'deviceId отсутствует: невозможно загрузить Z-отчет с бэка');
    }
    return sync.loadShiftReportFromBackend(
      key: key,
      sessionId: sessionId,
      deviceId: deviceId,
      includeProducts: true,
    );
  }

  Future<List<LocalAccount>> loadBankAccounts() async {
    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) {
      throw Exception(
          'posKey отсутствует: невозможно загрузить счета с бэка');
    }
    final accounts = await GetIt.I<PosSyncService>().loadAccountsFromBackend(
      key: key,
    );
    return accounts
        .where((account) =>
            account.visibleToPos && account.normalizedType == 'bank')
        .toList(growable: false);
  }

  @override
  void dispose() {
    _hideShortageCommentKeyboard();
    _ctrl.dispose();
    _amountFocusNode.dispose();
    _shortageCommentCtrl.dispose();
    _shortageCommentFocusNode.dispose();
    super.dispose();
  }

  void _focusAmountInput() {
    if (!mounted) return;
    _amountFocusNode.requestFocus();
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _showShortageCommentKeyboard() {
    _shortageCommentFocusNode.requestFocus();
    if (_shortageCommentKeyboardEntry != null) return;
    if (mounted) {
      setState(() => _shortageCommentKeyboardOpen = true);
    }

    _shortageCommentKeyboardEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.transparent,
          child: OnScreenKeyboardSheet(
            controllerGetter: () => _shortageCommentCtrl,
            onEnter: _hideShortageCommentKeyboard,
            onClose: _hideShortageCommentKeyboard,
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(
      _shortageCommentKeyboardEntry!,
    );
  }

  void _hideShortageCommentKeyboard() {
    _shortageCommentKeyboardEntry?.remove();
    _shortageCommentKeyboardEntry = null;
    if (mounted && _shortageCommentKeyboardOpen) {
      setState(() => _shortageCommentKeyboardOpen = false);
    } else {
      _shortageCommentKeyboardOpen = false;
    }
  }

  num? _parseAmount(String s) {
    final value = s.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (value.isEmpty) return null;
    return num.tryParse(value);
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
    _ctrl.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _appendAmountToken(String token) {
    var value = _ctrl.text;

    if (token == 'backspace') {
      if (value.isNotEmpty) {
        value = value.substring(0, value.length - 1);
      }
      _setAmountText(value);
      _focusAmountInput();
      return;
    }

    if (token == '.') {
      if (!value.contains('.')) {
        value = value.isEmpty ? '0.' : '$value.';
      }
      _setAmountText(value);
      _focusAmountInput();
      return;
    }

    value = value == '0' ? token : '$value$token';
    value = value.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    _setAmountText(value);
    _focusAmountInput();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final amount = _parseAmount(_ctrl.text);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Введите корректную сумму')),
      );
      return;
    }

    late final ShiftClosureSummaryData? summary;
    try {
      summary = await _summaryFuture;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Не удалось загрузить итоги смены с бэка: $error'),
        ),
      );
      return;
    }
    String? closeComment;
    if (!mounted) return;
    if (summary != null && amount < summary.expectedCashAmount) {
      closeComment = _shortageCommentCtrl.text.trim();
      if (closeComment.isEmpty) {
        setState(() {
          _showConfirmDialog = true;
          _shortageCommentError = 'Укажите причину недостачи';
        });
        _shortageCommentFocusNode.requestFocus();
        return;
      }
    }

    setState(() {
      _showConfirmDialog = false;
      _submitting = true;
    });
    _hideShortageCommentKeyboard();
    await context.read<AuthCubit>().closeSessionWithCash(
          closingCashAmount: amount,
          comment: closeComment,
        );
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _printReport() async {
    if (_printingReport || _submitting || _showSuccessState) return;

    final tokenProvider = context.read<AuthTokenProvider>();
    final sessionId = tokenProvider.shiftId?.trim() ?? '';
    if (sessionId.isEmpty) return;

    setState(() => _printingReport = true);
    try {
      final report = await _loadShiftReport(sessionId);
      if (report == null || !mounted) return;

      final storeName = (tokenProvider.storeName ?? '').trim().isEmpty
          ? ((tokenProvider.posName ?? '').trim().isEmpty
              ? 'Магазин'
              : tokenProvider.posName!.trim())
          : tokenProvider.storeName!.trim();
      final posName = (tokenProvider.posName ?? '').trim().isEmpty
          ? 'POS'
          : tokenProvider.posName!.trim();
      final cashierName = (tokenProvider.activeUserName ?? '').trim().isEmpty
          ? 'Кассир'
          : tokenProvider.activeUserName!.trim();
      final pageFormat = tokenProvider.receiptPaperMm == 57
          ? PdfPageFormat.roll57
          : PdfPageFormat.roll80;

      await PrintService().print80mmSilently(
        () => buildShiftReportPdf(
          ShiftReportPdfData(
            pageFormat: pageFormat,
            money: money,
            storeName: storeName,
            posName: posName,
            cashierName: cashierName,
            sessionId: report.sessionId,
            openedAt: report.openedAt,
            closedAt: null,
            openingCashAmount: report.openingCashAmount,
            closingCashAmount: report.closingCashAmount,
            salesCount: report.salesCount,
            cashTotal: report.cashTotal,
            cardTotal: report.cardTotal,
            transferTotal: report.transferTotal,
            creditTotal: report.creditTotal,
            grandTotal: report.grandTotal,
            refundsTotal: report.refundsTotal,
            incomeTotal: report.incomeTotal,
            expenseTotal: report.expenseTotal,
            expectedCashAmount: report.expectedCashAmount,
            reportTitle: 'Z-ОТЧЁТ',
            reportSubtitle:
                'Данные для закрытия смены',
            footerText:
                'Подтверждение закрытия',
            items: report.items
                .map(
                  (item) => ReceiptPdfItem(
                    name: item.name,
                    quantity: item.quantity,
                    unitPrice: 0,
                    lineTotal: item.totalSum,
                  ),
                )
                .toList(),
          ),
        ),
        format: pageFormat,
        printerName: tokenProvider.receiptPrinterName,
      );
    } finally {
      if (mounted) {
        setState(() => _printingReport = false);
      }
    }
  }

  void _openConfirmDialog() {
    final amount = _parseAmount(_ctrl.text);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Введите корректную сумму')),
      );
      return;
    }

    setState(() {
      _shortageCommentError = null;
      _showConfirmDialog = true;
    });
    _summaryFuture.then((summary) {
      if (!mounted || !_showConfirmDialog || summary == null) return;
      if (amount >= summary.expectedCashAmount) return;
      _shortageCommentFocusNode.requestFocus();
    });
  }

  void _closePage() {
    final hasShift = context.read<AuthTokenProvider>().hasShiftId;
    context.go(hasShift ? '/pos' : '/login');
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d.$m.$y г';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tokenProvider = context.read<AuthTokenProvider>();
    final hasShift = tokenProvider.hasShiftId;

    return BlocConsumer<AuthCubit, AuthState>(
      listenWhen: (prev, curr) =>
          curr is AuthFailure ||
          curr is AuthShiftClosed ||
          curr is AuthProvisioned ||
          curr is AuthInitial,
      listener: (context, state) {
        if (state is AuthFailure) {
          if (mounted) setState(() => _showSuccessState = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          return;
        }

        if (state is AuthShiftClosed && mounted) {
          setState(() => _showSuccessState = true);
        }
      },
      builder: (context, state) {
        final isClosingFlow =
            state is AuthClosingSession || _submitting || _showSuccessState;
        final isBusy = isClosingFlow || _showConfirmDialog || _printingReport;
        final loadingState = state is AuthClosingSession ? state : null;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F3),
          body: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone = constraints.maxWidth < 920;
                    final horizontalPadding = isPhone ? 18.0 : 32.0;
                    return Container(
                      width: double.infinity,
                      margin: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F3),
                        borderRadius: BorderRadius.circular(0),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                24,
                                horizontalPadding,
                                0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: isBusy ? null : _closePage,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                        icon: const Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                          size: 18,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Закрыть смену',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 72),
                                  Expanded(
                                    child: isPhone
                                        ? Column(
                                            children: [
                                              Expanded(
                                                flex: 6,
                                                child:
                                                    _buildLeftBlock(hasShift),
                                              ),
                                              const SizedBox(height: 16),
                                              Expanded(
                                                flex: 5,
                                                child: _buildRightBlock(
                                                  isClosingFlow ||
                                                      _printingReport,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                flex: 12,
                                                child:
                                                    _buildLeftBlock(hasShift),
                                              ),
                                              const SizedBox(width: 46),
                                              Expanded(
                                                flex: 5,
                                                child: Transform.translate(
                                                  offset: const Offset(0, -54),
                                                  child: _buildRightBlock(
                                                    isClosingFlow ||
                                                        _printingReport,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            color: const Color(0xFF3F444C),
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              23,
                              horizontalPadding,
                              23,
                            ),
                            child: Row(
                              children: [
                                const Spacer(),
                                SizedBox(
                                  width: isPhone ? double.infinity : 164,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: isClosingFlow || _printingReport
                                        ? null
                                        : _openConfirmDialog,
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      backgroundColor: const Color(0xFF33CC99),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'СДАТЬ СМЕНУ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (_showConfirmDialog)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _hideShortageCommentKeyboard();
                        _showConfirmDialog = false;
                      }),
                      child: Container(
                        color: const Color(0x88000000),
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () {},
                          child: AnimatedPadding(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.only(
                              bottom:
                                  _shortageCommentKeyboardOpen ? 340 : 0,
                            ),
                            child: FutureBuilder<ShiftClosureSummaryData?>(
                              future: _summaryFuture,
                              builder: (context, snapshot) {
                              final summary = snapshot.data;
                              final enteredAmount =
                                  _parseAmount(_ctrl.text) ?? 0;
                              final hasShortage = summary != null &&
                                  enteredAmount < summary.expectedCashAmount;
                              final difference = summary == null
                                  ? 0
                                  : enteredAmount -
                                      summary.expectedCashAmount;
                              final screenWidth =
                                  MediaQuery.of(context).size.width;
                              final dialogWidth =
                                  screenWidth < 920 ? screenWidth - 24 : 620.0;
                                return Container(
                                width: dialogWidth,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.22),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      height: 64,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF3B424C),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(14),
                                          topRight: Radius.circular(14),
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'Данные для закрытия',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        22,
                                        20,
                                        22,
                                        18,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _ModalRow(
                                            label:
                                                'Фактическая сумма',
                                            value: money(enteredAmount),
                                            strong: true,
                                          ),
                                          const SizedBox(height: 10),
                                          _ModalRow(
                                            label:
                                                'Ожидается в кассе',
                                            value: summary == null
                                                ? '-'
                                                : money(
                                                    summary.expectedCashAmount),
                                          ),
                                          const SizedBox(height: 10),
                                          _ModalRow(
                                            label:
                                                'Продажи за смену',
                                            value: summary == null
                                                ? '-'
                                                : money(
                                                    summary.totalSalesAmount),
                                          ),
                                          const SizedBox(height: 10),
                                          _ModalRow(
                                            label: 'Взнос',
                                            value: summary == null
                                                ? '-'
                                                : money(summary.incomeTotal),
                                          ),
                                          const SizedBox(height: 10),
                                          _ModalRow(
                                            label: 'Расход',
                                            value: summary == null
                                                ? '-'
                                                : money(summary.expenseTotal),
                                          ),
                                          if (summary != null) ...[
                                            const SizedBox(height: 10),
                                            _ModalRow(
                                              label:
                                                  'Разница',
                                              value: money(difference),
                                              valueColor: difference < 0
                                                  ? const Color(0xFFD15850)
                                                  : difference > 0
                                                      ? const Color(0xFF047857)
                                                      : const Color(0xFF111827),
                                            ),
                                          ],
                                          if (hasShortage) ...[
                                            const SizedBox(height: 14),
                                            TextField(
                                              controller: _shortageCommentCtrl,
                                              focusNode:
                                                  _shortageCommentFocusNode,
                                              autofocus: true,
                                              minLines: 2,
                                              maxLines: 4,
                                              maxLength: 1000,
                                              textInputAction:
                                                  TextInputAction.newline,
                                              onChanged: (_) {
                                                if (_shortageCommentError ==
                                                    null) {
                                                  return;
                                                }
                                                setState(() =>
                                                    _shortageCommentError =
                                                        null);
                                              },
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF111827),
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'Комментарий',
                                                labelStyle: const TextStyle(
                                                  color: Color(0xFF4B5563),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                floatingLabelStyle:
                                                    const TextStyle(
                                                  color: Color(0xFF4B5563),
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                hintText:
                                                    'Напишите причину недостача',
                                                errorText:
                                                    _shortageCommentError,
                                                suffixIcon: IconButton(
                                                  tooltip: 'Клавиатура',
                                                  onPressed:
                                                      _showShortageCommentKeyboard,
                                                  icon: const Icon(
                                                    Icons
                                                        .keyboard_alt_outlined,
                                                    color: Color(0xFF111827),
                                                  ),
                                                ),
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF7F7F8),
                                                counterStyle: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  borderSide:
                                                      const BorderSide(
                                                    color: Color(0xFFE0E0E0),
                                                  ),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  borderSide:
                                                      const BorderSide(
                                                    color: Color(0xFFE0E0E0),
                                                  ),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  borderSide:
                                                      const BorderSide(
                                                    color: Color(0xFF33CC99),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        0,
                                        14,
                                        14,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: 54,
                                              child: ElevatedButton(
                                                onPressed: () => setState(
                                                  () {
                                                    _hideShortageCommentKeyboard();
                                                    _showConfirmDialog = false;
                                                  },
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  elevation: 0,
                                                  backgroundColor:
                                                      const Color(0xFFD95C55),
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'ОТМЕНА',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: SizedBox(
                                              height: 54,
                                              child: ElevatedButton(
                                                onPressed: _printingReport
                                                    ? null
                                                    : _printReport,
                                                style: ElevatedButton.styleFrom(
                                                  elevation: 0,
                                                  backgroundColor:
                                                      const Color(0xFFD7D7D7),
                                                  foregroundColor:
                                                      const Color(0xFF111827),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                                child: _printingReport
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                              Color(0xFF111827),
                                                        ),
                                                      )
                                                    : const Text(
                                                        'Распечатать\nZ-отчет',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          height: 1.1,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            flex: 2,
                                            child: SizedBox(
                                              height: 54,
                                              child: ElevatedButton(
                                                onPressed: _submitting
                                                    ? null
                                                    : _submit,
                                                style: ElevatedButton.styleFrom(
                                                  elevation: 0,
                                                  backgroundColor:
                                                      const Color(0xFF33CC99),
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'СДАТЬ СМЕНУ',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isClosingFlow)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xAA111827),
                      alignment: Alignment.center,
                      child: Container(
                        width: 460,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 54,
                              height: 54,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _showSuccessState
                                      ? const Color(0xFF33CC99)
                                      : const Color(0xFFF2F4F7),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _showSuccessState
                                      ? Icons.check_rounded
                                      : Icons.hourglass_top_rounded,
                                  color: _showSuccessState
                                      ? Colors.white
                                      : const Color(0xFF111827),
                                  size: 30,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _showSuccessState
                                  ? 'Смена закрыта'
                                  : ((loadingState?.message.isNotEmpty) ??
                                          false)
                                      ? loadingState!.message
                                      : 'Закрываем смену...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF101828),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _showSuccessState
                                  ? 'Операция успешно завершена.'
                                  : 'Подождите, выполняется синхронизация и закрытие смены.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                                color: Color(0xFF667085),
                              ),
                            ),
                            if (!_showSuccessState) ...[
                              const SizedBox(height: 18),
                              const LinearProgressIndicator(
                                minHeight: 8,
                                color: Color(0xFF33CC99),
                                backgroundColor: Color(0xFFE5E7EB),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(999)),
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _showSuccessState
                                    ? () => context.go('/login')
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: const Color(0xFF111827),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Text(
                                  _showSuccessState
                                      ? 'Продолжить'
                                      : 'В процессе',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftBlock(bool hasShift) {
    if (!hasShift) return const _NoShiftContent();

    final now = DateTime.now();
    final tokenProvider = context.read<AuthTokenProvider>();
    final shiftId = (tokenProvider.posNumber ?? '').trim();
    final cashierName = (tokenProvider.activeUserName ?? '').trim();
    final posName = (tokenProvider.posName ?? '').trim();

    return FutureBuilder<ShiftClosureSummaryData?>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SummaryErrorCard(error: snapshot.error);
        }
        final summary = snapshot.data;
        if (summary == null) {
          return const _LoadingSummaryCard();
        }

        return SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Касса'),
                  const SizedBox(height: 12),
                  if (compact)
                    Column(
                      children: [
                        _InfoTile(
                          minHeight: 98,
                          lines: [
                            _InfoLine(
                                'Начало', _formatDate(now)),
                            _InfoLine(
                                'Время', _formatTime(now)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _TwoTileRow(
                          left: _InfoTile(
                            background: const Color(0xFFF3E2AC),
                            lines: [
                              _InfoLine(
                                'Смена',
                                shiftId.isEmpty ? '-' : shiftId,
                              ),
                            ],
                          ),
                          right: _InfoTile(
                            background: const Color(0xFFE0E0E0),
                            lines: [
                              _InfoLine(
                                'Кассир',
                                cashierName.isEmpty ? '-' : cashierName,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _InfoTile(
                          minHeight: 68,
                          lines: [
                            _InfoLine('Касса',
                                posName.isEmpty ? '-' : posName),
                          ],
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _InfoTile(
                            minHeight: 98,
                            lines: [
                              _InfoLine('Начало',
                                  _formatDate(now)),
                              _InfoLine(
                                  'Время', _formatTime(now)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 12,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _InfoTile(
                                      minHeight: 42,
                                      background: const Color(0xFFF3E2AC),
                                      lines: [
                                        _InfoLine(
                                          'Смена',
                                          shiftId.isEmpty ? '-' : shiftId,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _InfoTile(
                                      minHeight: 42,
                                      background: const Color(0xFFE0E0E0),
                                      lines: [
                                        _InfoLine(
                                          'Кассир',
                                          cashierName.isEmpty
                                              ? '-'
                                              : cashierName,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _InfoTile(
                                  minHeight: 98,
                                  lines: [
                                    _InfoLine(
                                      'Касса',
                                      posName.isEmpty ? '-' : posName,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 34),
                  const _SectionTitle('Продажа'),
                  const SizedBox(height: 12),
                  _SalesSummaryTiles(summary: summary),
                  const SizedBox(height: 34),
                  const _SectionTitle(
                      'Взнос и вынос'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: _InfoTile(
                          background: const Color(0xFFDDEFC4),
                          lines: [
                            _InfoLine('Взнос',
                                money(summary.incomeTotal)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: _InfoTile(
                          background: const Color(0xFFEECFC9),
                          lines: [
                            _InfoLine('Расход',
                                money(summary.expenseTotal)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: _InfoTile(
                          lines: [
                            _InfoLine('Возврат',
                                money(summary.refundsTotal)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRightBlock(bool isBusy) {
    return FutureBuilder<ShiftClosureSummaryData?>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        return IgnorePointer(
          ignoring: isBusy,
          child: Opacity(
            opacity: isBusy ? 0.55 : 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = constraints.maxWidth.clamp(178.0, 220.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (summary != null)
                      SizedBox(
                        width: panelWidth,
                        height: 144,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Начало смены',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF8D929A),
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    money(summary.openingCashAmount),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Наличные',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF8D929A),
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${summary.salesCount} шт',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Ожидается',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF8D929A),
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    money(summary.expectedCashAmount),
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF33CC99),
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    InkWell(
                      onTap: _focusAmountInput,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: panelWidth,
                        height: 49,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF2F9CFF),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _amountFocusNode,
                                enableInteractiveSelection: false,
                                contextMenuBuilder: null,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9\.,]'),
                                  ),
                                ],
                                onTap: _focusAmountInput,
                                onChanged: (_) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted ||
                                        !_amountFocusNode.hasFocus) {
                                      return;
                                    }
                                    final text = _ctrl.text;
                                    if (_ctrl.selection.isCollapsed &&
                                        _ctrl.selection.baseOffset ==
                                            text.length) {
                                      return;
                                    }
                                    _ctrl.selection = TextSelection.collapsed(
                                      offset: text.length,
                                    );
                                  });
                                },
                                onSubmitted: (_) => _openConfirmDialog(),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '₸',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final bottomPadding =
                              constraints.maxHeight >= 320 ? 22.0 : 12.0;
                          return Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: EdgeInsets.only(bottom: bottomPadding),
                              child: _ShiftCloseKeypad(
                                width: panelWidth,
                                maxHeight:
                                    constraints.maxHeight - bottomPadding,
                                onToken: (token) {
                                  setState(() => _appendAmountToken(token));
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LoadingSummaryCard extends StatelessWidget {
  const _LoadingSummaryCard();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Сводка по смене загружается...',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF667085),
          ),
        ),
      ),
    );
  }
}

class _SummaryErrorCard extends StatelessWidget {
  const _SummaryErrorCard({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Не удалось загрузить данные смены с бэка.\n$error',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFFD15850),
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ShiftCloseKeypad extends StatelessWidget {
  const _ShiftCloseKeypad({
    required this.width,
    required this.maxHeight,
    required this.onToken,
  });

  final double width;
  final double maxHeight;
  final ValueChanged<String> onToken;

  @override
  Widget build(BuildContext context) {
    final boundedHeight = maxHeight.isFinite ? maxHeight : 321.0;
    final compact = boundedHeight < 300;
    final gap = compact ? 8.0 : 11.0;
    final buttonSize = ((boundedHeight - gap * 3) / 4).clamp(54.0, 72.0);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShiftCloseKeypadRow(
            children: [
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '7',
                onTap: () => onToken('7'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '8',
                onTap: () => onToken('8'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '9',
                onTap: () => onToken('9'),
              ),
            ],
          ),
          SizedBox(height: gap),
          _ShiftCloseKeypadRow(
            children: [
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '4',
                onTap: () => onToken('4'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '5',
                onTap: () => onToken('5'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '6',
                onTap: () => onToken('6'),
              ),
            ],
          ),
          SizedBox(height: gap),
          _ShiftCloseKeypadRow(
            children: [
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '1',
                onTap: () => onToken('1'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '2',
                onTap: () => onToken('2'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '3',
                onTap: () => onToken('3'),
              ),
            ],
          ),
          SizedBox(height: gap),
          _ShiftCloseKeypadRow(
            children: [
              _ShiftCloseDigitButton(
                size: buttonSize,
                customIcon: const _ShiftCloseBackspaceIcon(),
                onTap: () => onToken('backspace'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '0',
                onTap: () => onToken('0'),
              ),
              _ShiftCloseDigitButton(
                size: buttonSize,
                label: '.',
                onTap: () => onToken('.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShiftCloseKeypadRow extends StatelessWidget {
  const _ShiftCloseKeypadRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: children,
    );
  }
}

class _ShiftCloseDigitButton extends StatelessWidget {
  const _ShiftCloseDigitButton({
    required this.size,
    required this.onTap,
    this.label,
    this.customIcon,
  });

  final double size;
  final VoidCallback onTap;
  final String? label;
  final Widget? customIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFFDADADA),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: customIcon ??
            Text(
              label ?? '',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w500,
                color: Colors.black,
                height: 1,
              ),
            ),
      ),
    );
  }
}

class _ShiftCloseBackspaceIcon extends StatelessWidget {
  const _ShiftCloseBackspaceIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ShiftCloseBackspacePainter(),
            ),
          ),
          const Text(
            '×',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftCloseBackspacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF33CC99);
    final path = Path()
      ..moveTo(size.width * 0.28, 0)
      ..lineTo(size.width, 0)
      ..quadraticBezierTo(size.width, 0, size.width, size.height * 0.18)
      ..lineTo(size.width, size.height * 0.82)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width * 0.82,
        size.height,
      )
      ..lineTo(size.width * 0.28, size.height)
      ..lineTo(0, size.height * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NoShiftContent extends StatelessWidget {
  const _NoShiftContent();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Смена не открыта',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w900,
        color: Colors.black,
      ),
    );
  }
}

class _TwoTileRow extends StatelessWidget {
  const _TwoTileRow({
    required this.left,
    required this.right,
  });

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }
}

class _SalesSummaryTiles extends StatelessWidget {
  const _SalesSummaryTiles({required this.summary});

  final ShiftClosureSummaryData summary;

  @override
  Widget build(BuildContext context) {
    final totalsTile = _InfoTile(
      minHeight: 98,
      lines: [
        _InfoLine('Продажа', money(summary.totalSalesAmount)),
        _InfoLine('Количество чеков', '${summary.salesCount} шт'),
      ],
    );
    final cashTile = _InfoTile(
      background: const Color(0xFFDDEFC4),
      lines: [
        _InfoLine('Наличными', money(summary.cashSalesTotal)),
      ],
    );
    final debtTile = _InfoTile(
      background: const Color(0xFFE0E0E0),
      lines: [
        _InfoLine('Долги', money(summary.creditSalesTotal)),
      ],
    );
    final cashlessTiles = _cashlessTiles(summary.cashlessAccounts);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 650) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _spacedColumn([
                  totalsTile,
                  for (var i = 2; i < cashlessTiles.length; i += 3)
                    cashlessTiles[i],
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: _spacedColumn([
                  cashTile,
                  for (var i = 0; i < cashlessTiles.length; i += 3)
                    cashlessTiles[i],
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: _spacedColumn([
                  debtTile,
                  for (var i = 1; i < cashlessTiles.length; i += 3)
                    cashlessTiles[i],
                ]),
              ),
            ],
          );
        }

        final tiles = <Widget>[
          totalsTile,
          cashTile,
          debtTile,
          ...cashlessTiles,
        ];
        final columnCount = constraints.maxWidth < 650 ? 2 : 3;
        final totalGap = 8 * (columnCount - 1);
        final tileWidth =
            ((constraints.maxWidth - totalGap) / columnCount).floorToDouble();

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: tile,
              ),
          ],
        );
      },
    );
  }

  Widget _spacedColumn(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  List<Widget> _cashlessTiles(List<CashlessAccountReport> accounts) {
    if (accounts.isEmpty) {
      return const [
        _InfoTile(
          background: Color(0xFFD2E4EF),
          lines: [
            _InfoLine('Безналичные', '0'),
          ],
        ),
      ];
    }

    return [
      for (final account in accounts)
        _InfoTile(
          background: const Color(0xFFD2E4EF),
          lines: [
            _InfoLine(
              account.accountName.trim().isEmpty
                  ? 'Счет BANK'
                  : account.accountName.trim(),
              money(account.netTotal),
            ),
          ],
        ),
    ];
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.lines,
    this.background = Colors.white,
    this.minHeight = 42,
  });

  final List<_InfoLine> lines;
  final Color background;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            Text(
              lines[i].label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF8D929A),
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              lines[i].value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                height: 1.05,
              ),
            ),
            if (i != lines.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _InfoLine {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;
}

class _ModalRow extends StatelessWidget {
  const _ModalRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF667085),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 20 : 16,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
            color: valueColor ?? const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

extension on ShiftClosureSummaryData {
  int get salesCount => 0;
}
