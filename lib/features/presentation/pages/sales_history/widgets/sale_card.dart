import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/sale_model.dart';

import '../models/refund_pick.dart';
import '../utils/formatters.dart';
import '../utils/sales_filter.dart';
import 'bottom_action_button.dart';
import 'sale_items_box.dart';
import 'status_chip.dart';

class SaleCard extends StatelessWidget {
  const SaleCard({
    super.key,
    required this.sale,
    required this.cashierName,
    required this.expanded,
    required this.onToggle,
    required this.refundLoading,
    required this.receiptPrintLoading,
    required this.receiptPrintDisabled,
    required this.invoicePrintLoading,
    required this.invoicePrintDisabled,
    required this.onSubmitRefund,
    required this.onPrintReceipt,
    required this.showLocalPrint,
    required this.showFiscalPrint,
    required this.onPrintFiscalReceipt,
    required this.onPrintInvoice,
    required this.selectedCount,
    required this.selectedTotal,
    required this.picks,
    required this.onToggleItem,
    required this.onQtyChanged,
    required this.refundedQtyOf,
    required this.availableQtyOf,
  });

  final SaleModel sale;
  final String cashierName;
  final bool expanded;
  final VoidCallback onToggle;

  final bool refundLoading;
  final bool receiptPrintLoading;
  final bool receiptPrintDisabled;
  final bool invoicePrintLoading;
  final bool invoicePrintDisabled;
  final VoidCallback onSubmitRefund;
  final VoidCallback onPrintReceipt;
  final bool showLocalPrint;
  final bool showFiscalPrint;
  final VoidCallback onPrintFiscalReceipt;
  final VoidCallback onPrintInvoice;

  final int selectedCount;
  final num selectedTotal;

  final Map<String, RefundPick> picks;
  final void Function(SaleItemModel item, bool checked) onToggleItem;
  final void Function(SaleItemModel item, int qty) onQtyChanged;

  final int Function(SaleItemModel item) refundedQtyOf;
  final int Function(SaleItemModel item) availableQtyOf;

