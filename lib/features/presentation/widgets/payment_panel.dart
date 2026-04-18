import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:leemon_app/core/di/api/service_locator.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/core/print/print_service.dart';
import 'package:leemon_app/core/print/receipt_pdf_builder.dart';
import 'package:leemon_app/core/provider/auth_provider.dart'
    show AuthTokenProvider;
import 'package:leemon_app/features/data/sync/pos_sync_models.dart';
import 'package:leemon_app/features/data/sync/pos_sync_service.dart';
import 'package:leemon_app/features/domain/repositories/sale_repository.dart';
import 'package:leemon_app/features/presentation/pages/products/state/pos_cubit.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_dialog.dart';
import 'package:leemon_app/features/presentation/pages/search/widgets/customer_create_page.dart';
import 'package:leemon_app/features/presentation/widgets/last_sale_amount_notifier.dart';
import 'package:uuid/uuid.dart';
import '../../data/utils/money.dart';
import '../../domain/entities/payment.dart';

class PaymentPanel extends StatefulWidget {
  const PaymentPanel({super.key});

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<PaymentPanel> {
  final _cashCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _cashFocusNode = FocusNode();
  final _cardFocusNode = FocusNode();
  bool _paying = false;
  bool _paymentSuccess = false;
  bool _openingCustomerPicker = false;
  bool _isMixedPayment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<PosCubit>();
      cubit.setPaymentKind(PaymentKind.cash);
      cubit.setReceived(0);
      _cashCtrl.clear();
      _cardCtrl.clear();
      _cashFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cardFocusNode.dispose();
    _cashFocusNode.dispose();
    _cardCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
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
              balance: 0,
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
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  final _printService = PrintService();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 500,
      width: 573,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: BlocConsumer<PosCubit, PosState>(
          listenWhen: (prev, curr) => prev.received != curr.received,
          listener: (context, state) {
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
            final hasSelectedPaymentMethod =
                state.paymentKind == PaymentKind.card ||
                    state.paymentKind == PaymentKind.credit ||
                    state.received > 0;
            final canSubmitPayment =
                !_paying && hasItems && hasSelectedPaymentMethod;

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

              if (key.isEmpty) return;
              if (deviceId.isEmpty) return;
              if (storeId.isEmpty) return;
              if (posId.isEmpty) return;
              if (userId.isEmpty) return;
              if (fallbackAccountId.isEmpty) return;
              if (posCubit.state.items.isEmpty) return;

              if (posCubit.state.paymentKind == PaymentKind.cash &&
                  !_isMixedPayment &&
                  posCubit.state.received < posCubit.total) {
                return;
              }

              // Capture amounts before async gap
              final isMixed = _isMixedPayment;
              final cashInputAmt = _parseAmount(_cashCtrl.text).round();

              final saleItems = <SaleItemModel>[];
              for (final it in posCubit.state.items) {
                final cv = it.product.conversionValue;
                final qty = (cv != null && cv > 0) ? (it.qty * cv) : it.qty;
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
                  ),
                );
              }

              final paymentMethod = isMixed
                  ? 'mixed'
                  : switch (posCubit.state.paymentKind) {
                      PaymentKind.cash => 'cash',
                      PaymentKind.card => 'card',
                      PaymentKind.credit => 'credit',
                    };

              final customerId =
                  context.read<PosCubit>().state.activeCustomer?.id;

              final saleLocalId = const Uuid().v4();
              final totalAmountInt = posCubit.total.round();
              final exactTotal = double.parse(
                saleItems
                    .fold(0.0, (s, e) => s + e.totalPrice)
                    .toStringAsFixed(2),
              );

              final sale = SaleModel(
                localId: saleLocalId,
                number: '',
                date: DateTime.now(),
                totalAmount: totalAmountInt,
                paymentMethod: paymentMethod,
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
                          arrivalCost: 0,
                          sellingPrice: posCubit
                              .state.items[entry.key].effectiveUnitPrice,
                          wholesalePrice: 0,
                        ),
                      ),
                    )
                    .toList(),
              );

              // Load accounts to find cash/card account IDs
              final accounts = await sl<PosSyncService>().loadAccounts();
              final cashAccount = accounts.firstWhere(
                (a) => a.isCash,
                orElse: () => LocalAccount(id: fallbackAccountId, name: ''),
              );
              final cardAccount = accounts.firstWhere(
                (a) => !a.isCash && a.id != cashAccount.id,
                orElse: () => cashAccount,
              );

              final List<Map<String, dynamic>> payments;
              if (isMixed) {
                final cashAmt = double.parse(
                  cashInputAmt.clamp(0, exactTotal).toStringAsFixed(2),
                );
                final cardAmt = double.parse(
                  (exactTotal - cashAmt).toStringAsFixed(2),
                );
                payments = [
                  {
                    'account_id': cashAccount.id,
                    'amount': cashAmt,
                    'client_payment_id': '$saleLocalId-cash',
                  },
                  {
                    'account_id': cardAccount.id,
                    'amount': cardAmt,
                    'client_payment_id': '$saleLocalId-card',
                  },
                ];
              } else if (paymentMethod == 'card') {
                payments = [
                  {
                    'account_id': cardAccount.id,
                    'amount': exactTotal,
                    'client_payment_id': '$saleLocalId-card',
                  },
                ];
              } else {
                payments = [
                  {
                    'account_id': cashAccount.id,
                    'amount': exactTotal,
                    'client_payment_id': '$saleLocalId-cash',
                  },
                ];
              }

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
                final paymentKind = posCubit.state.paymentKind;
                final outcome = await repo.createSale(
                  key: key,
                  deviceId: deviceId,
                  sale: sale,
                  payments: payments,
                );
                final result = outcome.result;
                final printedSale = outcome.sale;

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
                      paymentMethodLabel: switch (paymentKind) {
                        PaymentKind.cash => 'Наличные',
                        PaymentKind.card => 'Безналичный',
                        PaymentKind.credit => 'В долг',
                      },
                      isCashPayment: paymentKind == PaymentKind.cash,
                      received: posCubit.state.received,
                      change: posCubit.change,
                    ),
                  ),
                  printerName: auth.receiptPrinterName,
                );

                if (!context.mounted) return;
                if (result == CreateSaleResult.rejected) return;
                saleCompleted = true;
                lastSaleAmountNotifier.value = printedSale.totalAmount;
                setState(() {
                  _paying = false;
                  _paymentSuccess = true;
                });
                await Future.delayed(const Duration(milliseconds: 950));
                if (!mounted) return;
                Navigator.of(this.context).pop();
                posCubit.clearAfterPayment();
              } catch (_) {
                if (!mounted) return;
              } finally {
                if (mounted && !saleCompleted) {
                  setState(() => _paying = false);
                }
              }
            }

            bool useCardInput() {
              if (_isMixedPayment) return _cardFocusNode.hasFocus;
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

            void setMixedCashText(String text) {
              _setText(context, text, applyToState: false);
              _setCardText(
                context,
                complementText(text),
                applyToState: false,
              );
              cubit.setReceived(total);
            }

            void setMixedCardText(String text) {
              _setCardText(context, text, applyToState: false);
              _setText(
                context,
                complementText(text),
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

            void addQuick(int inc) {
              final curr =
                  double.tryParse(activeText().replaceAll(',', '.')) ?? 0;
              final next = curr + inc;
              setActiveText(_fmt(next));
            }

            final customerName = state.activeCustomer?.name.trim();
            final customerButtonText =
                (customerName != null && customerName.isNotEmpty)
                    ? customerName
                    : 'ПОКУПАТЕЛЬ';
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
                          height: 493.296,
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
                              setState(() => _isMixedPayment = false);
                              cubit.setPaymentKind(PaymentKind.cash);
                              _cashFocusNode.requestFocus();
                            },
                            onCard: () {
                              setState(() => _isMixedPayment = false);
                              cubit.setPaymentKind(PaymentKind.card);
                              _setCardText(context, _fmt(total));
                              _cardFocusNode.requestFocus();
                            },
                            onMixed: () {
                              setState(() => _isMixedPayment = true);
                              cubit.setPaymentKind(PaymentKind.cash);
                              final cashText = _cashCtrl.text.trim().isEmpty
                                  ? '0'
                                  : _cashCtrl.text;
                              _setText(
                                context,
                                cashText,
                                applyToState: false,
                              );
                              _setCardText(
                                context,
                                complementText(cashText),
                                applyToState: false,
                              );
                              cubit.setReceived(total);
                              _cashFocusNode.requestFocus();
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
                              onChanged: (v) {
                                if (_isMixedPayment) {
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
                              onChanged: (v) {
                                if (_isMixedPayment) {
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
                        Positioned(
                          left: 299.934,
                          top: 323.387,
                          width: 256.169,
                          height: 29.1575,
                          child: _WhiteButton(
                            text: customerButtonText,
                            onTap: _pickCustomer,
                            borderRadius: 4.64873,
                            borderColor: Colors.black,
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
                                ? () => cubit.setPaymentKind(PaymentKind.credit)
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
                            selected: false,
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

  static const double _tabHeight = 42;
  static const double _dividerTop = 6;
  static const double _dividerHeight = 30;

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
            SizedBox(
              height: _tabHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: 180.59,
                    child: _PaymentTabButton(
                      text: 'Наличные',
                      selected: !mixed && paymentKind == PaymentKind.cash,
                      onTap: onCash,
                    ),
                  ),
                  SizedBox(
                    width: 171.205,
                    child: _PaymentTabButton(
                      text: 'Безналичные',
                      selected: !mixed && paymentKind == PaymentKind.card,
                      onTap: onCard,
                    ),
                  ),
                  SizedBox(
                    width: 189.97,
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
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        foregroundColor: selected ? Colors.white : Colors.black,
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
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final Color borderColor;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.502),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 8,
            top: 7,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: const Color(0xFF8A8A8A),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1,
              ),
            ),
          ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            readOnly: readOnly,
            enableInteractiveSelection: !readOnly,
            onChanged: onChanged,
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
              fontWeight: FontWeight.w900,
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
    final bg = selected ? const Color(0xFF33CC99) : const Color(0xFFBBBBBB);

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
