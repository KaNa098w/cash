import 'package:flutter/material.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('POS Desktop', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Войдите в кассу, чтобы продолжить', style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        )),
      ],
    );
  }
}
