import 'package:flutter/material.dart';
import 'package:leemon_app/core/models/pos_provision_response.dart';

class OpeningCashStep extends StatelessWidget {
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
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                user.name,
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
          'Открытие смены выполняется без ввода стартовой суммы.',
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54),
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
            onPressed: onSubmit,
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
