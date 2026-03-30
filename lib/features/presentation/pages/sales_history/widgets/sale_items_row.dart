import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/sale_model.dart';

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
    final cs = Theme.of(context).colorScheme;
    final name = item.product?.name ?? '-';
    final unit = (item.product?.measurementUnit.trim().isNotEmpty ?? false)
        ? item.product!.measurementUnit
        : 'шт.';

    final totalQty = toIntQty(item.quantity);
    final refundedQty = refundedQtyOf(item);
    final maxQty = availableQtyOf(item);

    final checked = pick?.checked ?? false;
    final qty = (pick?.quantity ?? 0).clamp(0, maxQty);
    final leftAfterPick = (maxQty - qty).clamp(0, maxQty);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: checked
            ? const Color(0xFFE9F6EF)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked
              ? const Color(0xFF34A853).withValues(alpha: 0.35)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Checkbox(
              value: checked,
              onChanged: maxQty == 0 ? null : (v) => onToggle(v ?? false),
              side: BorderSide(
                color: checked
                    ? const Color(0xFF34A853)
                    : cs.outline.withValues(alpha: 0.55),
                width: 1.4,
              ),
              activeColor: const Color(0xFF34A853),
              checkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  softWrap: true,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (refundedQty > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      returnedTextRu(refundedQty),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
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
              style: TextStyle(color: Colors.black.withValues(alpha: 0.75)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                QtyBtn(
                  icon: Icons.remove,
                  onTap: qty <= 0 ? null : () => onQtyChanged(qty - 1),
                ),
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
                  onTap: (maxQty == 0 || qty >= maxQty)
                      ? null
                      : () => onQtyChanged(qty + 1),
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
            child: Text(
              unit,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
