import 'package:flutter/material.dart';
import 'package:leemon_app/features/presentation/pages/auth/widgets/pos_diagnostics_dialog.dart';

class ProductsErrorStep extends StatelessWidget {
  const ProductsErrorStep({
    super.key,
    required this.theme,
    required this.message,
    required this.onRetry,
    required this.onBack,
    this.onOpenDiagnostics,
  });

  final ThemeData theme;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback? onOpenDiagnostics;

  void _openDiagnostics(BuildContext context) {
    final open = onOpenDiagnostics ?? () => showPosDiagnosticsDialog(context);
    open();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Не удалось загрузить товары',
          style: theme.textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium!.copyWith(
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD45F4F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Повторить',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Назад',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => _openDiagnostics(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Подробнее',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const Spacer(),
        Text(
          '© ${DateTime.now().year} POS Desktop',
          style: theme.textTheme.bodySmall!.copyWith(
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
