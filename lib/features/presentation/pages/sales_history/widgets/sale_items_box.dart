import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sale_items_row.dart';

import '../models/refund_pick.dart';

class SaleItemsBox extends StatelessWidget {
  const SaleItemsBox({
    super.key,
    required this.items,
    required this.picks,
    required this.onToggleItem,
    required this.onQtyChanged,
    required this.refundedQtyOf,
    required this.availableQtyOf,
  });

  final List<SaleItemModel> items;
  final Map<String, RefundPick> picks;

  final void Function(SaleItemModel item, bool checked) onToggleItem;
  final void Function(SaleItemModel item, int qty) onQtyChanged;

  final int Function(SaleItemModel item) refundedQtyOf;
  final int Function(SaleItemModel item) availableQtyOf;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Нет позиций', style: TextStyle(color: Colors.black.withOpacity(0.55))),
            ),
          for (int i = 0; i < items.length; i++) ...[
            SaleItemRow(
              item: items[i],
              pick: picks[items[i].id.toString()],
              onToggle: (v) => onToggleItem(items[i], v),
              onQtyChanged: (q) => onQtyChanged(items[i], q),
              refundedQtyOf: refundedQtyOf,
              availableQtyOf: availableQtyOf,
            ),
            if (i != items.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Divider(height: 10, thickness: 1, color: Colors.black.withOpacity(0.06)),
              ),
          ],
        ],
      ),
    );
  }
}
