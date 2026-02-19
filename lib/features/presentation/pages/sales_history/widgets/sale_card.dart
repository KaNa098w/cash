import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';

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
    required this.expanded,
    required this.onToggle,
    required this.refundLoading,
    required this.onSubmitRefund,
    required this.selectedCount,
    required this.selectedTotal,
    required this.picks,
    required this.onToggleItem,
    required this.onQtyChanged,
    required this.refundedQtyOf,
    required this.availableQtyOf,
  });

  final SaleModel sale;
  final bool expanded;
  final VoidCallback onToggle;

  final bool refundLoading;
  final VoidCallback onSubmitRefund;

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

  Color get statusBg => isReturned ? const Color(0xFFFFE6D6) : const Color(0xFFCBE9C5);
  Color get statusFg => isReturned ? const Color(0xFFB54708) : const Color(0xFF258808);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 205,
                  child: Text(
                    saleNumber(sale),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 400, child: Text(fmtSaleDate(sale.date), overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: 180,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(label: statusLabel, bg: statusBg, fg: statusFg),
                  ),
                ),
                SizedBox(width: 250, child: Text(cashierLabel(sale), overflow: TextOverflow.ellipsis)),
                const Spacer(),
                SizedBox(
                  width: 140,
                  child: Text(
                    money0(sale.totalAmount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.more_horiz, size: 22, color: Colors.black.withOpacity(0.55)),
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
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, 6)),
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
                Row(
                  children: [
                    Expanded(child: RefundSummary(count: selectedCount, total: selectedTotal)),
                    const SizedBox(width: 12),
                    BottomActionButton(
                      label: selectedCount == 0 ? 'Выбери товары' : 'Оформить возврат',
                      width: 220,
                      bg: selectedCount == 0 ? const Color(0xFFB0B0B0) : const Color(0xFF7B7B7B),
                      onTap: (selectedCount == 0 || refundLoading) ? null : onSubmitRefund,
                      loading: refundLoading,
                    ),
                    const SizedBox(width: 12),
                    BottomActionButton(label: 'Накладная', width: 170, bg: const Color(0xFF21B3C0), onTap: () {}),
                    const SizedBox(width: 12),
                    BottomActionButton(label: 'Распечатать чек', width: 220, bg: const Color(0xFF21B3C0), onTap: () {}),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