  static const _radius = 22.0;
  static const _rowTextStyle = TextStyle(
    fontSize: 18,
    height: 1.4,
    letterSpacing: 0.18,
    fontWeight: FontWeight.w500,
    color: Colors.black,
  );
  static const _cashierTextStyle = TextStyle(
    fontSize: 18,
    height: 1.4,
    letterSpacing: 0.27,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  bool get hasRefund {
    final refund = sale.refund;
    if (refund == null) return false;

    return refund.id.trim().isNotEmpty ||
        (refund.totalAmount ?? 0) > 0 ||
        refund.items.isNotEmpty;
  }

  String get paymentLabel {
    switch (sale.paymentMethod.trim().toLowerCase()) {
      case 'cash':
        return 'Наличными';
      case 'card':
        return 'Безналичными';
      case 'closed':
      case 'close':
        return 'Закрыт';
      case 'mixed':
        return 'Смешанная';
      case 'credit':
      case 'debt':
      case 'partial_debt':
        return 'В долг';
      default:
        final raw = sale.paymentMethod.trim();
        return raw.isEmpty ? '-' : raw;
    }
  }

  Color get paymentBg {
    return const Color(0xFFCBE9C5);
  }

  Color get paymentFg {
    return const Color(0xFF258808);
  }

  Color get actionBlueMuted => const Color(0xFF33B5CC);
  Color get actionDarkMuted => const Color(0xFF6F7671);

  List<SalePaymentModel> get paymentDetails {
    final method = sale.paymentMethod.trim().toLowerCase();
    if (method != 'card' && method != 'mixed') {
      return const <SalePaymentModel>[];
    }

    final payments = sale.payments
        .where((payment) => payment.amount > 0)
        .toList(growable: false);
    if (payments.isNotEmpty) return payments;

    if (method == 'card') {
      return [
        SalePaymentModel(
          accountId: sale.accountId,
          amount: sale.totalAmount,
        ),
      ];
    }

    return const <SalePaymentModel>[];
  }

  String get cashierDisplayName {
    final name = cashierName.trim();
    if (name.isNotEmpty) return name;
    return cashierLabel(sale);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final desktopNarrow = !compact && constraints.maxWidth < 1400;
        final actionWidth = (constraints.maxWidth - 36).clamp(180.0, 520.0);
        final refundBtnWidth = desktopNarrow ? 98.0 : 112.0;
        final invoiceBtnWidth = desktopNarrow ? 130.0 : 170.0;
        final printBtnWidth = desktopNarrow ? 180.0 : 220.0;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Column(
              children: [
                InkWell(
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 13),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      saleNumber(sale),
                                      overflow: TextOverflow.ellipsis,
                                      style: _rowTextStyle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      fmtSaleDate(sale.date),
                                      overflow: TextOverflow.ellipsis,
                                      style: _rowTextStyle,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Flexible(
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        StatusChip(
                                            label: paymentLabel,
                                            bg: paymentBg,
                                            fg: paymentFg),
                                        if (hasRefund)
                                          const _RefundStatusBadge(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      cashierDisplayName,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: _cashierTextStyle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 132,
                                    child: _AmountText(
                                      value: money2(sale.totalAmount),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.more_horiz,
                                      size: 22,
                                      color:
                                          Colors.black.withValues(alpha: 0.55)),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                flex: 14,
                                child: Text(
                                  saleNumber(sale),
                                  overflow: TextOverflow.ellipsis,
                                  style: _rowTextStyle,
                                ),
                              ),
                              Expanded(
                                flex: 28,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    fmtSaleDate(sale.date),
                                    overflow: TextOverflow.ellipsis,
                                    style: _rowTextStyle,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 16,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      StatusChip(
                                          label: paymentLabel,
                                          bg: paymentBg,
                                          fg: paymentFg),
                                      if (hasRefund) const _RefundStatusBadge(),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 15,
                                child: Text(cashierDisplayName,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: _cashierTextStyle),
                              ),
                              Expanded(
                                flex: 14,
                                child: _AmountText(
                                  value: money2(sale.totalAmount),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                expanded ? Icons.expand_less : Icons.more_horiz,
                                size: 22,
                                color: const Color(0xFF596579),
                              ),
                            ],
                          ),
                  ),
                ),
                if (expanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SaleItemsBox(
                          items: sale.items,
                          picks: picks,
                          onToggleItem: onToggleItem,
                          onQtyChanged: onQtyChanged,
                          refundedQtyOf: refundedQtyOf,
                          availableQtyOf: availableQtyOf,
                          selectable: false,
                        ),
                        if (paymentDetails.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _PaymentDetailsPanel(payments: paymentDetails),
                        ],
                        const SizedBox(height: 14),
                        if (compact) ...[
                          BottomActionButton(
                            label: 'Возврат',
                            width: actionWidth,
                            fontSize: 16,
                            bg: const Color(0xFF8D8D8D),
                            onTap: refundLoading ? null : onSubmitRefund,
                            loading: refundLoading,
                            horizontalPadding: 8,
                          ),
                          const SizedBox(height: 12),
                          BottomActionButton(
                            label: 'Накладная',
                            width: actionWidth,
                            fontSize: 16,
                            bg: actionBlueMuted,
                            onTap: invoicePrintDisabled ? null : onPrintInvoice,
                            loading: invoicePrintLoading,
                          ),
                          const SizedBox(height: 12),
                          if (showLocalPrint)
                            BottomActionButton(
                              label: 'Распечатать чек',
                              width: actionWidth,
                              fontSize: 16,
                              bg: actionBlueMuted,
                              onTap:
                                  receiptPrintDisabled ? null : onPrintReceipt,
                              loading: receiptPrintLoading,
                            ),
                          if (showFiscalPrint) ...[
                            const SizedBox(height: 12),
                            BottomActionButton(
                              label: 'Фискальный чек',
                              width: actionWidth,
                              fontSize: 16,
                              bg: actionBlueMuted,
                              onTap: receiptPrintDisabled
                                  ? null
                                  : onPrintFiscalReceipt,
                              loading: receiptPrintLoading,
                            ),
                          ],
                        ] else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              BottomActionButton(
                                label: 'Возврат',
                                width: refundBtnWidth,
                                fontSize: 16,
                                bg: const Color(0xFF8D8D8D),
                                onTap: refundLoading ? null : onSubmitRefund,
                                loading: refundLoading,
                                horizontalPadding: 8,
                              ),
                              const SizedBox(width: 12),
                              BottomActionButton(
                                  label: 'Накладная',
                                  width: invoiceBtnWidth,
                                  fontSize: 16,
                                  bg: actionBlueMuted,
                                  onTap: invoicePrintDisabled
                                      ? null
                                      : onPrintInvoice,
                                  loading: invoicePrintLoading),
                              if (showLocalPrint) ...[
                                const SizedBox(width: 12),
                                BottomActionButton(
                                    label: 'Распечатать чек',
                                    width: printBtnWidth,
                                    fontSize: 16,
                                    bg: actionBlueMuted,
                                    onTap: receiptPrintDisabled
                                        ? null
                                        : onPrintReceipt,
                                    loading: receiptPrintLoading),
                              ],
                              if (showFiscalPrint) ...[
                                const SizedBox(width: 12),
                                BottomActionButton(
                                  label: 'Фискальный чек',
                                  width: printBtnWidth,
                                  fontSize: 16,
                                  bg: actionBlueMuted,
                                  onTap: receiptPrintDisabled
                                      ? null
                                      : onPrintFiscalReceipt,
                                  loading: receiptPrintLoading,
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RefundStatusBadge extends StatelessWidget {
  const _RefundStatusBadge();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Есть возврат',
      child: Icon(
        Icons.assignment_return_rounded,
        size: 18,
        color: Color(0xFF16A34A),
      ),
    );
  }
}

class _AmountText extends StatelessWidget {
  const _AmountText({
    required this.value,
    required this.fontWeight,
  });

  final String value;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        value,
        maxLines: 1,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 18,
          height: 1.4,
          letterSpacing: 0.27,
          fontWeight: fontWeight,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _PaymentDetailsPanel extends StatelessWidget {
  const _PaymentDetailsPanel({required this.payments});

  final List<SalePaymentModel> payments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Детали оплаты',
            style: TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 5),
          for (final payment in payments) ...[
            _PaymentDetailRow(payment: payment),
            if (payment != payments.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _PaymentDetailRow extends StatelessWidget {
  const _PaymentDetailRow({required this.payment});

  final SalePaymentModel payment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            payment.accountName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          money2(payment.amount),
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 15,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class SalesHistoryHeader extends StatelessWidget {
  const SalesHistoryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        if (compact) return const SizedBox.shrink();

        return const Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Row(
            children: [
              Expanded(
                flex: 14,
                child: _HeaderText('№ чека'),
              ),
              Expanded(
                flex: 28,
                child: _HeaderText('Время'),
              ),
              Expanded(
                flex: 16,
                child: _HeaderText('Оплата'),
              ),
              Expanded(
                flex: 15,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _HeaderText('Кассир'),
                ),
              ),
              Expanded(
                flex: 14,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _HeaderText('Сумма'),
                ),
              ),
              SizedBox(width: 30),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 18,
        height: 1.4,
        letterSpacing: 0.18,
        fontWeight: FontWeight.w500,
        color: Colors.black,
      ),
    );
  }
}
