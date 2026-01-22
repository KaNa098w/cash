import 'package:flutter/material.dart';
import 'package:pos_desktop_clean/core/models/pos_provision_response.dart';
import 'package:pos_desktop_clean/features/pos/presentation/widgets/amount_keypad.dart';

class OpeningCashStep extends StatefulWidget {
  final ThemeData theme;
  final PosUser user;
  final VoidCallback onBack;
  final ValueChanged<num> onSubmit;

  const OpeningCashStep({
    super.key,
    required this.theme,
    required this.user,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  State<OpeningCashStep> createState() => _OpeningCashStepState();
}

class _OpeningCashStepState extends State<OpeningCashStep> {
  final _cashController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  num _parseAmount(String v) {
    final clean = v.trim().replaceAll(' ', '').replaceAll(',', '.');
    return num.tryParse(clean) ?? 0;
  }

  void _setAmountText(String v) {
    _cashController.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    setState(() {});
  }

  void _submit() {
    setState(() => _submitted = true);
    final amount = _parseAmount(_cashController.text);
    if (amount < 0) return;
    widget.onSubmit(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final amount = _parseAmount(_cashController.text);
    final showError = _submitted && amount < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                widget.user.name,
                style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Сумма открытия смены', style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 16),

        TextField(
          controller: _cashController,
          readOnly: true,
          showCursor: false,
          enableInteractiveSelection: false,
          decoration: InputDecoration(
            labelText: 'Сумма',
            hintText: 'Например: 10000',
            errorText: showError ? 'Сумма не может быть отрицательной' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),

        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submit,
            child: const Text('Открыть смену', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ),
        ),

        const SizedBox(height: 16),

        AmountKeypad(
          text: _cashController.text,
          onChanged: _setAmountText,
          allowDecimal: true,
          showQuickRows: true,
          rows: const [
            ['+200', '+500', '+1 000'],
            ['+2 000', '+5 000', '+10 000'],
          ],
        ),

        const SizedBox(height: 12),
        Text('© ${DateTime.now().year} POS Desktop', style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}
