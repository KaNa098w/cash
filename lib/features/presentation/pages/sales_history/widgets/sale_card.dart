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
    required this.onSubmitRefund,
    required this.onPrintReceipt,
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
  final VoidCallback onSubmitRefund;
  final VoidCallback onPrintReceipt;

  final int selectedCount;
  final num selectedTotal;

  final Map<String, RefundPick> picks;
  final void Function(SaleItemModel item, bool checked) onToggleItem;
  final void Function(SaleItemModel item, int qty) onQtyChanged;

  final int Function(SaleItemModel item) refundedQtyOf;
  final int Function(SaleItemModel item) availableQtyOf;

  static const _radius = 22.0;

  bool get isReturned => (sale.refund?.id ?? '').trim().isNotEmpty;

  String get statusLabel => isReturned ? 'Возвращен' : 'Закрыт';

  Color get statusBg =>
      isReturned ? const Color(0xFFFFE6D6) : const Color(0xFFCBE9C5);
  Color get statusFg =>
      isReturned ? const Color(0xFFB54708) : const Color(0xFF258808);
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
        final saleNumberWidth = desktopNarrow ? 150.0 : 205.0;
        final dateWidth = desktopNarrow ? 220.0 : 400.0;
        final statusWidth = desktopNarrow ? 130.0 : 180.0;
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
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
                              Flexible(
                                child: Text(
                                  fmtSaleDate(sale.date),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              StatusChip(
                                  label: statusLabel,
                                  bg: statusBg,
                                  fg: statusFg),
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
                                  color: Colors.black.withOpacity(0.55)),
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
                              child: Text(fmtSaleDate(sale.date),
                                  overflow: TextOverflow.ellipsis)),
                          SizedBox(
                            width: statusWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: StatusChip(
                                  label: statusLabel,
                                  bg: statusBg,
                                  fg: statusFg),
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
                          Icon(Icons.more_horiz,
                              size: 22, color: Colors.black.withOpacity(0.55)),
                        ],
                      ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
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
                        bg: selectedCount == 0
                            ? const Color(0xFFB0B0B0)
                            : const Color(0xFF7B7B7B),
                        onTap: (selectedCount == 0 || refundLoading)
                            ? null
                            : onSubmitRefund,
                        loading: refundLoading,
                      ),
                      const SizedBox(height: 12),
                      BottomActionButton(
                        label: 'Накладная',
                        width: actionWidth,
                        bg: const Color(0xFF21B3C0),
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      BottomActionButton(
                        label: 'Распечатать чек',
                        width: actionWidth,
                        bg: const Color(0xFF21B3C0),
                        onTap: onPrintReceipt,
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
                            bg: selectedCount == 0
                                ? const Color(0xFFB0B0B0)
                                : const Color(0xFF7B7B7B),
                            onTap: (selectedCount == 0 || refundLoading)
                                ? null
                                : onSubmitRefund,
                            loading: refundLoading,
                          ),
                          const SizedBox(width: 12),
                          BottomActionButton(
                              label: 'Накладная',
                              width: invoiceBtnWidth,
                              bg: const Color(0xFF21B3C0),
                              onTap: () {}),
                          const SizedBox(width: 12),
                          BottomActionButton(
                              label: 'Распечатать чек',
                              width: printBtnWidth,
                              bg: const Color(0xFF21B3C0),
                              onTap: onPrintReceipt),
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
