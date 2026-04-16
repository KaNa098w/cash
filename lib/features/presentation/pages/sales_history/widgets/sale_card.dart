import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/sale_model.dart';

import '../models/refund_pick.dart';
import '../utils/formatters.dart';
import '../utils/sales_filter.dart';
import 'bottom_action_button.dart';
import 'refund_summary.dart';
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
  final VoidCallback onPrintInvoice;

  final int selectedCount;
  final num selectedTotal;

  final Map<String, RefundPick> picks;
  final void Function(SaleItemModel item, bool checked) onToggleItem;
  final void Function(SaleItemModel item, int qty) onQtyChanged;

  final int Function(SaleItemModel item) refundedQtyOf;
  final int Function(SaleItemModel item) availableQtyOf;

  static const _radius = 22.0;

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
        return 'Наличная';
      case 'card':
        return 'Безналичная';
      case 'credit':
        return 'В долг';
      default:
        final raw = sale.paymentMethod.trim();
        return raw.isEmpty ? '-' : raw;
    }
  }

  Color get paymentBg {
    switch (sale.paymentMethod.trim().toLowerCase()) {
      case 'cash':
        return const Color(0xFFE6F4EA);
      case 'card':
        return const Color(0xFFE0ECFF);
      case 'credit':
        return const Color(0xFFFFE6D6);
      default:
        return const Color(0xFFF3F5F4);
    }
  }

  Color get paymentFg {
    switch (sale.paymentMethod.trim().toLowerCase()) {
      case 'cash':
        return const Color(0xFF258808);
      case 'card':
        return const Color(0xFF1D4ED8);
      case 'credit':
        return const Color(0xFFB54708);
      default:
        return const Color(0xFF425A4E);
    }
  }

  Color get cardShadow => const Color(0x140F172A);
  Color get dateBg => const Color(0xFFF3F5F4);
  Color get dateBorder => const Color(0xFFD9E1DC);
  Color get dateFg => const Color(0xFF425A4E);
  Color get actionBlueMuted => const Color(0xFF6A8C84);
  Color get actionDarkMuted => const Color(0xFF6F7671);
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
        final desktopNarrow = !compact && constraints.maxWidth < 1180;
        final actionWidth = (constraints.maxWidth - 36).clamp(180.0, 520.0);
        final saleNumberWidth = desktopNarrow ? 220.0 : 280.0;
        final dateWidth = desktopNarrow ? 220.0 : 400.0;
        final statusWidth = desktopNarrow ? 190.0 : 250.0;
        final cashierWidth = desktopNarrow ? 170.0 : 250.0;
        final amountWidth = desktopNarrow ? 110.0 : 140.0;
        final refundBtnWidth = desktopNarrow ? 180.0 : 220.0;
        final invoiceBtnWidth = desktopNarrow ? 130.0 : 170.0;
        final printBtnWidth = desktopNarrow ? 180.0 : 220.0;

        return Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(_radius),
              onTap: onToggle,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFEFC),
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: [
                    BoxShadow(
                        color: cardShadow,
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _DateBadge(
                                text: fmtSaleDate(sale.date),
                                bg: dateBg,
                                border: dateBorder,
                                fg: dateFg,
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
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    StatusChip(
                                        label: paymentLabel,
                                        bg: paymentBg,
                                        fg: paymentFg),
                                    if (hasRefund) const _RefundStatusBadge(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  cashierDisplayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                money0(sale.totalAmount),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.more_horiz,
                                  size: 22,
                                  color: Colors.black.withValues(alpha: 0.55)),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: saleNumberWidth,
                            child: Text(
                              saleNumber(sale),
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          SizedBox(
                            width: dateWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _DateBadge(
                                text: fmtSaleDate(sale.date),
                                bg: dateBg,
                                border: dateBorder,
                                fg: dateFg,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: statusWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
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
                          SizedBox(
                              width: cashierWidth,
                              child: Text(cashierDisplayName,
                                  overflow: TextOverflow.ellipsis)),
                          const Spacer(),
                          SizedBox(
                            width: amountWidth,
                            child: Text(
                              money0(sale.totalAmount),
                              textAlign: TextAlign.right,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.more_horiz,
                              size: 22, color: Color(0xFF7A837E)),
                        ],
                      ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFEFC),
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: [
                    BoxShadow(
                        color: cardShadow,
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
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
                    ),
                    const SizedBox(height: 14),
                    if (compact) ...[
                      RefundSummary(count: selectedCount, total: selectedTotal),
                      const SizedBox(height: 12),
                      BottomActionButton(
                        label:
                            selectedCount == 0 ? 'Возврат' : 'Оформить возврат',
                        width: actionWidth,
                        fontSize: 16,
                        bg: selectedCount == 0
                            ? const Color(0xFFB0B0B0)
                            : actionDarkMuted,
                        onTap: (selectedCount == 0 || refundLoading)
                            ? null
                            : onSubmitRefund,
                        loading: refundLoading,
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
                      BottomActionButton(
                        label: 'Распечатать чек',
                        width: actionWidth,
                        fontSize: 16,
                        bg: actionBlueMuted,
                        onTap: receiptPrintDisabled ? null : onPrintReceipt,
                        loading: receiptPrintLoading,
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                              child: RefundSummary(
                                  count: selectedCount, total: selectedTotal)),
                          const SizedBox(width: 12),
                          BottomActionButton(
                            label: selectedCount == 0
                                ? 'Возврат'
                                : 'Оформить возврат',
                            width: refundBtnWidth,
                            fontSize: 16,
                            bg: selectedCount == 0
                                ? const Color(0xFFB0B0B0)
                                : actionDarkMuted,
                            onTap: (selectedCount == 0 || refundLoading)
                                ? null
                                : onSubmitRefund,
                            loading: refundLoading,
                          ),
                          const SizedBox(width: 12),
                          BottomActionButton(
                              label: 'Накладная',
                              width: invoiceBtnWidth,
                              fontSize: 16,
                              bg: actionBlueMuted,
                              onTap:
                                  invoicePrintDisabled ? null : onPrintInvoice,
                              loading: invoicePrintLoading),
                          const SizedBox(width: 12),
                          BottomActionButton(
                              label: 'Распечатать чек',
                              width: printBtnWidth,
                              fontSize: 16,
                              bg: actionBlueMuted,
                              onTap:
                                  receiptPrintDisabled ? null : onPrintReceipt,
                              loading: receiptPrintLoading),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
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

class _DateBadge extends StatelessWidget {
  const _DateBadge({
    required this.text,
    required this.bg,
    required this.border,
    required this.fg,
  });

  final String text;
  final Color bg;
  final Color border;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
