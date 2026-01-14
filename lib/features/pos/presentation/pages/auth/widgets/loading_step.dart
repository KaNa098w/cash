import 'package:flutter/material.dart';

class LoadingStep extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String subtitle;

  const LoadingStep({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 18),
        const Center(child: CircularProgressIndicator()),
        const Spacer(),
        Text('© ${DateTime.now().year} POS Desktop', style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
      ],
    );
  }
}
