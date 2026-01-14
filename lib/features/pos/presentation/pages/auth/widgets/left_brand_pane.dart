import 'package:flutter/material.dart';

class LeftBrandPane extends StatelessWidget {
  const LeftBrandPane({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.95),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text('POS', style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          Text(
            'Касса\nDesktop',
            style: theme.textTheme.displaySmall!.copyWith(
              color: Colors.white,
              height: 1.05,
              fontWeight: FontWeight.w800,
              shadows: const [
                Shadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 2)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Быстро. Стабильно. Оффлайн/онлайн.',
            style: theme.textTheme.titleMedium!.copyWith(color: Colors.white70),
          ),
          const Spacer(),
          const MiniFeatures(),
        ],
      ),
    );
  }
}

class MiniFeatures extends StatelessWidget {
  const MiniFeatures({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: Colors.white.withOpacity(.9),
        );

    Widget pill(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(t, style: style),
        );

    return Wrap(
      children: [
        pill('Горячие клавиши'),
        pill('Работа без интернета'),
        pill('Импорт/Экспорт'),
        pill('Синхронизация'),
      ],
    );
  }
}
