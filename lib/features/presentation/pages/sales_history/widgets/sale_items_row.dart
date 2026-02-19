import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/models/sale_model.dart';

import '../models/refund_pick.dart';
import '../utils/formatters.dart';
import 'qty_btn.dart';

class SaleItemRow extends StatelessWidget {
  const SaleItemRow({
    super.key,
    required this.item,
    required this.pick,
    required this.onToggle,
    required this.onQtyChanged,
    required this.refundedQtyOf,
    required this.availableQtyOf,
  });

  final SaleItemModel item;
  final RefundPick? pick;

  final void Function(bool v) onToggle;
  final void Function(int q) onQtyChanged;

  final int Function(SaleItemModel item) refundedQtyOf;
  final int Function(SaleItemModel item) availableQtyOf;

  @override
  Widget build(BuildContext context) {
    final name = item.product?.name ?? '—';
    final unit = (item.product?.measurementUnit.trim().isNotEmpty ?? false)
        ? item.product!.measurementUnit
        : 'шт.';

    final totalQty = toIntQty(item.quantity);
    final refundedQty = refundedQtyOf(item);
    final maxQty = availableQtyOf(item);

    final checked = pick?.checked ?? false;
    final qty = (pick?.quantity ?? 0).clamp(0, maxQty);
    final leftAfterPick = (maxQty - qty).clamp(0, maxQty);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Checkbox(
              value: checked,
              onChanged: maxQty == 0 ? null : (v) => onToggle(v ?? false),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (refundedQty > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      returnedTextRu(refundedQty),
                      style: TextStyle(fontSize: 14, color: Colors.black.withOpacity(0.55)),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              money0(item.price),
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.black.withOpacity(0.75)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                QtyBtn(icon: Icons.remove, onTap: qty <= 0 ? null : () => onQtyChanged(qty - 1)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$leftAfterPick/$totalQty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                QtyBtn(
                  icon: Icons.add,
                  onTap: (maxQty == 0 || qty >= maxQty) ? null : () => onQtyChanged(qty + 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              money0(toNum(item.price) * qty),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(unit, textAlign: TextAlign.right, style: TextStyle(color: Colors.black.withOpacity(0.6))),
          ),
        ],
      ),
    );
  }
}
