import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/presentation/pages/sales_history/widgets/sale_items_row.dart';

import '../models/refund_pick.dart';
import '../utils/formatters.dart';

class SaleItemsBox extends StatelessWidget {
  const SaleItemsBox({
    super.key,
    required this.items,
    required this.picks,
    required this.onToggleItem,
    required this.onQtyChanged,
    required this.refundedQtyOf,
    required this.availableQtyOf,
    this.selectable = true,
  });

  final List<SaleItemModel> items;
  final Map<String, RefundPick> picks;

  final void Function(SaleItemModel item, bool checked) onToggleItem;
  final void Function(SaleItemModel item, int qty) onQtyChanged;

  final int Function(SaleItemModel item) refundedQtyOf;
  final int Function(SaleItemModel item) availableQtyOf;
  final bool selectable;

  String _pickKey(SaleItemModel item) {
    final id = item.id.trim();
    if (id.isNotEmpty) return id;
    return item.productId.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          if (!selectable && items.isNotEmpty) ...[
            const _SaleItemsHeader(),
            const SizedBox(height: 4),
          ],
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Нет позиций',
                  style:
                      TextStyle(color: Colors.black.withValues(alpha: 0.55))),
            ),
          for (int i = 0; i < items.length; i++) ...[
            if (selectable)
              SaleItemRow(
                item: items[i],
                pick: picks[_pickKey(items[i])],
                onToggle: (v) => onToggleItem(items[i], v),
                onQtyChanged: (q) => onQtyChanged(items[i], q),
                refundedQtyOf: refundedQtyOf,
                availableQtyOf: availableQtyOf,
              )
            else
              _SaleItemPreviewRow(item: items[i]),
            if (i != items.length - 1) const SizedBox(height: 0),
          ],
        ],
      ),
    );
  }
}

class _SaleItemsHeader extends StatelessWidget {
  const _SaleItemsHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Color(0xFF6B7280),
    );

    return const Row(
      children: [
        SizedBox(width: 32),
        Expanded(flex: 30, child: Text('Товар', style: style)),
        Expanded(
          flex: 16,
          child: Padding(
            padding: EdgeInsets.only(right: 24),
            child: Text(
              'Цена',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ),
        Expanded(
          flex: 14,
          child: Text(
            'Количество',
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
        Expanded(
          flex: 14,
          child: Text(
            'Скидка',
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
        Expanded(
          flex: 18,
          child: Text(
            'Итого',
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _SaleItemPreviewRow extends StatelessWidget {
  const _SaleItemPreviewRow({required this.item});

  final SaleItemModel item;

  String get _unit {
    final unit = item.product?.measurementUnit.trim() ?? '';
    return unit.isEmpty ? 'шт' : unit;
  }

  String _qty(double value) {
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 30,
            child: Text(
              item.displayProductName,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 16,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Text(
                money2(item.basePrice),
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
          Expanded(
            flex: 14,
            child: Text(
              '${_qty(item.quantity)} $_unit',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(
              item.hasDiscount
                  ? '${item.discountPercent.toStringAsFixed(item.discountPercent % 1 == 0 ? 0 : 1)}%'
                  : '0%',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color:
                    item.hasDiscount ? const Color(0xFF179D72) : Colors.black,
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              money2(item.totalPrice),
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
        ],
      ),
    );
  }
}
