import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RefundReasonOption {
  const RefundReasonOption({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;
}

const refundReasonOptions = <RefundReasonOption>[
  RefundReasonOption(
    code: 'customer_changed_mind',
    label: 'Покупатель передумал',
  ),
  RefundReasonOption(code: 'defective', label: 'Брак'),
  RefundReasonOption(
    code: 'damaged',
    label: 'Повреждение товара или упаковки',
  ),
  RefundReasonOption(code: 'expired', label: 'Просроченный товар'),
  RefundReasonOption(code: 'wrong_item', label: 'Продан не тот товар'),
  RefundReasonOption(code: 'incorrect_quantity', label: 'Ошибка в количестве'),
  RefundReasonOption(code: 'incorrect_price', label: 'Ошибка в цене'),
  RefundReasonOption(code: 'duplicate_sale', label: 'Товар пробит повторно'),
  RefundReasonOption(code: 'other', label: 'Другое'),
];

String refundReasonLabel(String? code) {
  final value = (code ?? '').trim();
  if (value.isEmpty) return '';
  for (final option in refundReasonOptions) {
    if (option.code == value) return option.label;
  }
  return value;
}

class RefundReasonSelector extends StatelessWidget {
  const RefundReasonSelector({
    super.key,
    required this.selectedCode,
    required this.onChanged,
    this.compact = false,
  });

  final String? selectedCode;
  final ValueChanged<String?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selected = (selectedCode ?? '').trim();

    final selectedValue =
        refundReasonOptions.any((o) => o.code == selected) ? selected : null;

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      isExpanded: true,
      borderRadius: BorderRadius.circular(12),
      decoration: InputDecoration(
        labelText: 'Причина возврата',
        hintText: 'Выберите причину',
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 10 : 13,
        ),
        suffixIcon: selectedValue == null
            ? null
            : IconButton(
                tooltip: 'Очистить',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        labelStyle: GoogleFonts.inter(
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF64748B),
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: compact ? 13 : 14,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF94A3B8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF33CC99), width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      style: GoogleFonts.inter(
        fontSize: compact ? 13 : 14,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF111827),
      ),
      items: [
        for (final option in refundReasonOptions)
          DropdownMenuItem<String>(
            value: option.code,
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
