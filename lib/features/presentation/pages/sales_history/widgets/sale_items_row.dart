import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:leemon_app/core/models/sale_model.dart';
import 'package:leemon_app/features/presentation/widgets/keypad_widget.dart';

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
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: maxQty <= 0
                      ? null
                      : () async {
                          final selectedQty = await _showRefundQtyDialog(
                            context,
                            productName: name,
                            initialQty: qty,
                            maxQty: maxQty,
                            unit: unitText,
                          );
                          if (selectedQty != null) {
                            onQtyChanged(selectedQty);
                          }
                        },
                  child: SizedBox(
                    width: 64,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
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
            width: 100,
            child: Text(
              item.hasDiscount
                  ? '${item.discountPercent.toStringAsFixed(item.discountPercent % 1 == 0 ? 0 : 1)}%'
                  : '0%',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color:
                    item.hasDiscount ? const Color(0xFF179D72) : Colors.black,
              ),
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

Future<int?> _showRefundQtyDialog(
  BuildContext context, {
  required String productName,
  required int initialQty,
  required int maxQty,
  required String unit,
}) async {
  final controller = TextEditingController(text: '$initialQty');

  void selectAll() {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  final result = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final parsed = int.tryParse(controller.text);
        final isValid = parsed != null && parsed >= 0 && parsed <= maxQty;

        void inputToken(String token) {
          var text = controller.text;
          final selection = controller.selection;
          final start = selection.isValid ? selection.start : text.length;
          final end = selection.isValid ? selection.end : text.length;
          final from = start < end ? start : end;
          final to = start < end ? end : start;

          if (token == '⌫') {
            if (from != to) {
              text = text.replaceRange(from, to, '');
            } else if (from > 0) {
              text = text.replaceRange(from - 1, from, '');
            }
          } else if (RegExp(r'^\d$').hasMatch(token)) {
            text = text.replaceRange(from, to, token);
          } else {
            return;
          }

          text = text.replaceFirst(RegExp(r'^0+(?=\d)'), '');
          setState(() {
            controller.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
          });
        }

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Изменить количество возврата',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Доступно для возврата: $maxQty $unit',
                      style: const TextStyle(color: Color(0xFF4B5563)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      errorText: controller.text.isNotEmpty && !isValid
                          ? 'Введите число от 0 до $maxQty'
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onTap: selectAll,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (isValid) Navigator.of(dialogContext).pop(parsed);
                    },
                  ),
                  const SizedBox(height: 16),
                  Keypad(keyHeight: 54, fontSize: 20, onTap: inputToken),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            fixedSize: const Size.fromHeight(56),
                          ),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isValid
                              ? () => Navigator.of(dialogContext).pop(parsed)
                              : null,
                          style: ElevatedButton.styleFrom(
                            fixedSize: const Size.fromHeight(56),
                            backgroundColor: const Color(0xFF456B5A),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Готово'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  controller.dispose();
  return result;
}
