import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/refund_model.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/datasources/refunds_remote_datasource.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart'
    show LocalAccount, LocalSession, QueueSendResult;
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/models/refund_pick.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/error_bloc.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_history_controller.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_search_bar.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';
import 'package:leemon_app/features/presentation/widgets/refund_reason_selector.dart';

import 'state/sales_cubit.dart';
import 'state/sales_state.dart';

import 'utils/app_scroll_behavior.dart';
import 'utils/formatters.dart';
import 'utils/sales_filter.dart';
import 'widgets/sale_card.dart';
import 'widgets/sale_items_box.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  static const Duration _historyIdleTimeout = Duration(seconds: 60);
  static const Duration _printLoadingDuration = Duration(seconds: 1);
  static const Duration _printCooldownDuration = Duration(seconds: 5);

  String? _expandedSaleId;
  String? _expandedRefundId;

  final ScrollController _scrollController = ScrollController();
  late final SalesHistoryCubit _cubit;
  StreamSubscription<void>? _historyChangedSub;

  final _controller = SalesHistoryController();

  final TextEditingController _saleSearchCtrl = TextEditingController();
  Timer? _saleSearchDebounce;
  Timer? _historyRefreshDebounce;
  Timer? _historyIdleTimer;
  bool _historyIdlePaused = false;
  String _saleQuery = '';
  DateTime? _selectedDate;
  SalesStatusFilter _statusFilter = SalesStatusFilter.all;
  StreamSubscription<PosState>? _posStateSub;

  int? _statusCodeOf(Object e) {
    try {
      final dynamic de = e;
      final dynamic resp = de.response;
      final code = resp?.statusCode;
      if (code is int) return code;
    } catch (_) {}
    return null;
  }

  static const double _fs = 18;
  final FocusNode _saleSearchFocusNode = FocusNode();
  bool _saleKeyboardOpen = false;
  OverlayEntry? _saleKeyboardEntry;

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _cancelHistoryIdleTimer() {
    _historyIdleTimer?.cancel();
    _historyIdleTimer = null;
  }

  void _resetHistoryIdleTimer() {
    if (!mounted) return;
    if (_historyIdlePaused) {
      _cancelHistoryIdleTimer();
      return;
    }
    final posCubit = context.read<PosCubit>();
    if (!posCubit.state.isHistoryMode) {
      _cancelHistoryIdleTimer();
      return;
    }

    _historyIdleTimer?.cancel();
    _historyIdleTimer = Timer(_historyIdleTimeout, () {
      if (!mounted) return;
      final currentCubit = context.read<PosCubit>();
      if (!currentCubit.state.isHistoryMode) return;
      currentCubit.showSales();
    });
  }

  void _trackUserActivity() {
    _resetHistoryIdleTimer();
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(DateTime.now());

    final sync = GetIt.I<PosSyncService>();
    _cubit = SalesHistoryCubit(sync, GetIt.I<RefundsRemoteDatasource>());
    _historyChangedSub = sync.onSalesHistoryChanged.listen((_) {
      _scheduleHistoryRefresh();
    });

    _saleSearchCtrl.addListener(() {
      _trackUserActivity();
      _saleSearchDebounce?.cancel();
      _saleSearchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          _saleQuery = _saleSearchCtrl.text.trim();
          _expandedSaleId = null;
          _expandedRefundId = null;
        });
      });
    });

    _posStateSub = context.read<PosCubit>().stream.listen((state) {
      if (state.isHistoryMode) {
        _resetHistoryIdleTimer();
      } else {
        _cancelHistoryIdleTimer();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetHistoryIdleTimer();
      final auth = context.read<AuthTokenProvider>();
      final key = auth.posKey?.trim() ?? '';

      if (key.isEmpty) {
        _cubit.showError('POS key пустой. Пройдите provisioning.');
        return;
      }

      _reloadHistory();
    });
  }

  @override
  void dispose() {
    _saleSearchDebounce?.cancel();
    _historyRefreshDebounce?.cancel();
    _cancelHistoryIdleTimer();
    _historyChangedSub?.cancel();
    _posStateSub?.cancel();
    _closeSaleKeyboard();
    _saleSearchCtrl.dispose();
    _saleSearchFocusNode.dispose();

    _scrollController.dispose();
    _controller.dispose();
    _cubit.close();
    super.dispose();
  }

  void _scheduleHistoryRefresh() {
    _historyRefreshDebounce?.cancel();
    _historyRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      _reloadHistory,
    );
  }

  void _reloadHistory() {
    if (!mounted) return;

    final key = context.read<AuthTokenProvider>().posKey?.trim() ?? '';
    if (key.isEmpty) return;

    _cubit.loadFirst(key: key);
  }

  Future<T?> _runWithDialogFocus<T>(Future<T?> Function() open) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _saleSearchFocusNode.unfocus();

    try {
      return await open();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _saleSearchFocusNode.requestFocus();
        final t = _saleSearchCtrl.text;
        _saleSearchCtrl.selection = TextSelection.collapsed(offset: t.length);
      });
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _storeName(AuthTokenProvider auth) {
    final raw = auth.storeName?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
    final posName = auth.posName?.trim() ?? '';
    if (posName.isNotEmpty) return posName;
    return 'Магазин';
  }

  String _salePrintKey(SaleModel sale) {
    final localId = sale.localId.trim();
    if (localId.isNotEmpty) return localId;

    final number = sale.number.trim();
    if (number.isNotEmpty) return 'number:$number';

    return 'sale:${sale.date.microsecondsSinceEpoch}:${sale.totalAmount}';
  }

  String _sessionKeyForSale(SaleModel sale, List<LocalSession> sessions) {
    final saleSessionId = (sale.posSessionId ?? '').trim();
    if (saleSessionId.isNotEmpty) {
      final session = _sessionForSale(sale, sessions);
      return session?.clientSessionId ?? saleSessionId;
    }
    return '__without_session';
  }

  LocalSession? _sessionForSale(SaleModel sale, List<LocalSession> sessions) {
    final saleSessionId = (sale.posSessionId ?? '').trim();
    if (saleSessionId.isEmpty) return null;
    for (final session in sessions) {
      if (session.matches(saleSessionId)) return session;
    }
    return null;
  }

  List<_SalesHistoryListEntry> _buildSaleListEntries(
    List<SaleModel> sales,
    List<LocalSession> sessions,
  ) {
    if (sales.isEmpty) return const [];

    final summaries = <String, _SessionSalesSummary>{};
    for (final sale in sales) {
      final key = _sessionKeyForSale(sale, sessions);
      final current = summaries[key] ?? const _SessionSalesSummary();
      summaries[key] = current.add(sale.totalAmount);
    }

    final entries = <_SalesHistoryListEntry>[];
    String? lastKey;
    for (final sale in sales) {
      final key = _sessionKeyForSale(sale, sessions);
      if (key != lastKey) {
        entries.add(
          _SessionHeaderEntry(
            session: _sessionForSale(sale, sessions),
            summary: summaries[key] ?? const _SessionSalesSummary(),
          ),
        );
        lastKey = key;
      }
      entries.add(_SaleEntry(sale));
    }
    return entries;
  }

  void _notifyPrintStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  ReceiptPdfData _buildSaleReceiptData({
    required SaleModel sale,
    required AuthTokenProvider auth,
  }) {
    final pageFormat =
        auth.receiptPaperMm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? (sale.userId.trim().isEmpty ? '-' : sale.userId.trim())
        : auth.activeUserName!.trim();

    return ReceiptPdfData(
      pageFormat: pageFormat,
      money: money,
      receiptDate: sale.date,
      receiptNumber: formatPosReceiptNumber(
        posNumber: auth.posNumber ?? '',
        saleNumber: sale.number,
        fallback: sale.localId,
      ),
      cashierName: cashierName,
      storeName: _storeName(auth),
      items: sale.items
          .map(
            (it) => ReceiptPdfItem(
              name: it.displayProductName,
              quantity: it.quantity,
              unitPrice: it.price,
              lineTotal: it.totalPrice,
            ),
          )
          .toList(),
      total: sale.totalAmount,
      discountSum: 0,
      paymentMethodLabel: switch (sale.paymentMethod.trim().toLowerCase()) {
        'cash' => 'Наличные',
        'card' => 'Безналичный',
        'mixed' => 'Смешанная',
        'credit' => 'В долг',
        'debt' => 'В долг',
        'partial_debt' => 'В долг',
        _ =>
          sale.paymentMethod.trim().isEmpty ? '-' : sale.paymentMethod.trim(),
      },
      isCashPayment: sale.paymentMethod.trim().toLowerCase() == 'cash',
      paidNow: sale.paymentMethod.trim().toLowerCase() == 'cash'
          ? null
          : sale.paidAmount > 0
              ? sale.paidAmount
              : null,
      debtAmount: sale.debtAmount > 0 ? sale.debtAmount : null,
    );
  }

  Future<bool> _showReceiptPreview(ReceiptPdfData receipt) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ReceiptPreviewDialog(receipt: receipt),
    );
    return result == true;
  }

  Future<void> _printSaleReceipt(SaleModel sale) async {
    final saleKey = _salePrintKey(sale);
    if (_controller.isReceiptPrintDisabled(saleKey)) return;

    final previewAuth = context.read<AuthTokenProvider>();
    final previewReceipt = _buildSaleReceiptData(sale: sale, auth: previewAuth);
    final shouldPrint = await _showReceiptPreview(previewReceipt);
    if (!mounted || !shouldPrint) return;

    _controller.setReceiptPrintLoading(saleKey, true, _notifyPrintStateChanged);

    final auth = context.read<AuthTokenProvider>();
    final printer = PrintService();
    final pageFormat =
        auth.receiptPaperMm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? (sale.userId.trim().isEmpty ? '-' : sale.userId.trim())
        : auth.activeUserName!.trim();

    try {
      await printer.print80mmSilently(
        () => buildReceiptPdf(
          ReceiptPdfData(
            pageFormat: pageFormat,
            money: money,
            receiptDate: sale.date,
            receiptNumber: formatPosReceiptNumber(
              posNumber: auth.posNumber ?? '',
              saleNumber: sale.number,
              fallback: sale.localId,
            ),
            cashierName: cashierName,
            storeName: _storeName(auth),
            items: sale.items
                .map(
                  (it) => ReceiptPdfItem(
                    name: it.displayProductName,
                    quantity: it.quantity,
                    unitPrice: it.price,
                    lineTotal: it.totalPrice,
                  ),
                )
                .toList(),
            total: sale.totalAmount,
            discountSum: 0,
            paymentMethodLabel: switch (
                sale.paymentMethod.trim().toLowerCase()) {
              'cash' => 'Наличные',
              'card' => 'Безналичный',
              'credit' => 'В долг',
              'debt' => 'В долг',
              'partial_debt' => 'В долг',
              _ => sale.paymentMethod.trim().isEmpty
                  ? '-'
                  : sale.paymentMethod.trim(),
            },
            isCashPayment: sale.paymentMethod.trim().toLowerCase() == 'cash',
            paidNow: sale.paymentMethod.trim().toLowerCase() == 'cash'
                ? null
                : sale.paidAmount > 0
                    ? sale.paidAmount
                    : null,
            debtAmount: sale.debtAmount > 0 ? sale.debtAmount : null,
          ),
        ),
        format: pageFormat,
        printerName: auth.receiptPrinterName,
      );
      if (!mounted) return;
      _snack('Чек отправлен на печать');
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка печати: $e');
    } finally {
      _controller.startReceiptPrintCooldownAfterLoading(
        saleKey,
        _printLoadingDuration,
        _printCooldownDuration,
        _notifyPrintStateChanged,
      );
    }
  }

  Future<void> _printInvoice(SaleModel sale) async {
    final saleKey = _salePrintKey(sale);
    if (_controller.isInvoicePrintDisabled(saleKey)) return;

    _controller.setInvoicePrintLoading(saleKey, true, _notifyPrintStateChanged);

    final auth = context.read<AuthTokenProvider>();
    final printer = PrintService();
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? (sale.userId.trim().isEmpty ? '-' : sale.userId.trim())
        : auth.activeUserName!.trim();
    final storeName = (auth.storeName?.trim().isNotEmpty == true)
        ? auth.storeName!.trim()
        : (auth.posName?.trim().isNotEmpty == true
            ? auth.posName!.trim()
            : 'Магазин');

    try {
      final doc = await buildInvoicePdf(
        InvoicePdfData(
          money: money,
          invoiceDate: sale.date,
          invoiceNumber:
              sale.number.trim().isEmpty ? sale.localId : sale.number.trim(),
          cashierName: cashierName,
          storeName: storeName,
          items: sale.items
              .map(
                (it) => ReceiptPdfItem(
                  name: it.displayProductName,
                  quantity: it.quantity,
                  unitPrice: it.price,
                  lineTotal: it.totalPrice,
                ),
              )
              .toList(),
          total: sale.totalAmount,
          discountSum: 0,
          paymentMethodLabel: switch (sale.paymentMethod.trim().toLowerCase()) {
            'cash' => 'Наличные',
            'card' => 'Безналичный',
            'credit' => 'В долг',
            'debt' => 'В долг',
            'partial_debt' => 'В долг',
            _ => sale.paymentMethod.trim().isEmpty
                ? '-'
                : sale.paymentMethod.trim(),
          },
        ),
      );
      final bytes = await doc.save();
      await printer.printPdfBytesSilently(
        bytes,
        printerName: auth.invoicePrinterName,
      );
      if (!mounted) return;
      _snack('Накладная отправлена на печать');
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка печати накладной: $e');
    } finally {
      _controller.startInvoicePrintCooldownAfterLoading(
        saleKey,
        _printLoadingDuration,
        _printCooldownDuration,
        _notifyPrintStateChanged,
      );
    }
  }

  Future<void> _showRefundSuccessDialog({
    required bool updated,
    required int itemsCount,
    required num totalAmount,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'refund-success',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 420,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF16A34A),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      updated
                          ? 'Возврат успешно обновлён'
                          : 'Возврат успешно оформлен',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Позиции: $itemsCount',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Сумма: ${money(totalAmount.toDouble())}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(
                            fontSize: 14,
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
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('ru'),
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF456B5A),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF111827),
              surfaceContainerHighest: Color(0xFFEAF1ED),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF456B5A),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            dialogTheme: const DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedDate = _dateOnly(picked);
        _expandedSaleId = null;
        _expandedRefundId = null;
      });
    }
  }

  void _applySaleSearch() {
    setState(() {
      _saleQuery = _saleSearchCtrl.text.trim();
      _expandedSaleId = null;
      _expandedRefundId = null;
    });
  }

  void _logOpenedSale(SaleModel sale) {
    final json = const JsonEncoder.withIndent('  ').convert(sale.toJson());
    _debugPrintLong(
      '[SalesHistory] Opened sale. Stored local SaleModel:\n$json',
    );
  }

  void _debugPrintLong(String message) {
    const chunkSize = 900;
    for (var start = 0; start < message.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, message.length);
      debugPrint(message.substring(start, end));
    }
  }

  void _openSaleKeyboard() {
    if (_saleKeyboardOpen) return;
    _saleKeyboardOpen = true;

    if (!_saleSearchFocusNode.hasFocus) {
      _saleSearchFocusNode.requestFocus();
      final text = _saleSearchCtrl.text;
      _saleSearchCtrl.selection = TextSelection.collapsed(offset: text.length);
    }

    _saleKeyboardEntry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: double.infinity,
              child: OnScreenKeyboardSheet(
                controllerGetter: () => _saleSearchCtrl,
                onEnter: () {
                  _closeSaleKeyboard();
                  _applySaleSearch();
                },
                onClose: _closeSaleKeyboard,
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_saleKeyboardEntry!);
  }

  void _closeSaleKeyboard() {
    if (!_saleKeyboardOpen && _saleKeyboardEntry == null) return;
    _saleKeyboardOpen = false;
    _saleKeyboardEntry?.remove();
    _saleKeyboardEntry = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _saleSearchFocusNode.requestFocus();
      final text = _saleSearchCtrl.text;
      _saleSearchCtrl.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  Future<bool> _submitRefund(
    BuildContext context,
    SaleModel sale, {
    String? reasonCode,
  }) async {
    final auth = context.read<AuthTokenProvider>();

    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final posSessionId = auth.shiftId?.trim() ?? '';

    if (key.isEmpty) {
      _snack('Нет posKey');
      return false;
    }
    if (deviceId.isEmpty) {
      _snack('Нет deviceId');
      return false;
    }
    if (posSessionId.isEmpty) {
      _snack('Смена не открыта');
      return false;
    }
    final cashAccountId = auth.accountId?.trim() ?? '';

    final saleId = sale.localId.trim();
    if (saleId.isEmpty) {
      _snack('saleId пустой (sale.localId)');
      return false;
    }
    if (_controller.isRefundLoading(saleId)) return false;

    final picks = _controller
        .salePickMap(saleId)
        .values
        .where((e) => e.checked && e.quantity > 0)
        .toList();

    if (picks.isEmpty) {
      _snack('Выбери товары для возврата');
      return false;
    }

    // Synced sales have server-assigned item IDs; local-only sales do not.
    final isSynced = sale.items.any((i) => i.id.isNotEmpty);

    final items = picks.map((e) {
      if (e.productId.trim().isEmpty) {
        throw Exception('product_id пустой у sale_item_id=${e.saleItemId}');
      }
      return <String, dynamic>{
        'product_id': e.productId,
        'quantity': e.quantity,
        'price': e.price,
        if (isSynced && e.saleItemId.isNotEmpty) 'sale_item_id': e.saleItemId,
      };
    }).toList();

    final totalAmount = items.fold<int>(
      0,
      (sum, it) =>
          sum +
          (((it['price'] as num?) ?? 0).round() *
              ((it['quantity'] as num?) ?? 0).round()),
    );

    final sync = sl<PosSyncService>();
    void showRefundError(String message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }

    // Build payments[] based on the original sale's payment method
    final salePaymentMethod = sale.paymentMethod.trim().toLowerCase();
    final refundPaymentMethod = switch (salePaymentMethod) {
      'card' => 'card',
      'mixed' => 'mixed',
      _ => 'cash',
    };

    final accounts = await sync.loadAccounts();
    final visibleAccounts =
        accounts.where((account) => account.visibleToPos).toList();
    final cardAccount = visibleAccounts.cast<LocalAccount?>().firstWhere(
          (a) => a?.isBankOrPos ?? false,
          orElse: () => null,
        );

    if ((refundPaymentMethod == 'cash' || refundPaymentMethod == 'mixed') &&
        cashAccountId.isEmpty) {
      showRefundError(
        'Не найден наличный счёт POS. Выполните вход заново.',
      );
      return false;
    }
    if ((refundPaymentMethod == 'card' || refundPaymentMethod == 'mixed') &&
        (cardAccount?.id.trim().isEmpty ?? true)) {
      showRefundError(
        'Не найден счет карты. Обновите синхронизацию POS или настройте счет BANK/POS.',
      );
      return false;
    }

    final refundClientId = 'refund_${DateTime.now().microsecondsSinceEpoch}';
    final List<Map<String, dynamic>> refundPayments;
    if (refundPaymentMethod == 'mixed') {
      final half = totalAmount ~/ 2;
      refundPayments = [
        {
          'account_id': cashAccountId,
          'amount': half,
          'client_payment_id': '$refundClientId-cash',
        },
        {
          'account_id': cardAccount!.id,
          'amount': totalAmount - half,
          'client_payment_id': '$refundClientId-card',
        },
      ];
    } else if (refundPaymentMethod == 'card') {
      refundPayments = [
        {
          'account_id': cardAccount!.id,
          'amount': totalAmount,
          'client_payment_id': '$refundClientId-card',
        },
      ];
    } else {
      refundPayments = [
        {
          'account_id': cashAccountId,
          'amount': totalAmount,
          'client_payment_id': '$refundClientId-cash',
        },
      ];
    }

    final refundId = (sale.refund?.id ?? '').trim();
    var effectiveRefundId = refundId;
    // Key: server item id for synced sales, productId for offline sales.
    final pickedBySaleItemId = <String, int>{
      for (final p in picks)
        (p.saleItemId.isNotEmpty ? p.saleItemId : p.productId): p.quantity,
    };

    _controller.setRefundLoading(saleId, true, () => setState(() {}));

    // 🔍 Debug: Log saved return_access_key
    try {
      final sync = sl<PosSyncService>();
      final savedKeys = await sync.getAllActiveReturnAccessKeys();
      print('✅ [REFUND DEBUG] Refund initiated for sale: $saleId');
      print('   Saved return_access_keys count: ${savedKeys.length}');
      if (savedKeys.isNotEmpty) {
        for (var i = 0; i < savedKeys.length; i++) {
          print(
              '   Key[$i]: ${savedKeys[i].substring(0, min(10, savedKeys[i].length))}...${savedKeys[i].length > 10 ? ' (length: ${savedKeys[i].length})' : ''}');
        }
      } else {
        print('   ⚠️ No active return_access_keys found');
      }
    } catch (e) {
      print('❌ [DEBUG] Error checking return_access_keys: $e');
    }

    try {
      final ok = await _runWithDialogFocus(() async {
        return showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => RefundAccessDialog(
            onScanned: (barcode) async {
              final accessKey = barcode.trim();
              if (accessKey.isEmpty) return false;

              try {
                print(
                    '🔐 [REFUND] Sending refund with accessKey: ${accessKey.substring(0, min(10, accessKey.length))}...${accessKey.length > 10 ? ' (length: ${accessKey.length})' : ''}');
                final result = await sync.createRefund(
                  key: key,
                  deviceId: deviceId,
                  posSessionId: posSessionId,
                  saleId: isSynced ? saleId : '',
                  clientSaleId: isSynced ? null : saleId,
                  totalAmount: totalAmount,
                  paymentMethod: refundPaymentMethod,
                  payments: refundPayments,
                  items: items,
                  date: DateTime.now(),
                  returnAccessKey: accessKey,
                  reasonCode: reasonCode,
                );
                print(
                    '✅ [REFUND] Success! Result: ${result.result}, ClientId: ${result.clientId}');
                if (result.result == QueueSendResult.manual) {
                  throw Exception(
                    result.errorMessage ?? 'Возврат требует ручной обработки',
                  );
                }
                effectiveRefundId = result.clientId;
                return true; // 200 — доступ есть
              } catch (e) {
                // 401 — доступ нет, диалог покажет ошибку и попросит перескан
                if (_statusCodeOf(e) == 401) {
                  print(
                      '❌ [REFUND] Access denied (401) for key: ${accessKey.substring(0, min(10, accessKey.length))}...');
                  return false;
                }
                print('❌ [REFUND] Error: $e');
                rethrow; // остальные ошибки покажем как "Ошибка запроса"
              }
            },
          ),
        );
      });

      if (ok != true) return false; // отмена/закрытие/нет доступа

      if (!mounted) return false;
      _cubit.applyRefundOptimistic(
        saleId: saleId,
        refundId: effectiveRefundId,
        pickedBySaleItemId: pickedBySaleItemId,
      );
      try {
        await _printRefundReceipt(
          sale: sale,
          picks: picks,
          totalAmount: totalAmount,
          paymentMethod: refundPaymentMethod,
        );
      } catch (e) {
        if (mounted) {
          _snack('Ошибка печати чека возврата: $e');
        }
      }
      await _showRefundSuccessDialog(
        updated: refundId.isNotEmpty,
        itemsCount: picks.length,
        totalAmount: totalAmount,
      );

      _controller.clearPicksForSale(saleId, () => setState(() {}));
      return true;
    } catch (e) {
      if (mounted) {
        _snack('Ошибка возврата: $e');
      }
      return false;
    } finally {
      if (mounted) {
        _controller.setRefundLoading(saleId, false, () => setState(() {}));
      }
    }
  }

  Future<void> _openRefundPickDialog(
      BuildContext context, SaleModel sale) async {
    final saleId = sale.localId.trim();
    if (saleId.isEmpty) return _snack('saleId пустой (sale.localId)');
    final cashierName = (context.read<AuthTokenProvider>().activeUserName ?? '')
            .trim()
            .isNotEmpty
        ? context.read<AuthTokenProvider>().activeUserName!.trim()
        : cashierLabel(sale);

    _controller.clearPicksForSale(saleId, () => setState(() {}));

    _historyIdlePaused = true;
    _cancelHistoryIdleTimer();

    try {
      String? selectedReasonCode;
      await _runWithDialogFocus(() {
        return showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.45),
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (dialogContext, setDialogState) {
                void refresh() {
                  setDialogState(() {});
                  if (mounted) setState(() {});
                }

                final selectedCount = _controller.selectedItemsCount(saleId);
                final selectedTotal = _controller.selectedTotal(saleId);
                final canSubmit =
                    selectedCount > 0 && !_controller.isRefundLoading(saleId);

                return Dialog(
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  backgroundColor: Colors.transparent,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 1180, maxHeight: 560),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E5E5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                        child: Column(
                          children: [
                            _RefundDialogReceiptHeader(
                              sale: sale,
                              cashierName: cashierName,
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    SaleItemsBox(
                                      items: sale.items,
                                      picks: _controller.salePickMap(saleId),
                                      onToggleItem: (item, checked) {
                                        _controller.toggleItem(
                                          saleId: saleId,
                                          item: item,
                                          checked: checked,
                                          notify: refresh,
                                        );
                                      },
                                      onQtyChanged: (item, q) {
                                        _controller.changeQty(
                                          saleId: saleId,
                                          item: item,
                                          newQty: q,
                                          notify: refresh,
                                        );
                                      },
                                      refundedQtyOf: _controller.refundedQtyOf,
                                      availableQtyOf:
                                          _controller.availableQtyOf,
                                    ),
                                    const SizedBox(height: 10),
                                    RefundReasonSelector(
                                      selectedCode: selectedReasonCode,
                                      compact: true,
                                      onChanged: (code) {
                                        setDialogState(() {
                                          selectedReasonCode = code;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _RefundDialogTotal(
                                    count: selectedCount,
                                    total: selectedTotal,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 100,
                                      height: 40,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext)
                                                .pop(false),
                                        style: ElevatedButton.styleFrom(
                                          elevation: 0,
                                          backgroundColor:
                                              const Color(0xFF9A9A9A),
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                        ),
                                        child: const Text(
                                          'Отмена',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 104,
                                      height: 40,
                                      child: ElevatedButton(
                                        onPressed: canSubmit
                                            ? () async {
                                                setDialogState(() {});
                                                final success =
                                                    await _submitRefund(
                                                  dialogContext,
                                                  sale,
                                                  reasonCode:
                                                      selectedReasonCode,
                                                );
                                                if (!dialogContext.mounted) {
                                                  return;
                                                }
                                                setDialogState(() {});
                                                if (success) {
                                                  Navigator.of(dialogContext)
                                                      .pop();
                                                }
                                              }
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          elevation: 0,
                                          backgroundColor:
                                              const Color(0xFF2DB8CF),
                                          disabledBackgroundColor:
                                              const Color(0xFFB6B6B6),
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                        ),
                                        child: const Text(
                                          'Возврат',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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
      });
    } finally {
      _historyIdlePaused = false;
      if (mounted) _resetHistoryIdleTimer();
    }
  }

  Future<void> _printRefundReceipt({
    required SaleModel sale,
    required List<RefundPick> picks,
    required num totalAmount,
    required String paymentMethod,
  }) async {
    final auth = context.read<AuthTokenProvider>();
    final printer = PrintService();
    final pageFormat =
        auth.receiptPaperMm == 57 ? PdfPageFormat.roll57 : PdfPageFormat.roll80;
    final cashierName = (auth.activeUserName ?? '').trim().isEmpty
        ? (sale.userId.trim().isEmpty ? '-' : sale.userId.trim())
        : auth.activeUserName!.trim();

    final picksByKey = <String, int>{
      for (final pick in picks)
        (pick.saleItemId.isNotEmpty ? pick.saleItemId : pick.productId):
            pick.quantity,
    };

    final refundItems = sale.items.where((item) {
      final key = item.id.isNotEmpty ? item.id : item.productId;
      return picksByKey.containsKey(key);
    }).map((item) {
      final key = item.id.isNotEmpty ? item.id : item.productId;
      final qty = (picksByKey[key] ?? 0).toDouble();
      return ReceiptPdfItem(
        name: item.displayProductName,
        quantity: qty,
        unitPrice: item.price,
        lineTotal: double.parse((item.price * qty).toStringAsFixed(2)),
      );
    }).toList(growable: false);

    if (refundItems.isEmpty) return;

    await printer.print80mmSilently(
      () => buildReceiptPdf(
        ReceiptPdfData(
          pageFormat: pageFormat,
          money: money,
          receiptDate: DateTime.now(),
          receiptNumber: '',
          cashierName: cashierName,
          storeName: _storeName(auth),
          items: refundItems,
          total: totalAmount,
          discountSum: 0,
          paymentMethodLabel: switch (paymentMethod) {
            'cash' => 'Наличные',
            'card' => 'Безналичный',
            'mixed' => 'Смешанная',
            'credit' => 'В долг',
            'debt' => 'В долг',
            'partial_debt' => 'В долг',
            _ => paymentMethod.isEmpty ? '-' : paymentMethod,
          },
          isCashPayment: paymentMethod == 'cash',
          documentTitle: 'ЧЕК ВОЗВРАТА',
          footerText: 'Возврат успешно оформлен',
        ),
      ),
      format: pageFormat,
      printerName: auth.receiptPrinterName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _trackUserActivity(),
      onPointerSignal: (_) => _trackUserActivity(),
      child: DefaultTextStyle.merge(
        style: GoogleFonts.inter(fontSize: _fs, color: Colors.black),
        child: BlocProvider.value(
          value: _cubit,
          child: BlocBuilder<SalesHistoryCubit, SalesHistoryState>(
            builder: (context, state) {
              final showingRefunds =
                  _statusFilter == SalesStatusFilter.refunded;
              final visibleSales = filterSales(
                state.sales,
                _saleQuery,
                date: _selectedDate,
                status: _statusFilter,
              );
              final visibleRefunds = showingRefunds
                  ? (filterRefunds(
                      state.refunds,
                      _saleQuery,
                      date: _selectedDate,
                    )..sort((a, b) {
                      final ad =
                          a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final bd =
                          b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                      return bd.compareTo(ad);
                    }))
                  : const <RefundModel>[];
              final savedCashierName =
                  context.read<AuthTokenProvider>().activeUserName ?? '';
              final visibleTotalAmount = showingRefunds
                  ? visibleRefunds.fold<num>(
                      0,
                      (sum, refund) => sum + (refund.totalAmount ?? 0),
                    )
                  : visibleSales.fold<num>(
                      0,
                      (sum, sale) => sum + sale.totalAmount,
                    );
              final visibleChecksCount =
                  showingRefunds ? visibleRefunds.length : visibleSales.length;
              final saleListEntries =
                  _buildSaleListEntries(visibleSales, state.sessions);
              final showRefundReason = visibleRefunds.any((refund) =>
                  (refund.reason ?? refund.note ?? '').trim().isNotEmpty ||
                  refundReasonLabel(refund.reasonCode).isNotEmpty);

              return Column(
                children: [
                  SalesSearchBar(
                    controller: _saleSearchCtrl,
                    focusNode: _saleSearchFocusNode,
                    foundCount: (_saleQuery.isNotEmpty ||
                            _selectedDate != null ||
                            _statusFilter != SalesStatusFilter.all)
                        ? visibleChecksCount
                        : null,
                    statusFilter: _statusFilter,
                    onStatusFilterChanged: (filter) {
                      _trackUserActivity();
                      setState(() {
                        _statusFilter = filter;
                        _expandedSaleId = null;
                        _expandedRefundId = null;
                      });
                    },
                    onSubmit: () {
                      _trackUserActivity();
                      _applySaleSearch();
                    },
                    onOpenKeyboard: () {
                      _trackUserActivity();
                      _openSaleKeyboard();
                    },
                    onClear: () {
                      _trackUserActivity();
                      _saleSearchCtrl.clear();
                      setState(() {
                        _expandedSaleId = null;
                        _expandedRefundId = null;
                      });
                      _applySaleSearch();
                    },
                    selectedDate: _selectedDate,
                    onPickDate: () {
                      _trackUserActivity();
                      _pickDate();
                    },
                    onClearDate: () {
                      _trackUserActivity();
                      setState(() {
                        _selectedDate = null;
                        _expandedSaleId = null;
                        _expandedRefundId = null;
                      });
                    },
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFF1F1F1),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: showingRefunds
                                ? _RefundsHistoryHeader(
                                    showReason: showRefundReason,
                                  )
                                : const SalesHistoryHeader(),
                          ),
                          Expanded(
                            child: state.loading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.grey))
                                : state.error != null
                                    ? ErrorBlock(
                                        message: state.error!,
                                        onRetry: () {
                                          _trackUserActivity();
                                          final key = context
                                                  .read<AuthTokenProvider>()
                                                  .posKey
                                                  ?.trim() ??
                                              '';
                                          if (key.isNotEmpty) {
                                            _cubit.loadFirst(key: key);
                                          }
                                        },
                                      )
                                    : ScrollConfiguration(
                                        behavior: AppScrollBehavior(),
                                        child: Scrollbar(
                                          controller: _scrollController,
                                          thumbVisibility: true,
                                          trackVisibility: true,
                                          interactive: true,
                                          thickness: 10,
                                          radius: const Radius.circular(12),
                                          child: showingRefunds
                                              ? ListView.separated(
                                                  controller: _scrollController,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 16,
                                                    vertical: 0,
                                                  ),
                                                  itemCount:
                                                      visibleRefunds.length,
                                                  separatorBuilder: (_, __) =>
                                                      const SizedBox(
                                                          height: 14),
                                                  itemBuilder: (_, index) {
                                                    final refund =
                                                        visibleRefunds[index];
                                                    return _RefundHistoryCard(
                                                      refund: refund,
                                                      showReason:
                                                          showRefundReason,
                                                      expanded:
                                                          _expandedRefundId ==
                                                              refund.id,
                                                      onTap: () {
                                                        _trackUserActivity();
                                                        setState(() {
                                                          _expandedRefundId =
                                                              _expandedRefundId ==
                                                                      refund.id
                                                                  ? null
                                                                  : refund.id;
                                                          _expandedSaleId =
                                                              null;
                                                        });
                                                      },
                                                    );
                                                  },
                                                )
                                              : ListView.separated(
                                                  controller: _scrollController,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 16,
                                                      vertical: 0),
                                                  itemCount:
                                                      saleListEntries.length,
                                                  separatorBuilder: (_, index) {
                                                    final current =
                                                        saleListEntries[index];
                                                    final next =
                                                        saleListEntries[
                                                            index + 1];
                                                    final nearSession = current
                                                            is _SessionHeaderEntry ||
                                                        next
                                                            is _SessionHeaderEntry;
                                                    return SizedBox(
                                                      height:
                                                          nearSession ? 6 : 14,
                                                    );
                                                  },
                                                  itemBuilder: (_, index) {
                                                    final entry =
                                                        saleListEntries[index];
                                                    if (entry
                                                        is _SessionHeaderEntry) {
                                                      return _MinimalSessionDivider(
                                                        session: entry.session,
                                                        summary: entry.summary,
                                                      );
                                                    }

                                                    final sale =
                                                        (entry as _SaleEntry)
                                                            .sale;
                                                    final expanded =
                                                        _expandedSaleId ==
                                                            sale.localId;
                                                    final saleId = sale.localId;
                                                    final printKey =
                                                        _salePrintKey(sale);

                                                    return SaleCard(
                                                      sale: sale,
                                                      cashierName:
                                                          savedCashierName,
                                                      expanded: expanded,
                                                      refundLoading: _controller
                                                          .isRefundLoading(
                                                              saleId),
                                                      receiptPrintLoading:
                                                          _controller
                                                              .isReceiptPrintLoading(
                                                                  printKey),
                                                      receiptPrintDisabled:
                                                          _controller
                                                              .isReceiptPrintDisabled(
                                                                  printKey),
                                                      invoicePrintLoading:
                                                          _controller
                                                              .isInvoicePrintLoading(
                                                                  printKey),
                                                      invoicePrintDisabled:
                                                          _controller
                                                              .isInvoicePrintDisabled(
                                                                  printKey),
                                                      selectedCount: _controller
                                                          .selectedItemsCount(
                                                              saleId),
                                                      selectedTotal: _controller
                                                          .selectedTotal(
                                                              saleId),
                                                      onSubmitRefund: () {
                                                        _trackUserActivity();
                                                        _openRefundPickDialog(
                                                            context, sale);
                                                      },
                                                      onPrintReceipt: () {
                                                        _trackUserActivity();
                                                        _printSaleReceipt(sale);
                                                      },
                                                      onPrintInvoice: () {
                                                        _trackUserActivity();
                                                        _printInvoice(sale);
                                                      },
                                                      onToggle: () {
                                                        _trackUserActivity();
                                                        if (!expanded) {
                                                          _logOpenedSale(sale);
                                                        }
                                                        setState(() {
                                                          _expandedSaleId =
                                                              expanded
                                                                  ? null
                                                                  : sale
                                                                      .localId;
                                                          _expandedRefundId =
                                                              null;
                                                        });
                                                      },
                                                      picks: _controller
                                                          .salePickMap(saleId),
                                                      onToggleItem:
                                                          (item, checked) =>
                                                              setState(() {
                                                        _trackUserActivity();
                                                        _controller.toggleItem(
                                                          saleId: saleId,
                                                          item: item,
                                                          checked: checked,
                                                          notify: () {},
                                                        );
                                                      }),
                                                      onQtyChanged: (item, q) =>
                                                          setState(() {
                                                        _trackUserActivity();
                                                        _controller.changeQty(
                                                          saleId: saleId,
                                                          item: item,
                                                          newQty: q,
                                                          notify: () {},
                                                        );
                                                      }),
                                                      refundedQtyOf: _controller
                                                          .refundedQtyOf,
                                                      availableQtyOf:
                                                          _controller
                                                              .availableQtyOf,
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SalesHistoryTotalsBar(
                    checksCount: visibleChecksCount,
                    totalAmount: visibleTotalAmount,
                    countLabel: showingRefunds
                        ? 'Количество возвратов'
                        : 'Количество чеков',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

abstract class _SalesHistoryListEntry {
  const _SalesHistoryListEntry();
}

class _SessionHeaderEntry extends _SalesHistoryListEntry {
  const _SessionHeaderEntry({
    required this.session,
    required this.summary,
  });

  final LocalSession? session;
  final _SessionSalesSummary summary;
}

class _SaleEntry extends _SalesHistoryListEntry {
  const _SaleEntry(this.sale);

  final SaleModel sale;
}

class _SessionSalesSummary {
  const _SessionSalesSummary({
    this.count = 0,
    this.total = 0,
  });

  final int count;
  final num total;

  _SessionSalesSummary add(num amount) {
    return _SessionSalesSummary(
      count: count + 1,
      total: total + amount,
    );
  }
}

class _MinimalSessionDivider extends StatelessWidget {
  const _MinimalSessionDivider({
    required this.session,
    required this.summary,
  });

  final LocalSession? session;
  final _SessionSalesSummary summary;

  String _time(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = session?.isOpened == true && session?.closedAt == null;
    final sessionLabel = session == null
        ? 'Продажи без смены'
        : isOpen
            ? 'Открытие смены'
            : 'Закрытие смены';
    final sessionDate = session == null
        ? '-'
        : isOpen
            ? _time(session?.openedAt)
            : _time(session?.closedAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: _SessionTimeLine(
                label: sessionLabel,
                value: sessionDate,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SessionMetric(label: 'Чеков', value: '${summary.count}'),
          const SizedBox(width: 6),
          _SessionMetric(label: 'Сумма', value: money2(summary.total)),
        ],
      ),
    );
  }
}

class _SessionTimeLine extends StatelessWidget {
  const _SessionTimeLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF334155),
          height: 1.05,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SessionHistoryHeaderCard extends StatelessWidget {
  const _SessionHistoryHeaderCard({
    required this.session,
    required this.summary,
  });

  final LocalSession? session;
  final _SessionSalesSummary summary;

  String _time(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String get _title {
    if (session == null) return 'Продажи без смены';
    final id = session!.serverSessionId?.trim().isNotEmpty == true
        ? session!.serverSessionId!.trim()
        : session!.clientSessionId.trim();
    final shortId = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'Смена $shortId';
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = session?.isOpened == true && session?.closedAt == null;
    final statusText = session == null
        ? 'Не указана'
        : isOpen
            ? 'Открыта'
            : 'Закрыта';
    final statusColor = session == null
        ? const Color(0xFF64748B)
        : isOpen
            ? const Color(0xFF15803D)
            : const Color(0xFF334155);
    final statusBg = session == null
        ? const Color(0xFFE2E8F0)
        : isOpen
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8DEE8)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F0EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              size: 21,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Открытие: ${_time(session?.openedAt)}   Закрытие: ${_time(session?.closedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _SessionMetric(label: 'Чеков', value: '${summary.count}'),
          const SizedBox(width: 10),
          _SessionMetric(label: 'Сумма', value: money2(summary.total)),
        ],
      ),
    );
  }
}

class _SessionMetric extends StatelessWidget {
  const _SessionMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              height: 1,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundDialogReceiptHeader extends StatelessWidget {
  const _RefundDialogReceiptHeader({
    required this.sale,
    required this.cashierName,
  });

  final SaleModel sale;
  final String cashierName;

  String get _paymentLabel {
    switch (sale.paymentMethod.trim().toLowerCase()) {
      case 'cash':
        return 'Наличными';
      case 'card':
        return 'Безналичными';
      case 'mixed':
        return 'Смешанная';
      case 'credit':
      case 'debt':
      case 'partial_debt':
        return 'В долг';
      case 'closed':
      case 'close':
        return 'Закрыт';
      default:
        final raw = sale.paymentMethod.trim();
        return raw.isEmpty ? '-' : raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.inter(
      fontSize: 18,
      height: 1.4,
      letterSpacing: 0.18,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    );
    final strongStyle = GoogleFonts.inter(
      fontSize: 20,
      height: 1.4,
      letterSpacing: 0.27,
      fontWeight: FontWeight.w700,
      color: Colors.black,
    );
    final amountStyle = GoogleFonts.inter(
      fontSize: 20,
      height: 1.4,
      letterSpacing: 0.27,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 14,
            child: Text(
              saleNumber(sale),
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          Expanded(
            flex: 28,
            child: Text(
              fmtSaleDate(sale.date),
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          Expanded(
            flex: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBE9C5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _paymentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    height: 1.4,
                    letterSpacing: 0.34,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF258808),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 15,
            child: Text(
              cashierName,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: strongStyle,
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              money2(sale.totalAmount),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: amountStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundDialogTotal extends StatelessWidget {
  const _RefundDialogTotal({
    required this.count,
    required this.total,
  });

  final int count;
  final num total;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            'Выбрано товаров: $count',
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF5F6772),
            ),
          ),
          const Spacer(),
          Text(
            'Итого возврат',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            money2(total),
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 22,
              height: 1.4,
              letterSpacing: 0.27,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptPreviewDialog extends StatelessWidget {
  const _ReceiptPreviewDialog({required this.receipt});

  final ReceiptPdfData receipt;

  String _qty(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Предпросмотр чека',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Center(
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F111827),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.25,
                          color: Colors.black,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              receipt.storeName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              receipt.documentTitle ?? 'КАССОВЫЙ ЧЕК',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ReceiptPreviewRow(
                              label: 'Номер',
                              value: receipt.receiptNumber,
                            ),
                            _ReceiptPreviewRow(
                              label: 'Дата',
                              value: fmtSaleDate(receipt.receiptDate),
                            ),
                            _ReceiptPreviewRow(
                              label: 'Кассир',
                              value: receipt.cashierName,
                            ),
                            _ReceiptPreviewRow(
                              label: 'Оплата',
                              value: receipt.paymentMethodLabel,
                            ),
                            const _ReceiptPreviewDivider(),
                            for (final item in receipt.items) ...[
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              _ReceiptPreviewRow(
                                label:
                                    '${_qty(item.quantity)} x ${receipt.money(item.unitPrice)}',
                                value: receipt.money(item.lineTotal),
                              ),
                              const SizedBox(height: 8),
                            ],
                            const _ReceiptPreviewDivider(),
                            _ReceiptPreviewRow(
                              label: 'Итого',
                              value: receipt.money(receipt.total),
                              emphasized: true,
                            ),
                            if (receipt.paidNow != null)
                              _ReceiptPreviewRow(
                                label: 'Оплачено',
                                value: receipt.money(receipt.paidNow!),
                              ),
                            if (receipt.debtAmount != null)
                              _ReceiptPreviewRow(
                                label: 'Долг',
                                value: receipt.money(receipt.debtAmount!),
                              ),
                            const SizedBox(height: 14),
                            Text(
                              receipt.footerText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: const Color(0xFF374151),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Закрыть',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text(
                          'Распечатать',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: const Color(0xFF33CC99),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
    );
  }
}

class _ReceiptPreviewRow extends StatelessWidget {
  const _ReceiptPreviewRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
              fontSize: emphasized ? 14 : 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptPreviewDivider extends StatelessWidget {
  const _ReceiptPreviewDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: Color(0xFF9CA3AF)),
    );
  }
}

class _RefundsHistoryHeader extends StatelessWidget {
  const _RefundsHistoryHeader({required this.showReason});

  final bool showReason;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: Color(0xFF5F6772),
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      child: Row(
        children: [
          const Expanded(flex: 14, child: Text('Номер', style: style)),
          const Expanded(flex: 24, child: Text('Дата', style: style)),
          const Expanded(flex: 16, child: Text('Тип', style: style)),
          if (showReason)
            const Expanded(flex: 20, child: Text('Причина', style: style)),
          const Expanded(
            flex: 14,
            child: Text('Сумма', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _RefundHistoryCard extends StatelessWidget {
  const _RefundHistoryCard({
    required this.refund,
    required this.showReason,
    required this.expanded,
    required this.onTap,
  });

  final RefundModel refund;
  final bool showReason;
  final bool expanded;
  final VoidCallback onTap;

  String get _typeLabel {
    final saleId = (refund.saleId ?? '').trim();
    return saleId.isEmpty ? 'Без чека' : 'С чеком';
  }

  @override
  Widget build(BuildContext context) {
    final date = refund.date;
    final reason = (refund.reason ?? refund.note ?? '').trim().isNotEmpty
        ? (refund.reason ?? refund.note ?? '').trim()
        : refundReasonLabel(refund.reasonCode);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 14,
                      child: Text(
                        refundNumber(refund),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 24,
                      child: Text(
                        date == null ? '-' : fmtSaleDate(date),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    Expanded(
                      flex: 16,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _RefundChip(
                          label: _typeLabel,
                          background: const Color(0xFFFFEDD5),
                          foreground: const Color(0xFF9A3412),
                        ),
                      ),
                    ),
                    if (showReason)
                      Expanded(
                        flex: 20,
                        child: Text(
                          reason,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    Expanded(
                      flex: 14,
                      child: Text(
                        money2(refund.totalAmount ?? 0),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) _RefundDetailsPanel(refund: refund),
          ],
        ),
      ),
    );
  }
}

class _RefundDetailsPanel extends StatelessWidget {
  const _RefundDetailsPanel({required this.refund});

  final RefundModel refund;

  @override
  Widget build(BuildContext context) {
    final note = (refund.note ?? '').trim();
    final reason = (refund.reason ?? '').trim().isNotEmpty
        ? (refund.reason ?? '').trim()
        : refundReasonLabel(refund.reasonCode);
    final items = refund.items.map(_toSaleItem).toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (reason.isNotEmpty)
                _RefundInfoPill(label: 'Причина', value: reason),
              if (note.isNotEmpty)
                _RefundInfoPill(label: 'Заметка', value: note),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Товары',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text(
              'Позиции не указаны',
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            )
          else
            SaleItemsBox(
              items: items,
              picks: const {},
              selectable: false,
              onToggleItem: (_, __) {},
              onQtyChanged: (_, __) {},
              refundedQtyOf: (_) => 0,
              availableQtyOf: (item) => item.quantity.round(),
            ),
        ],
      ),
    );
  }

  SaleItemModel _toSaleItem(RefundItemModel item) {
    final qty = item.quantity.toDouble();
    final price = item.price.toDouble();
    return SaleItemModel(
      id: item.saleItemId.trim().isNotEmpty ? item.saleItemId : item.id,
      saleId: refund.saleId ?? '',
      productId: item.productId,
      product: item.product,
      quantity: qty,
      price: price,
      totalPrice: qty * price,
    );
  }
}

class _RefundInfoPill extends StatelessWidget {
  const _RefundInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundChip extends StatelessWidget {
  const _RefundChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _SalesHistoryTotalsBar extends StatelessWidget {
  const _SalesHistoryTotalsBar({
    required this.checksCount,
    required this.totalAmount,
    this.countLabel = 'Количество чеков',
  });

  final int checksCount;
  final num totalAmount;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFCF8),
        border: Border(
          top: BorderSide(color: Color(0xFFE6E0D8)),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _TotalsTile(
                label: countLabel,
                value: '$checksCount',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TotalsTile(
                label: 'Общая сумма',
                value: money(totalAmount),
                emphasized: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsTile extends StatelessWidget {
  const _TotalsTile({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFE9F0EB) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasized ? const Color(0xFFC9D7CF) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: emphasized ? 24 : 22,
                  color: const Color(0xFF17211C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
