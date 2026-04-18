import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';

import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/provider/auth_provider.dart';
import 'package:leemon_app/features/data/sync/pos_sync_models.dart'
    show LocalAccount, QueueSendResult;
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/data/utils/money.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/models/refund_pick.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/error_bloc.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/refund_access_dialog.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_history_controller.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sales_search_bar.dart';
import 'package:leemon_app/features/presentation/widgets/onscreen_keyboar_widget.dart';

import 'state/sales_cubit.dart';
import 'state/sales_state.dart';

import 'utils/app_scroll_behavior.dart';
import 'utils/sales_filter.dart';
import 'widgets/sale_card.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  static const Duration _historyIdleTimeout = Duration(seconds: 30);
  static const Duration _printLoadingDuration = Duration(seconds: 1);
  static const Duration _printCooldownDuration = Duration(seconds: 5);

  String? _expandedSaleId;

  final ScrollController _scrollController = ScrollController();
  late final SalesHistoryCubit _cubit;
  StreamSubscription<void>? _historyChangedSub;

  final _controller = SalesHistoryController();

  final TextEditingController _saleSearchCtrl = TextEditingController();
  Timer? _saleSearchDebounce;
  Timer? _historyRefreshDebounce;
  Timer? _historyIdleTimer;
  String _saleQuery = '';
  DateTime? _selectedDate;
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

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _cancelHistoryIdleTimer() {
    _historyIdleTimer?.cancel();
    _historyIdleTimer = null;
  }

  void _resetHistoryIdleTimer() {
    if (!mounted) return;
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
    _cubit = SalesHistoryCubit(sync);
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

  void _notifyPrintStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _printSaleReceipt(SaleModel sale) async {
    final saleKey = _salePrintKey(sale);
    if (_controller.isReceiptPrintDisabled(saleKey)) return;

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
                    name: (it.product?.name ?? '').trim().isEmpty
                        ? 'Товар ${it.productId}'
                        : it.product!.name,
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
              _ => sale.paymentMethod.trim().isEmpty
                  ? '-'
                  : sale.paymentMethod.trim(),
            },
            isCashPayment: sale.paymentMethod.trim().toLowerCase() == 'cash',
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
                  name: (it.product?.name ?? '').trim().isEmpty
                      ? 'Товар ${it.productId}'
                      : it.product!.name,
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
      });
    }
  }

  void _applySaleSearch() {
    setState(() {
      _saleQuery = _saleSearchCtrl.text.trim();
      _expandedSaleId = null;
    });
  }

  void _openSaleKeyboard() {
    if (_saleKeyboardOpen) return;
    _saleKeyboardOpen = true;

    _runWithDialogFocus(() {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.15),
        builder: (ctx) {
          return OnScreenKeyboardSheet(
            controllerGetter: () => _saleSearchCtrl,
            onEnter: () {
              Navigator.of(ctx).pop();
              _applySaleSearch();
            },
            onClose: () => Navigator.of(ctx).pop(),
          );
        },
      );
    }).whenComplete(() {
      _saleKeyboardOpen = false;
    });
  }

  Future<void> _submitRefund(BuildContext context, SaleModel sale) async {
    final auth = context.read<AuthTokenProvider>();

    final key = auth.posKey?.trim() ?? '';
    final deviceId = auth.deviceId?.trim() ?? '';
    final posSessionId = auth.shiftId?.trim() ?? '';
    final fallbackAccountId = auth.accountId?.trim() ?? '';

    if (key.isEmpty) return _snack('Нет posKey');
    if (deviceId.isEmpty) return _snack('Нет deviceId');
    if (posSessionId.isEmpty) return _snack('Смена не открыта');

    final saleId = sale.localId.trim();
    if (saleId.isEmpty) return _snack('saleId пустой (sale.localId)');
    if (_controller.isRefundLoading(saleId)) return;

    final picks = _controller
        .salePickMap(saleId)
        .values
        .where((e) => e.checked && e.quantity > 0)
        .toList();

    if (picks.isEmpty) return _snack('Выбери товары для возврата');

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

    // Build payments[] based on the original sale's payment method
    final salePaymentMethod = sale.paymentMethod.trim().toLowerCase();
    final refundPaymentMethod = switch (salePaymentMethod) {
      'card' => 'card',
      'mixed' => 'mixed',
      _ => 'cash',
    };

    final accounts = await sync.loadAccounts();
    final cashAccount = accounts.firstWhere(
      (a) => a.isCash,
      orElse: () => LocalAccount(id: fallbackAccountId, name: ''),
    );
    final cardAccount = accounts.firstWhere(
      (a) => !a.isCash && a.id != cashAccount.id,
      orElse: () => cashAccount,
    );

    final refundClientId = 'refund_${DateTime.now().microsecondsSinceEpoch}';
    final List<Map<String, dynamic>> refundPayments;
    if (refundPaymentMethod == 'mixed') {
      final half = totalAmount ~/ 2;
      refundPayments = [
        {
          'account_id': cashAccount.id,
          'amount': half,
          'client_payment_id': '$refundClientId-cash',
        },
        {
          'account_id': cardAccount.id,
          'amount': totalAmount - half,
          'client_payment_id': '$refundClientId-card',
        },
      ];
    } else if (refundPaymentMethod == 'card') {
      refundPayments = [
        {
          'account_id': cardAccount.id,
          'amount': totalAmount,
          'client_payment_id': '$refundClientId-card',
        },
      ];
    } else {
      refundPayments = [
        {
          'account_id': cashAccount.id,
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
                );
                if (result.result == QueueSendResult.manual) {
                  throw Exception(
                    result.errorMessage ?? 'Возврат требует ручной обработки',
                  );
                }
                effectiveRefundId = result.clientId;
                return true; // 200 — доступ есть
              } catch (e) {
                // 401 — доступ нет, диалог покажет ошибку и попросит перескан
                if (_statusCodeOf(e) == 401) return false;
                rethrow; // остальные ошибки покажем как "Ошибка запроса"
              }
            },
          ),
        );
      });

      if (ok != true) return; // отмена/закрытие/нет доступа

      if (!mounted) return;
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
          refundId: effectiveRefundId,
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
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка возврата: $e');
    } finally {
      if (mounted) {
        _controller.setRefundLoading(saleId, false, () => setState(() {}));
      }
    }
  }

  Future<void> _printRefundReceipt({
    required SaleModel sale,
    required List<RefundPick> picks,
    required num totalAmount,
    required String refundId,
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
        name: (item.product?.name ?? '').trim().isEmpty
            ? 'Товар ${item.productId}'
            : item.product!.name,
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
          receiptNumber: formatPosReceiptNumber(
            posNumber: auth.posNumber ?? '',
            saleNumber: refundId,
            fallback: sale.localId,
          ),
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
              final visibleSales =
                  filterSales(state.sales, _saleQuery, date: _selectedDate);
              final savedCashierName =
                  context.read<AuthTokenProvider>().activeUserName ?? '';
              final visibleTotalAmount = visibleSales.fold<num>(
                0,
                (sum, sale) => sum + sale.totalAmount,
              );
              final visibleChecksCount = visibleSales.length;

              return Column(
                children: [
                  SalesSearchBar(
                    controller: _saleSearchCtrl,
                    focusNode: _saleSearchFocusNode,
                    foundCount: (_saleQuery.isNotEmpty || _selectedDate != null)
                        ? visibleSales.length
                        : null,
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
                      setState(() => _expandedSaleId = null);
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
                      });
                    },
                  ),
                  Expanded(
                    child: state.loading
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: Colors.grey))
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
                                  child: ListView.separated(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    itemCount: visibleSales.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, index) {
                                      final sale = visibleSales[index];
                                      final expanded =
                                          _expandedSaleId == sale.localId;
                                      final saleId = sale.localId;
                                      final printKey = _salePrintKey(sale);

                                      return SaleCard(
                                        sale: sale,
                                        cashierName: savedCashierName,
                                        expanded: expanded,
                                        refundLoading:
                                            _controller.isRefundLoading(saleId),
                                        receiptPrintLoading: _controller
                                            .isReceiptPrintLoading(printKey),
                                        receiptPrintDisabled: _controller
                                            .isReceiptPrintDisabled(printKey),
                                        invoicePrintLoading: _controller
                                            .isInvoicePrintLoading(printKey),
                                        invoicePrintDisabled: _controller
                                            .isInvoicePrintDisabled(printKey),
                                        selectedCount: _controller
                                            .selectedItemsCount(saleId),
                                        selectedTotal:
                                            _controller.selectedTotal(saleId),
                                        onSubmitRefund: () {
                                          _trackUserActivity();
                                          _submitRefund(context, sale);
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
                                          setState(() {
                                            _expandedSaleId =
                                                expanded ? null : sale.localId;
                                          });
                                        },
                                        picks: _controller.salePickMap(saleId),
                                        onToggleItem: (item, checked) =>
                                            setState(() {
                                          _trackUserActivity();
                                          _controller.toggleItem(
                                            saleId: saleId,
                                            item: item,
                                            checked: checked,
                                            notify: () {},
                                          );
                                        }),
                                        onQtyChanged: (item, q) => setState(() {
                                          _trackUserActivity();
                                          _controller.changeQty(
                                            saleId: saleId,
                                            item: item,
                                            newQty: q,
                                            notify: () {},
                                          );
                                        }),
                                        refundedQtyOf:
                                            _controller.refundedQtyOf,
                                        availableQtyOf:
                                            _controller.availableQtyOf,
                                      );
                                    },
                                  ),
                                ),
                              ),
                  ),
                  _SalesHistoryTotalsBar(
                    checksCount: visibleChecksCount,
                    totalAmount: visibleTotalAmount,
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

class _SalesHistoryTotalsBar extends StatelessWidget {
  const _SalesHistoryTotalsBar({
    required this.checksCount,
    required this.totalAmount,
  });

  final int checksCount;
  final num totalAmount;

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
                label: 'Количество чеков',
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
          Text(
            value,
            style: TextStyle(
              fontSize: emphasized ? 24 : 22,
              color: const Color(0xFF17211C),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
