import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';

class OpeningCashStep extends StatefulWidget {
  const OpeningCashStep({
    super.key,
    required this.theme,
    required this.user,
    required this.onBack,
    required this.onSubmit,
  });

  final ThemeData theme;
  final PosUser user;
  final VoidCallback onBack;
  final ValueChanged<num> onSubmit;

  @override
  State<OpeningCashStep> createState() => _OpeningCashStepState();
}

class _OpeningCashStepState extends State<OpeningCashStep> {
  final _controller = TextEditingController(text: '0');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  num? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return num.tryParse(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                widget.user.name,
                style: theme.textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Укажи стартовую сумму наличных для открытия смены.',
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Стартовая сумма в кассе',
            hintText: 'Например 5000',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onSubmitted: (_) {
            final amount = _parseAmount(_controller.text);
            if (amount == null || amount < 0) return;
            widget.onSubmit(amount);
          },
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              final amount = _parseAmount(_controller.text);
              if (amount == null || amount < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Введите корректную стартовую сумму'),
                  ),
                );
                return;
              }
              widget.onSubmit(amount);
            },
            child: const Text(
              'Открыть смену',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '© ${DateTime.now().year} POS Desktop',
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}
