import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final name = item.displayProductName;
    final unit = (item.product?.measurementUnit.trim().isNotEmpty ?? false)
        ? item.product!.measurementUnit
        : 'шт.';

    final refundedQty = refundedQtyOf(item);
    final maxQty = availableQtyOf(item);

    final qty = (pick?.quantity ?? 0).clamp(0, maxQty);
    final unitText = unit.trim().replaceAll('.', '');
    final qtyText =
        unitText == 'шт' ? '$qty шт' : '${qty.toStringAsFixed(2)} $unitText';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.zero,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    softWrap: true,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    )),
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
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                money2(item.price),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
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
                  onTap: (maxQty == 0 || qty >= maxQty)
                      ? null
                      : () => onQtyChanged(qty + 1),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    qtyText,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                QtyBtn(
                  icon: Icons.add,
                  onTap: qty <= 0 ? null : () => onQtyChanged(qty - 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              money2(item.totalPrice),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}
