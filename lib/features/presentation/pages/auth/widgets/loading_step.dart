import 'package:flutter/material.dart';

class LoadingStep extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String subtitle;
  final double? progress;
  final String? stage;

  const LoadingStep({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    this.progress,
    this.stage,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress?.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle, style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black54)),
        const SizedBox(height: 14),
        if (p == null)
          const Center(child: CircularProgressIndicator())
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: p,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stage ?? 'Синхронизация данных',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: const Color(0xFF475569)),
                    ),
                  ),
                  Text(
                    '${(p * 100).round()}%',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        const Spacer(),
        Text(
          '© ${DateTime.now().year} POS Desktop',
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}
